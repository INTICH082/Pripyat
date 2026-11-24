class_name HUD
extends Control

## Интерфейс ликвидатора в советском индустриальном стиле.
## Отображает кошелек (крб.), чистоту двора, шкалы здоровья, радиации, выносливости,
## текущий класс специалиста, прицел, подсказки и состав отряда (до 4 игроков).

@onready var rubles_label: Label = $TopLeft/VBox/HBoxRubles/RublesValue
@onready var cleanliness_bar: ProgressBar = $TopLeft/VBox/CleanlinessBar
@onready var cleanliness_label: Label = $TopLeft/VBox/CleanlinessBar/CleanlinessLabel

@onready var squad_container: VBoxContainer = get_node_or_null("TopLeft/VBox/SquadContainer")
@onready var squad_list: VBoxContainer = get_node_or_null("TopLeft/VBox/SquadContainer/SquadMembersList")

@onready var class_badge_label: Label = $TopRight/VBox/ClassBadgeLabel
@onready var health_bar: ProgressBar = $TopRight/VBox/HealthBar
@onready var health_label: Label = $TopRight/VBox/HealthBar/HealthLabel
@onready var stamina_bar: ProgressBar = $TopRight/VBox/StaminaBar
@onready var stamina_label: Label = $TopRight/VBox/StaminaBar/StaminaLabel
@onready var radiation_bar: ProgressBar = $TopRight/VBox/RadiationBar
@onready var radiation_label: Label = $TopRight/VBox/RadiationBar/RadiationLabel

@onready var tool_label: Label = $BottomLeft/VBox/ToolLabel
@onready var prompt_label: Label = $CenterContainer/PromptLabel
@onready var char_select_screen: CharacterSelectScreen = get_node_or_null("CharacterSelectScreen")
@onready var player: PlayerController = null

func _ready() -> void:
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.cleanliness_updated.connect(_on_cleanliness_updated)
	EventBus.tool_changed.connect(_on_tool_changed)
	EventBus.weapon_switched.connect(_on_weapon_switched)
	EventBus.weapon_ammo_changed.connect(_on_weapon_ammo_changed)
	
	EventBus.health_changed.connect(_on_health_changed)
	EventBus.stamina_changed.connect(_on_stamina_changed)
	EventBus.radiation_changed.connect(_on_radiation_changed)
	EventBus.character_class_changed.connect(_on_character_class_changed)
	
	if NetworkManager:
		NetworkManager.lobby_updated.connect(_on_squad_updated)
		
	# Начальные значения
	rubles_label.text = "%d крб." % GameState.karbovantsi
	cleanliness_bar.value = 0.0
	cleanliness_label.text = "Чистота двора: 0.0%"
	
	if GameState:
		_on_health_changed(GameState.health, GameState.max_health, 0.0)
		_on_stamina_changed(GameState.stamina, GameState.max_stamina, 0.0)
		_on_radiation_changed(GameState.radiation, GameState.max_radiation, 0.0)
		if GameState.CLASS_DEFINITIONS.has(GameState.current_class_id):
			_on_character_class_changed(GameState.current_class_id, GameState.CLASS_DEFINITIONS[GameState.current_class_id])
			
	_update_squad_display()

func _find_local_player() -> PlayerController:
	if NetworkManager:
		var p = NetworkManager.get_local_player_node()
		if p: return p
	for node in get_tree().get_nodes_in_group("player"):
		var pc = node as PlayerController
		if pc and pc.is_multiplayer_authority():
			return pc
	return null

func _process(_delta: float) -> void:
	if not player or not is_instance_valid(player):
		player = _find_local_player()
	
	if player:
		prompt_label.text = player.current_prompt

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("character_select"):
		if char_select_screen:
			if char_select_screen.visible:
				char_select_screen.close_screen()
			else:
				char_select_screen.open_screen()

func _on_currency_changed(new_amount: int, delta: int) -> void:
	rubles_label.text = "%d крб." % new_amount
	if delta > 0:
		_flash_rubles()
	if NetworkManager and NetworkManager.is_multiplayer_active():
		NetworkManager.sync_rubles_across_squad(new_amount, delta)

func _on_cleanliness_updated(cleaned: int, total: int, percent: float) -> void:
	cleanliness_bar.value = percent
	cleanliness_label.text = "Чистота двора: %.1f%%" % percent
	if NetworkManager and NetworkManager.is_multiplayer_active():
		NetworkManager.sync_cleanliness_across_squad(cleaned, total, percent)

