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

# Характеристики выживания и класс персонажа
signal health_changed(current_hp: float, max_hp: float, delta: float)
signal radiation_changed(current_rad: float, max_rad: float, delta: float)
signal stamina_changed(current_sta: float, max_sta: float, delta: float)
signal character_class_changed(class_id: String, class_data: Dictionary)
signal player_damaged(amount: float)
signal control_settings_changed()

# Локации, Контрольные точки и Противники
signal location_changed(location_id: String, location_data: Dictionary)
signal enemy_defeated(enemy_id: String, reward_karbovantsi: int)
signal checkpoint_registered(checkpoint_id: String, index: int, total: int)
signal checkpoint_unlocked(checkpoint_id: String, checkpoint_name: String)
signal checkpoint_activated(checkpoint_id: String, tasks: Array)
signal checkpoint_task_updated(checkpoint_id: String, task_id: String, progress: float, completed: bool)
signal checkpoint_completed(checkpoint_id: String, reward_karbovantsi: int)
signal map_completed(location_id: String, next_location_id: String)
signal hub_transition_requested(next_location_id: String)

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
	_ensure_key_action("crouch", KEY_CTRL)
	_ensure_key_action("crouch_c", KEY_C)
	_ensure_key_action("interact", KEY_E)
	_ensure_key_action("drop", KEY_G)
	_ensure_mouse_action("primary_action", MOUSE_BUTTON_LEFT)
	_ensure_mouse_action("secondary_action", MOUSE_BUTTON_RIGHT)
	_ensure_key_action("tool_hands", KEY_1)
	_ensure_key_action("tool_brush", KEY_2)
	_ensure_key_action("weapon_mode", KEY_3)
	_ensure_key_action("reload", KEY_R)
	_ensure_key_action("weapon_next", KEY_BRACKETRIGHT)
	_ensure_key_action("weapon_prev", KEY_BRACKETLEFT)
	_ensure_key_action("character_select", KEY_TAB)
	_ensure_key_action("quick_heal", KEY_H)
	_ensure_key_action("flashlight", KEY_F)

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

## Программное переназначение клавиши действия
func rebind_action_key(action_name: String, new_key: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	# Очищаем только события клавиатуры для данного действия
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey:
			InputMap.action_erase_event(action_name, ev)
	var new_ev = InputEventKey.new()
	new_ev.physical_keycode = new_key
	InputMap.action_add_event(action_name, new_ev)
	control_settings_changed.emit()

## Получение человекочитаемого названия клавиши для действия
func get_action_key_text(action_name: String) -> String:
	if not InputMap.has_action(action_name):
		return ""
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode)
		elif ev is InputEventMouseButton:
			match ev.button_index:
				MOUSE_BUTTON_LEFT: return "ЛКМ"
				MOUSE_BUTTON_RIGHT: return "ПКМ"
				MOUSE_BUTTON_MIDDLE: return "СКМ"
				MOUSE_BUTTON_WHEEL_UP: return "Колесо Вверх"
				MOUSE_BUTTON_WHEEL_DOWN: return "Колесо Вниз"
	return ""
