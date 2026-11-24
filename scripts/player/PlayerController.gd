class_name PlayerController
extends CharacterBody3D

## Первоклассный 1st-person контроллер с поддержкой динамической смены классов,
## физического переноса предметов и высокопроизводительной очистки поверхностей.

enum ToolMode { HANDS, BRUSH, WEAPON }

@export_group("Движение")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.5
@export var crouch_speed: float = 2.2
@export var jump_velocity: float = 4.8
@export var acceleration: float = 12.0
@export var friction: float = 10.0
@export var gravity: float = 14.0

@export_group("Камера и Обзор")
@export var mouse_sensitivity: float = 0.0025
@export var max_pitch: float = 89.5

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_ray: RayCast3D = $Head/Camera3D/InteractionRay
@onready var hold_socket: Node3D = $Head/Camera3D/HoldSocket
@onready var tool_model: Node3D = $Head/Camera3D/ToolAnchor
@onready var cleaner_model: Node3D = get_node_or_null("CleanerModel")
@onready var weapon_manager: WeaponManager = get_node_or_null("Head/Camera3D/WeaponManager")
@onready var nametag: Node3D = get_node_or_null("Nametag")
@onready var name_label: Label3D = get_node_or_null("Nametag/NameLabel")

var anim_player: AnimationPlayer = null
var current_tool: ToolMode = ToolMode.WEAPON
var held_trash: CarryableTrash = null
var current_prompt: String = ""

# Мультиплеер и сетевая идентификация
var peer_id: int = 1
var player_name: String = "Ликвидатор"
var class_id: String = "cleaner"
var target_pos: Vector3 = Vector3.ZERO
var target_rot_y: float = 0.0
var target_head_pitch: float = 0.0
var target_velocity: Vector3 = Vector3.ZERO
var target_crouch: bool = false

# Параметры приседания
var is_crouching: bool = false
const STANDING_HEIGHT: float = 1.75
const CROUCHING_HEIGHT: float = 1.10
const STANDING_HEAD_Y: float = 1.665
const CROUCHING_HEAD_Y: float = 1.05

# Покачивание головы (Head Bob)
var bob_time: float = 0.0
const BOB_FREQ: float = 2.4
const BOB_AMP: float = 0.035

func _ready() -> void:
	target_pos = global_position
	target_rot_y = rotation.y
	target_head_pitch = head.rotation.x
	
	var is_auth = is_multiplayer_authority()
	
	if is_auth:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		camera.current = true
		if camera and GameState:
			camera.fov = GameState.camera_fov
		if nametag:
			nametag.visible = false
		if cleaner_model:
			_setup_shadow_only(cleaner_model)
		if weapon_manager:
			weapon_manager.set_viewmodel_visible(true)
	else:
		camera.current = false
		if nametag:
			nametag.visible = true
		if cleaner_model:
			_setup_full_visibility(cleaner_model)
		if weapon_manager:
			weapon_manager.set_viewmodel_visible(false)
		
	EventBus.character_class_changed.connect(_on_character_class_changed)
	
	if cleaner_model:
		anim_player = _find_animation_player(cleaner_model)
		if anim_player:
			var idle_name = _resolve_anim_name(anim_player, "Unarmed_Idle-loop")
			if idle_name != "":
				anim_player.play(idle_name)
			
	if is_auth:
		_update_tool_display()

func setup_player(player_info: Dictionary) -> void:
	peer_id = player_info.get("peer_id", 1)
	player_name = player_info.get("name", "Ликвидатор")
	class_id = player_info.get("class_id", "cleaner")
	
	set_multiplayer_authority(peer_id)
	var is_auth = is_multiplayer_authority()
	
	if nametag:
		nametag.visible = not is_auth
	if name_label:
		name_label.text = "%s\n[%s]" % [player_name, _get_class_display_name(class_id)]
		
	if is_auth:
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if weapon_manager:
			weapon_manager.set_viewmodel_visible(true)
		if cleaner_model:
			_setup_shadow_only(cleaner_model)
		if GameState:
			GameState.set_class(class_id)
	else:
		camera.current = false
		if weapon_manager:
			weapon_manager.set_viewmodel_visible(false)
		_apply_class_model(class_id, false)

func _get_class_display_name(c_id: String) -> String:
	match c_id:
		"cleaner": return "Чистильщик"
		"soldier": return "Штурмовик"
		"medic": return "Медик"
		"engineer": return "Инженер"
	return "Ликвидатор"

