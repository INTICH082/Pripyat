class_name PlayerController
extends CharacterBody3D

## Первоклассный 1st-person контроллер с поддержкой переноса физических объектов
## и послойной очистки поверхностей (в духе friendslop / cleaning games).

enum ToolMode { HANDS, BRUSH, WEAPON }

@export_group("Движение")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.0
@export var jump_velocity: float = 4.2
@export var acceleration: float = 12.0
@export var friction: float = 10.0
@export var gravity: float = 14.0

@export_group("Камера и Обзор")
@export var mouse_sensitivity: float = 0.0025
@export var max_pitch: float = 85.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_ray: RayCast3D = $Head/Camera3D/InteractionRay
@onready var hold_socket: Node3D = $Head/Camera3D/HoldSocket
@onready var tool_model: Node3D = $Head/Camera3D/ToolAnchor
@onready var cleaner_model: Node3D = get_node_or_null("CleanerModel")
@onready var weapon_manager: WeaponManager = get_node_or_null("Head/Camera3D/WeaponManager")

var anim_player: AnimationPlayer = null
var current_tool: ToolMode = ToolMode.HANDS
var held_trash: CarryableTrash = null
var current_prompt: String = ""

# Покачивание головы (Head Bob)
var bob_time: float = 0.0
const BOB_FREQ: float = 2.4
const BOB_AMP: float = 0.04

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if cleaner_model:
		_setup_shadow_only(cleaner_model)
		anim_player = cleaner_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim_player and anim_player.has_animation("Unarmed_Idle-loop"):
			anim_player.play("Unarmed_Idle-loop")
			
	_update_tool_display()

