class_name PlayerController
extends CharacterBody3D

## Первоклассный 1st-person контроллер с поддержкой переноса физических объектов
## и послойной очистки поверхностей (в духе friendslop / cleaning games).

enum ToolMode { HANDS, BRUSH }

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

var current_tool: ToolMode = ToolMode.HANDS
var held_trash: CarryableTrash = null
var current_prompt: String = ""

# Покачивание головы (Head Bob)
var bob_time: float = 0.0
const BOB_FREQ: float = 2.4
const BOB_AMP: float = 0.04

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_update_tool_display()

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

	# Переключение инструментов (1 - Руки, 2 - Щётка, Колесо мыши)
	if event.is_action_pressed("tool_hands"):
		_set_tool(ToolMode.HANDS)
	elif event.is_action_pressed("tool_brush"):
		_set_tool(ToolMode.BRUSH)
	elif event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_tool(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_tool(-1)

func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_handle_interaction(delta)
	_apply_head_bob(delta)

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

func _find_dirt_spot(node: Node) -> DirtSpot:
	if node is DirtSpot:
		return node
	if node and node.get_parent() is DirtSpot:
		return node.get_parent() as DirtSpot
	return null

func _pickup_trash(trash: CarryableTrash) -> void:
	held_trash = trash
	trash.pickup(hold_socket)

func _drop_held_trash(impulse_dir: Vector3) -> void:
	if held_trash:
		var trash = held_trash
		held_trash = null
		trash.drop(impulse_dir)

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
	var mode_name = "Руки (перенос мусора)" if current_tool == ToolMode.HANDS else "Щётка / Скребок (очистка поверхностей)"
	EventBus.tool_changed.emit(current_tool, mode_name)
	if tool_model:
		tool_model.visible = (current_tool == ToolMode.BRUSH)

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
