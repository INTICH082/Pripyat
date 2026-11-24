class_name CarryableTrash
extends RigidBody3D

## Физический мусор с удержанием через физические силы.
## Препятствует проникновению сквозь стены при переноске, сохраняет коллизии с миром
## и передает импульс броска с учетом движения игрока.

@export var trash_name: String = "Советский мусор"
@export var reward_rubles: int = 5
@export var throw_force: float = 7.5
@export var follow_speed: float = 16.0
@export var max_hold_distance: float = 2.4

var is_carried: bool = false
var is_deposited: bool = false
var current_holder: Node3D = null
var carrying_player: CharacterBody3D = null

var original_collision_layer: int = 1
var original_collision_mask: int = 1
var original_linear_damp: float = 0.0
var original_angular_damp: float = 0.0

func _ready() -> void:
	original_collision_layer = collision_layer
	original_collision_mask = collision_mask
	original_linear_damp = linear_damp
	original_angular_damp = angular_damp
	continuous_cd = true
	add_to_group("trash")
	
	if GameState:
		GameState.register_cleanup_item()

func pickup(holder: Node3D, player_ref: CharacterBody3D = null) -> void:
	if is_carried or is_deposited:
		return
		
	is_carried = true
	current_holder = holder
	carrying_player = player_ref
	
	freeze = false
	gravity_scale = 0.0
	linear_damp = 10.0
	angular_damp = 10.0
	
	# Объект сталкивается с окружающим миром (слой 1), но не блокирует капсулу игрока (слой 2)
	collision_layer = 4 # Выделенный слой переносимых предметов
	collision_mask = 1  # Коллизия со статичным миром
	
	EventBus.trash_picked_up.emit(self)

func _physics_process(delta: float) -> void:
	if not is_carried or not current_holder:
		return
		
	var target_pos = current_holder.global_position
	
	# Проверка препятствий лучом от камеры к сокету (защита от проталкивания сквозь стену)
	var space_state = get_world_3d().direct_space_state
	var cam_pos = current_holder.global_position + (current_holder.global_transform.basis.z * 0.8)
	var ray_query = PhysicsRayQueryParameters3D.create(cam_pos, target_pos, 1)
	ray_query.exclude = [self.get_rid()]
	if carrying_player:
		ray_query.exclude.append(carrying_player.get_rid())
		
	var hit = space_state.intersect_ray(ray_query)
	if not hit.is_empty():
		target_pos = hit.position - (current_holder.global_transform.basis.z * 0.15)
		
	var to_target = target_pos - global_position
	var dist = to_target.length()
	
	# Если предмет застрял за углом или слишком далеко - мягко роняем его
	if dist > max_hold_distance:
		drop(Vector3.ZERO)
		return
		
	# Физическое перемещение силой скорости (smooth spring)
	linear_velocity = to_target * follow_speed
	
	# Плавное выравнивание ориентации
	var target_basis = current_holder.global_transform.basis
	var current_quat = global_transform.basis.get_rotation_quaternion()
	var target_quat = target_basis.get_rotation_quaternion()
	var slerped_quat = current_quat.slerp(target_quat, 12.0 * delta)
	global_basis = Basis(slerped_quat)

func drop(throw_impulse_dir: Vector3 = Vector3.ZERO) -> void:
	if not is_carried:
		return
		
	is_carried = false
	current_holder = null
	
	gravity_scale = 1.0
	linear_damp = original_linear_damp
	angular_damp = original_angular_damp
	collision_layer = original_collision_layer
	collision_mask = original_collision_mask
	
	if throw_impulse_dir != Vector3.ZERO:
		var extra_vel = carrying_player.velocity * 0.6 if carrying_player else Vector3.ZERO
		linear_velocity = extra_vel
		apply_central_impulse(throw_impulse_dir.normalized() * throw_force)
		apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 1.5)
		
	carrying_player = null
	EventBus.trash_dropped.emit(self)

func deposit_into_bin() -> void:
	if is_deposited:
		return
	if NetworkManager and NetworkManager.is_multiplayer_active():
		rpc_deposit_into_bin.rpc()
	else:
		_execute_deposit()

@rpc("any_peer", "call_local", "reliable")
func rpc_deposit_into_bin() -> void:
	_execute_deposit()

func _execute_deposit() -> void:
	if is_deposited:
		return
	is_deposited = true
	is_carried = false
	current_holder = null
	carrying_player = null
	
	freeze = true
	collision_layer = 0
	collision_mask = 0
	
	EventBus.trash_deposited.emit(trash_name, reward_rubles)
	
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.001, 0.001, 0.001), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
