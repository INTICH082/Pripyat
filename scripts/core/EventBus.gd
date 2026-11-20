extends Node

## Глобальная шина событий (EventBus)
## Обеспечивает слабую связанность между системами (игрок, мусор, UI, статистика).

# События взаимодействия с мусором
signal trash_picked_up(trash_node: Node)
signal trash_dropped(trash_node: Node)
signal trash_deposited(trash_name: String, reward_rubles: int)

# События очистки поверхностей (грязь, трава, пыль)
signal dirt_cleaned(reward_rubles: int, world_pos: Vector3)

# Экономика и прогресс
signal currency_changed(new_amount: int, delta: int)
signal cleanliness_updated(cleaned_count: int, total_count: int, percent: float)

# Инструменты и Оружие
signal tool_changed(tool_mode: int, tool_name: String)
signal weapon_switched(weapon: WeaponData, current_ammo: int, reserve_ammo: int)
signal weapon_fired(weapon: WeaponData, current_ammo: int)
signal weapon_reloaded(weapon: WeaponData, current_ammo: int)
signal weapon_ammo_changed(current_ammo: int, reserve_ammo: int)
signal enemy_hit(target: Node, damage: float, hit_position: Vector3)

func _enter_tree() -> void:
	_setup_default_inputs()

func _setup_default_inputs() -> void:
	_ensure_key_action("move_forward", KEY_W)
	_ensure_key_action("move_backward", KEY_S)
	_ensure_key_action("move_left", KEY_A)
	_ensure_key_action("move_right", KEY_D)
	_ensure_key_action("jump", KEY_SPACE)
	_ensure_key_action("sprint", KEY_SHIFT)
	_ensure_key_action("interact", KEY_E)
	_ensure_key_action("drop", KEY_G)
	_ensure_mouse_action("primary_action", MOUSE_BUTTON_LEFT)
	_ensure_key_action("tool_hands", KEY_1)
	_ensure_key_action("tool_brush", KEY_2)
	_ensure_key_action("weapon_mode", KEY_3)
	_ensure_key_action("reload", KEY_R)
	_ensure_key_action("weapon_next", KEY_BRACKETRIGHT)
	_ensure_key_action("weapon_prev", KEY_BRACKETLEFT)

func _ensure_key_action(action_name: String, key_code: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var ev = InputEventKey.new()
		ev.physical_keycode = key_code
		InputMap.action_add_event(action_name, ev)

func _ensure_mouse_action(action_name: String, mouse_button: MouseButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var ev = InputEventMouseButton.new()
		ev.button_index = mouse_button
		InputMap.action_add_event(action_name, ev)