func _apply_class_model(c_id: String, shadow_only: bool) -> void:
	class_id = c_id
	var def = GameState.CLASS_DEFINITIONS.get(c_id, {}) if GameState else {}
	var body_path = def.get("body_model_path", "")
	if body_path != "" and ResourceLoader.exists(body_path):
		if cleaner_model:
			cleaner_model.queue_free()
		var scene = ResourceLoader.load(body_path) as PackedScene
		if scene:
			var new_body = scene.instantiate() as Node3D
			new_body.name = "CleanerModel"
			new_body.transform = Transform3D(Basis(Vector3(0, 1, 0), deg_to_rad(180)), Vector3.ZERO)
			add_child(new_body)
			cleaner_model = new_body
			if shadow_only:
				_setup_shadow_only(cleaner_model)
			else:
				_setup_full_visibility(cleaner_model)
			anim_player = _find_animation_player(cleaner_model)
			if anim_player:
				var idle_name = _resolve_anim_name(anim_player, "Unarmed_Idle-loop")
				if idle_name != "":
					anim_player.play(idle_name)

func _setup_full_visibility(node: Node) -> void:
	if not node:
		return
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.visible = true
	for child in node.get_children():
		_setup_full_visibility(child)

func _on_character_class_changed(p_class_id: String, class_data: Dictionary) -> void:
	if not is_multiplayer_authority():
		return
	class_id = p_class_id
	# Смена 3D-модели тела от третьего лица
	var body_path = class_data.get("body_model_path", "")
	if body_path != "" and ResourceLoader.exists(body_path):
		if cleaner_model:
			cleaner_model.queue_free()
		var scene = ResourceLoader.load(body_path) as PackedScene
		if scene:
			var new_body = scene.instantiate() as Node3D
			new_body.name = "CleanerModel"
			# Модель развернута лицом вперед (-Z)
			new_body.transform = Transform3D(Basis(Vector3(0, 1, 0), deg_to_rad(180)), Vector3.ZERO)
			add_child(new_body)
			cleaner_model = new_body
			_setup_shadow_only(cleaner_model)
			anim_player = _find_animation_player(cleaner_model)
			if anim_player:
				var idle_name = _resolve_anim_name(anim_player, "Unarmed_Idle-loop")
				if idle_name != "":
					anim_player.play(idle_name)
					
	# Смена FPS-модели рук и оружия
	var fps_path = class_data.get("fps_model_path", "")
	if fps_path != "" and weapon_manager and ResourceLoader.exists(fps_path):
		var fps_scene = ResourceLoader.load(fps_path) as PackedScene
		if fps_scene:
			weapon_manager.change_character_fps_model(fps_scene)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if not node:
		return null
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if found:
			return found
	return null

func _resolve_anim_name(player: AnimationPlayer, suffix: String) -> String:
	if not player:
		return ""
	if player.has_animation(suffix):
		return suffix
	for a in player.get_animation_list():
		if a == suffix or a.ends_with("/" + suffix) or a.ends_with(":" + suffix):
			return a
	return ""

