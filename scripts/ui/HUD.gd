class_name HUD
extends Control

## Интерфейс ликвидатора в советском индустриальном стиле.
## Отображает кошелек (крб.), чистоту двора, шкалы здоровья, радиации, выносливости,
## текущий класс специалиста, прицел и подсказки.

@onready var rubles_label: Label = $TopLeft/VBox/HBoxRubles/RublesValue
@onready var cleanliness_bar: ProgressBar = $TopLeft/VBox/CleanlinessBar
@onready var cleanliness_label: Label = $TopLeft/VBox/CleanlinessBar/CleanlinessLabel

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

func _process(_delta: float) -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")
	
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

func _on_cleanliness_updated(_cleaned: int, _total: int, percent: float) -> void:
	cleanliness_bar.value = percent
	cleanliness_label.text = "Чистота двора: %.1f%%" % percent

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