func _setup_shadow_only(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for child in node.get_children():
		_setup_shadow_only(child)

func _unhandled_input(event: InputEvent) -> void:
	# Захват мыши / выход по Esc
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Вращение камеры от 1-го лица
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-max_pitch), deg_to_rad(max_pitch))

	# Переключение инструментов (1 - Руки, 2 - Щётка, 3 - Оружие)
	if event.is_action_pressed("tool_hands"):
		_set_tool(ToolMode.HANDS)
	elif event.is_action_pressed("tool_brush"):
		_set_tool(ToolMode.BRUSH)
	elif event.is_action_pressed("weapon_mode"):
		_set_tool(ToolMode.WEAPON)
	elif current_tool == ToolMode.WEAPON and weapon_manager:
		if event.is_action_pressed("reload"):
			weapon_manager.reload()
		elif event.is_action_pressed("weapon_next"):
			weapon_manager.next_weapon()
		elif event.is_action_pressed("weapon_prev"):
			weapon_manager.prev_weapon()
		elif event is InputEventMouseButton and event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				weapon_manager.next_weapon()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				weapon_manager.prev_weapon()
	elif event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_tool(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_tool(-1)

func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_handle_interaction(delta)
	_apply_head_bob(delta)
	_update_character_animation()
	
	# Обновление FPS-анимации рук в зависимости от скорости ходьбы/бега
	if weapon_manager and (current_tool == ToolMode.WEAPON or (current_tool == ToolMode.HANDS and held_trash == null)):
		var flat_speed = Vector2(velocity.x, velocity.z).length()
		var is_sprinting = Input.is_action_pressed("sprint") and flat_speed > 5.0
		weapon_manager.update_movement_animation(flat_speed, is_sprinting)

func _update_character_animation() -> void:
	if not anim_player:
		return
	var flat_speed = Vector2(velocity.x, velocity.z).length()
	var prefix = "Unarmed_"
	
	if not is_on_floor():
		var jump_anim = prefix + "Jump"
		if anim_player.has_animation(jump_anim) and anim_player.current_animation != jump_anim:
			anim_player.play(jump_anim)
	elif flat_speed > 5.0:
		var run_anim = prefix + "Run-loop"
		if anim_player.has_animation(run_anim) and anim_player.current_animation != run_anim:
			anim_player.play(run_anim)
	elif flat_speed > 0.2:
		var walk_anim = prefix + "Walk-loop"
		if anim_player.has_animation(walk_anim) and anim_player.current_animation != walk_anim:
			anim_player.play(walk_anim)
	else:
		var idle_anim = prefix + "Idle-loop"
		if anim_player.has_animation(idle_anim) and anim_player.current_animation != idle_anim:
			anim_player.play(idle_anim)

func _handle_movement(delta: float) -> void:
	# Гравитация
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Прыжок
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Направление движения
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var target_speed = sprint_speed if Input.is_action_pressed("sprint") else walk_speed

	if direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, direction.x * target_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

	move_and_slide()

func _handle_interaction(delta: float) -> void:
	current_prompt = ""
	var collider = interaction_ray.get_collider()

	# 1. Если мы держим мусор в руках
	if held_trash != null:
		if collider is TrashBin:
			current_prompt = "[E] Выбросить в контейнер"
			if Input.is_action_just_pressed("interact"):
				var bin = collider as TrashBin
				var trash = held_trash
				held_trash = null
				trash.drop(Vector3.ZERO)
				bin.deposit_direct(trash)
				return
		else:
			current_prompt = "[E / G] Бросить мусор  |  [ЛКМ] Метнуть"
			
		if Input.is_action_just_pressed("drop") or Input.is_action_just_pressed("interact"):
			_drop_held_trash(Vector3.ZERO)
		elif Input.is_action_just_pressed("primary_action"):
			# Метнуть вперёд
			var throw_dir = -camera.global_transform.basis.z
			_drop_held_trash(throw_dir)
		return

	# 2. Если руки свободны (Режим HANDS)
	if current_tool == ToolMode.HANDS:
		if collider is CarryableTrash:
			var trash = collider as CarryableTrash
			current_prompt = "[E] Взять %s" % trash.trash_name
			if Input.is_action_just_pressed("interact"):
				_pickup_trash(trash)
		elif collider is TrashBin:
			current_prompt = "Контейнер для отходов Припяти"
		else:
			current_prompt = "[ЛКМ] Удар кулаком  |  [E] Взять мусор"
			if Input.is_action_just_pressed("primary_action"):
				if weapon_manager:
					weapon_manager.primary_attack()

	# 3. Если в руках инструмент (Режим BRUSH / Щетка)
	elif current_tool == ToolMode.BRUSH:
		var dirt_spot = _find_dirt_spot(collider)
		if dirt_spot:
			current_prompt = "[ЛКМ] Соскрести загрязнение"
			if Input.is_action_pressed("primary_action"):
				dirt_spot.scrub(delta)
				_animate_tool_action()
		else:
			if collider != null:
				current_prompt = "Направьте на грязь, мох или пыль"

	# 4. Если в руках оружие (Режим WEAPON)
	elif current_tool == ToolMode.WEAPON:
		if weapon_manager and weapon_manager.current_weapon:
			var w = weapon_manager.current_weapon
			var mag = weapon_manager.current_mags.get(w.id, 0)
			var res = weapon_manager.ammo_reserves.get(w.ammo_type, 0)
			if w.is_melee:
				current_prompt = "[ЛКМ] Удар: %s  |  [[ / ]] Смена оружия" % w.display_name
			elif w.is_flamethrower:
				current_prompt = "[ЛКМ] Струя огня (%d л)  |  [R] Заправка  |  [[ / ]] Смена" % mag
			else:
				current_prompt = "[ЛКМ] Огонь [%d / %d]  |  [R] Перезарядка  |  [[ / ]] Смена" % [mag, res]
				
			if w.fire_rate > 300 or w.is_flamethrower:
				if Input.is_action_pressed("primary_action"):
					weapon_manager.primary_attack()
			else:
				if Input.is_action_just_pressed("primary_action"):
					weapon_manager.primary_attack()

func _find_dirt_spot(node: Node) -> DirtSpot:
	if node is DirtSpot:
		return node
	if node and node.get_parent() is DirtSpot:
		return node.get_parent() as DirtSpot
	return null

func _pickup_trash(trash: CarryableTrash) -> void:
	held_trash = trash
	trash.pickup(hold_socket)
	if weapon_manager:
		weapon_manager.set_viewmodel_visible(false)

func _drop_held_trash(impulse_dir: Vector3) -> void:
	if held_trash:
		var trash = held_trash
		held_trash = null
		trash.drop(impulse_dir)
		if current_tool == ToolMode.HANDS and weapon_manager:
			weapon_manager.set_tool_mode_hands(true)

func _set_tool(mode: ToolMode) -> void:
	if held_trash != null:
		# Сначала выбрасываем то, что в руках
		_drop_held_trash(Vector3.ZERO)
		
	current_tool = mode
	_update_tool_display()

func _cycle_tool(direction: int) -> void:
	var next_mode = (current_tool + direction) % ToolMode.size()
	if next_mode < 0:
		next_mode += ToolMode.size()
	_set_tool(next_mode as ToolMode)

func _update_tool_display() -> void:
	var mode_name = ""
	match current_tool:
		ToolMode.HANDS:
			mode_name = "Руки (перенос мусора / кулачный бой)"
			if tool_model: tool_model.visible = false
			if weapon_manager:
				weapon_manager.set_tool_mode_hands(held_trash == null)
		ToolMode.BRUSH:
			mode_name = "Щётка / Скребок (очистка поверхностей)"
			if tool_model: tool_model.visible = true
			if weapon_manager:
				weapon_manager.set_tool_mode_brush()
		ToolMode.WEAPON:
			var w_name = weapon_manager.current_weapon.display_name if (weapon_manager and weapon_manager.current_weapon) else "Оружие"
			mode_name = "Оружие: %s" % w_name
			if tool_model: tool_model.visible = false
			if weapon_manager:
				weapon_manager.set_tool_mode_weapon()
			
	EventBus.tool_changed.emit(current_tool, mode_name)

func _animate_tool_action() -> void:
	# Легкая анимация покачивания инструмента при чистке
	if tool_model and tool_model.visible:
		tool_model.rotation_degrees.z = sin(Time.get_ticks_msec() * 0.03) * 8.0

func _apply_head_bob(delta: float) -> void:
	var flat_velocity = Vector2(velocity.x, velocity.z).length()
	if flat_velocity > 0.5 and is_on_floor():
		bob_time += delta * flat_velocity
		camera.position.y = sin(bob_time * BOB_FREQ) * BOB_AMP
		camera.position.x = cos(bob_time * BOB_FREQ * 0.5) * (BOB_AMP * 0.5)
	else:
		bob_time = 0.0
		camera.position.y = move_toward(camera.position.y, 0.0, delta * 0.2)
		camera.position.x = move_toward(camera.position.x, 0.0, delta * 0.2)