func _setup_shadow_only(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for child in node.get_children():
		_setup_shadow_only(child)

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
		
	# Выход / захват мыши по Esc
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Вращение камеры от 1-го лица (как в Blender)
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var sens = GameState.mouse_sensitivity if GameState else mouse_sensitivity
		var invert = -1.0 if (GameState and GameState.invert_y) else 1.0
		rotate_y(-event.relative.x * sens)
		head.rotate_x(-event.relative.y * sens * invert)
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
	if is_multiplayer_authority():
		_handle_movement(delta)
		_handle_interaction(delta)
		_apply_head_bob(delta)
		_update_character_animation()
		
		if weapon_manager and (current_tool == ToolMode.WEAPON or (current_tool == ToolMode.HANDS and held_trash == null)):
			var flat_speed = Vector2(velocity.x, velocity.z).length()
			var is_sprinting = Input.is_action_pressed("sprint") and flat_speed > 4.0 and not is_crouching and is_on_floor()
			weapon_manager.update_movement_animation(flat_speed, is_sprinting, is_crouching, not is_on_floor())
			
		if NetworkManager and NetworkManager.is_multiplayer_active():
			sync_transform.rpc(global_position, rotation.y, head.rotation.x, velocity, is_crouching)
	else:
		global_position = global_position.lerp(target_pos, 18.0 * delta)
		rotation.y = lerp_angle(rotation.y, target_rot_y, 18.0 * delta)
		head.rotation.x = lerp_angle(head.rotation.x, target_head_pitch, 18.0 * delta)
		velocity = target_velocity
		is_crouching = target_crouch
		_update_character_animation()

func _get_body_anim_prefix() -> String:
	if current_tool == ToolMode.HANDS or current_tool == ToolMode.BRUSH or not weapon_manager or not weapon_manager.current_weapon:
		return "Unarmed_"
	var wid = weapon_manager.current_weapon.id
	if wid == "02_crowbar":
		return "Crowbar_"
	elif wid == "03_spade":
		return "Spade_"
	elif wid in ["05_pistol_pl", "06_pistol_pt"]:
		return "Dozor_"
	elif wid in ["07_rifle_al", "08_rifle_at"]:
		return "Rubezh_"
	elif wid in ["09_rifle_vl", "10_rifle_vt"]:
		return "Eger_"
	elif wid in ["11_rpk", "12_flamya_1", "13_launcher_gm"]:
		return "Iney_"
	return "Unarmed_"

func _update_character_animation() -> void:
	if not anim_player:
		return
	var flat_speed = Vector2(velocity.x, velocity.z).length()
	var prefix = _get_body_anim_prefix()
	var action_suffix = ""
	
	if not is_on_floor():
		action_suffix = "Jump"
	elif flat_speed > 5.0 and not is_crouching:
		action_suffix = "Run-loop"
	elif flat_speed > 0.2:
		action_suffix = "Walk-loop"
	else:
		action_suffix = "Idle-loop"
		
	var target_anim = _resolve_anim_name(anim_player, prefix + action_suffix)
	if target_anim == "":
		target_anim = _resolve_anim_name(anim_player, "Unarmed_" + action_suffix)
		
	if target_anim != "" and anim_player.current_animation != target_anim:
		anim_player.play(target_anim, 0.2)

func _can_stand_up() -> bool:
	var space_state = get_world_3d().direct_space_state
	var from = global_position + Vector3(0, CROUCHING_HEIGHT * 0.5, 0)
	var to = global_position + Vector3(0, STANDING_HEIGHT + 0.1, 0)
	var query = PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [self.get_rid()]
	var result = space_state.intersect_ray(query)
	return result.is_empty()

func _handle_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Приседание
	var wants_crouch = Input.is_action_pressed("crouch") or Input.is_action_pressed("crouch_c")
	if wants_crouch:
		is_crouching = true
	else:
		if is_crouching and _can_stand_up():
			is_crouching = false

	var target_head_y = CROUCHING_HEAD_Y if is_crouching else STANDING_HEAD_Y
	head.position.y = move_toward(head.position.y, target_head_y, 7.0 * delta)
	
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var target_h = CROUCHING_HEIGHT if is_crouching else STANDING_HEIGHT
		collision_shape.shape.height = move_toward(collision_shape.shape.height, target_h, 7.0 * delta)
		collision_shape.position.y = collision_shape.shape.height * 0.5

	# Прыжок с расходом стамины
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		if GameState and GameState.consume_stamina(GameState.stamina_cost_jump):
			velocity.y = jump_velocity

	# Направление движения
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var wants_sprint = Input.is_action_pressed("sprint") and not is_crouching and is_on_floor() and input_dir.y < 0
	var is_sprinting = false
	if wants_sprint and GameState and GameState.can_sprint():
		if GameState.drain_stamina_continuous(GameState.stamina_drain_sprint, delta):
			is_sprinting = true
	
	var target_speed = walk_speed
	if is_crouching:
		target_speed = crouch_speed
	elif is_sprinting:
		target_speed = sprint_speed

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
					if NetworkManager and NetworkManager.is_multiplayer_active():
						rpc_play_attack.rpc("01_fists")

	# 3. Если в руках инструмент (Режим BRUSH / Щетка)
	elif current_tool == ToolMode.BRUSH:
		var patch = _find_dirt_patch(collider)
		var spot = _find_dirt_spot(collider)
		
		if patch:
			current_prompt = "[ЛКМ] Соскрести загрязнение"
			if Input.is_action_pressed("primary_action"):
				var hit_point = interaction_ray.get_collision_point()
				var clean_mod = GameState.cleaning_modifier if GameState else 1.0
				var brush_r = 0.38 * (1.5 if (GameState and GameState.current_class_id == "cleaner") else 1.0)
				patch.scrub_at_point(hit_point, delta * clean_mod, brush_r)
				_animate_tool_action()
				if NetworkManager and NetworkManager.is_multiplayer_active():
					rpc_scrub_patch.rpc(patch.get_path(), hit_point, delta * clean_mod, brush_r)
		elif spot:
			current_prompt = "[ЛКМ] Соскрести загрязнение"
			if Input.is_action_pressed("primary_action"):
				var clean_mod = GameState.cleaning_modifier if GameState else 1.0
				spot.scrub(delta * clean_mod)
				_animate_tool_action()
				if NetworkManager and NetworkManager.is_multiplayer_active():
					rpc_scrub_spot.rpc(spot.get_path(), delta * clean_mod)
		else:
			if collider != null:
				current_prompt = "Направьте на грязь, мох или копоть"

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
					if NetworkManager and NetworkManager.is_multiplayer_active():
						rpc_play_attack.rpc(w.id)
			else:
				if Input.is_action_just_pressed("primary_action"):
					weapon_manager.primary_attack()
					if NetworkManager and NetworkManager.is_multiplayer_active():
						rpc_play_attack.rpc(w.id)

func _find_dirt_patch(node: Node) -> DirtPatch:
	if not node:
		return null
	if node is DirtPatch:
		return node
	if node.get_parent() is DirtPatch:
		return node.get_parent() as DirtPatch
	return null

func _find_dirt_spot(node: Node) -> DirtSpot:
	if not node:
		return null
	if node is DirtSpot:
		return node
	if node.get_parent() is DirtSpot:
		return node.get_parent() as DirtSpot
	return null

func _pickup_trash(trash: CarryableTrash) -> void:
	held_trash = trash
	trash.pickup(hold_socket, self)
	if weapon_manager:
		weapon_manager.set_viewmodel_visible(false)
	if NetworkManager and NetworkManager.is_multiplayer_active():
		rpc_pickup_trash.rpc(trash.get_path())

func _drop_held_trash(impulse_dir: Vector3) -> void:
	if held_trash:
		var trash = held_trash
		held_trash = null
		trash.drop(impulse_dir)
		if current_tool == ToolMode.HANDS and weapon_manager:
			weapon_manager.set_tool_mode_hands(true)
		if NetworkManager and NetworkManager.is_multiplayer_active():
			rpc_drop_trash.rpc(trash.get_path(), impulse_dir)

func _set_tool(mode: ToolMode) -> void:
	if held_trash != null:
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
			if tool_model: tool_model.visible = false
			if weapon_manager:
				weapon_manager.set_tool_mode_weapon()
			var w_name = weapon_manager.current_weapon.display_name if (weapon_manager and weapon_manager.current_weapon) else "Оружие"
			mode_name = "Оружие: %s" % w_name
			
	EventBus.tool_changed.emit(current_tool, mode_name)

func _animate_tool_action() -> void:
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

# ==============================================================================
# СЕТЕВЫЕ RPC-МЕТОДЫ СИНХРОНИЗАЦИИ
# ==============================================================================

@rpc("unreliable")
func sync_transform(pos: Vector3, rot_y: float, head_pitch: float, vel: Vector3, crouch: bool) -> void:
	target_pos = pos
	target_rot_y = rot_y
	target_head_pitch = head_pitch
	target_velocity = vel
	target_crouch = crouch

@rpc("any_peer", "unreliable")
func rpc_scrub_patch(patch_path: NodePath, hit_point: Vector3, scrub_amt: float, brush_r: float) -> void:
	var patch = get_node_or_null(patch_path) as DirtPatch
	if patch:
		patch.scrub_at_point(hit_point, scrub_amt, brush_r, false)

@rpc("any_peer", "unreliable")
func rpc_scrub_spot(spot_path: NodePath, scrub_amt: float) -> void:
	var spot = get_node_or_null(spot_path) as DirtSpot
	if spot:
		spot.scrub(scrub_amt, false)

@rpc("any_peer", "call_local", "reliable")
func rpc_pickup_trash(trash_path: NodePath) -> void:
	if is_multiplayer_authority():
		return
	var trash = get_node_or_null(trash_path) as CarryableTrash
	if trash:
		held_trash = trash
		trash.pickup(hold_socket, self)

@rpc("any_peer", "call_local", "reliable")
func rpc_drop_trash(trash_path: NodePath, impulse_dir: Vector3) -> void:
	if is_multiplayer_authority():
		return
	var trash = get_node_or_null(trash_path) as CarryableTrash
	if trash:
		trash.drop(impulse_dir)
	held_trash = null

@rpc("any_peer", "reliable")
func rpc_play_attack(_weapon_id: String) -> void:
	if not is_multiplayer_authority() and anim_player:
		var prefix = _get_body_anim_prefix()
		var strike_name = _resolve_anim_name(anim_player, prefix + "Strike")
		if strike_name != "":
			anim_player.play(strike_name, 0.1)
