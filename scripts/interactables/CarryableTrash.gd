class_name CarryableTrash
extends RigidBody3D

## Физический мусор, который игрок может брать в руки и носить в контейнеры.

@export var trash_name: String = "Советский мусор"
@export var reward_rubles: int = 5
@export var throw_force: float = 6.0

var is_carried: bool = false
var is_deposited: bool = false
var original_collision_layer: int = 1
var original_collision_mask: int = 1

func _ready() -> void:
	original_collision_layer = collision_layer
	original_collision_mask = collision_mask
	add_to_group("trash")
	
	# Регистрируем объект в общем счётчике чистоты локации
	if GameState:
		GameState.register_cleanup_item()

func pickup(holder: Node3D) -> void:
	if is_carried:
		return
	is_carried = true
	freeze = true
	collision_layer = 0
	collision_mask = 0
	
	reparent(holder)
	transform.origin = Vector3.ZERO
	rotation = Vector3.ZERO
	EventBus.trash_picked_up.emit(self)

func drop(throw_impulse_dir: Vector3 = Vector3.ZERO) -> void:
	if not is_carried:
		return
	is_carried = false
	
	# Возвращаем в корень сцены мира
	var world_root = get_tree().current_scene
	var prev_transform = global_transform
	reparent(world_root)
	global_transform = prev_transform
	
	collision_layer = original_collision_layer
	collision_mask = original_collision_mask
	freeze = false
	
	if throw_impulse_dir != Vector3.ZERO:
		global_position += throw_impulse_dir.normalized() * 0.2
		apply_central_impulse(throw_impulse_dir * throw_force)
	
	EventBus.trash_dropped.emit(self)

func deposit_into_bin() -> void:
	if is_deposited:
		return
	is_deposited = true
	freeze = true
	collision_layer = 0
	collision_mask = 0
	
	# Вызывается баком при утилизации
	EventBus.trash_deposited.emit(trash_name, reward_rubles)
	
	# Плавная анимация уменьшения и исчезновения
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