func _on_health_changed(cur_hp: float, max_hp: float, _delta: float) -> void:
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = cur_hp
	if health_label:
		health_label.text = "ЗДОРОВЬЕ: %d / %d" % [int(cur_hp), int(max_hp)]

func _on_stamina_changed(cur_sta: float, max_sta: float, _delta: float) -> void:
	if stamina_bar:
		stamina_bar.max_value = max_sta
		stamina_bar.value = cur_sta
	if stamina_label:
		stamina_label.text = "ВЫНОСЛИВОСТЬ: %d / %d" % [int(cur_sta), int(max_sta)]

func _on_radiation_changed(cur_rad: float, max_rad: float, _delta: float) -> void:
	if radiation_bar:
		radiation_bar.max_value = max_rad
		radiation_bar.value = cur_rad
	if radiation_label:
		radiation_label.text = "РАДИАЦИЯ: %.1f мЗв" % cur_rad

func _on_character_class_changed(_class_id: String, class_data: Dictionary) -> void:
	if class_badge_label:
		class_badge_label.text = "СПЕЦИАЛИСТ: [ %s ]" % class_data.get("name", "Чистильщик").to_upper()
	_update_squad_display()

func _on_tool_changed(_mode: int, tool_name: String) -> void:
	tool_label.text = "Инструмент: [ %s ]" % tool_name

func _on_weapon_switched(weapon: WeaponData, cur_ammo: int, res_ammo: int) -> void:
	if weapon.is_melee:
		tool_label.text = "Оружие: [ %s (Ближний бой) ]" % weapon.display_name
	elif weapon.is_flamethrower:
		tool_label.text = "Оружие: [ %s ]  |  Топливо: %d л / %d" % [weapon.display_name, cur_ammo, res_ammo]
	else:
		tool_label.text = "Оружие: [ %s ]  |  Патроны: %d / %d" % [weapon.display_name, cur_ammo, res_ammo]

func _on_weapon_ammo_changed(cur_ammo: int, res_ammo: int) -> void:
	if player and player.weapon_manager and player.weapon_manager.current_weapon:
		var w = player.weapon_manager.current_weapon
		_on_weapon_switched(w, cur_ammo, res_ammo)

func _flash_rubles() -> void:
	var tween = create_tween()
	rubles_label.modulate = Color(1.0, 0.9, 0.2)
	tween.tween_property(rubles_label, "modulate", Color.WHITE, 0.3)

# ==============================================================================
# ОТОБРАЖЕНИЕ СОСТАВА ОТРЯДА (ДО 4 БОЙЦОВ)
# ==============================================================================

func _on_squad_updated(_players: Dictionary) -> void:
	_update_squad_display()

func _update_squad_display() -> void:
	if not squad_container or not squad_list:
		return
		
	for child in squad_list.get_children():
		child.queue_free()
		
	if not NetworkManager or not NetworkManager.is_multiplayer_active() or NetworkManager.players.size() <= 1:
		squad_container.visible = false
		return
		
	squad_container.visible = true
	var my_id = multiplayer.get_unique_id() if NetworkManager.is_multiplayer_active() else 1
	
	for pid in NetworkManager.players:
		var p_data = NetworkManager.players[pid]
		var p_name = p_data.get("name", "Боец")
		var c_id = p_data.get("class_id", "cleaner")
		var is_me = (pid == my_id)
		
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		
		var bullet = Label.new()
		bullet.text = "●"
		bullet.modulate = _get_squad_class_color(c_id)
		bullet.add_theme_font_size_override("font_size", 12)
		row.add_child(bullet)
		
		var lbl = Label.new()
		var you_tag = " (Вы)" if is_me else ""
		lbl.text = "%s [%s]%s" % [p_name, _get_short_class_name(c_id), you_tag]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.modulate = Color(0.9, 0.95, 0.9) if is_me else Color(0.75, 0.8, 0.75)
		row.add_child(lbl)
		
		squad_list.add_child(row)

func _get_short_class_name(c_id: String) -> String:
	match c_id:
		"cleaner": return "Чистильщик"
		"soldier": return "Штурмовик"
		"medic": return "Медик"
		"engineer": return "Инженер"
	return "Боец"

func _get_squad_class_color(c_id: String) -> Color:
	match c_id:
		"cleaner": return Color(0.4, 0.9, 0.6)
		"soldier": return Color(0.95, 0.45, 0.35)
		"medic": return Color(0.35, 0.85, 1.0)
		"engineer": return Color(1.0, 0.8, 0.25)
	return Color.WHITE
