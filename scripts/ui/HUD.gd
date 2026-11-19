class_name HUD
extends Control

## Интерфейс игрока в советском индустриальном стиле.
## Отображает кошелек (руб.), шкалу чистоты территории, прицел и подсказки.

@onready var rubles_label: Label = $TopLeft/VBox/HBoxRubles/RublesValue
@onready var cleanliness_bar: ProgressBar = $TopLeft/VBox/CleanlinessBar
@onready var cleanliness_label: Label = $TopLeft/VBox/CleanlinessBar/CleanlinessLabel
@onready var tool_label: Label = $BottomLeft/VBox/ToolLabel
@onready var prompt_label: Label = $CenterContainer/PromptLabel
@onready var player: PlayerController = null

func _ready() -> void:
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.cleanliness_updated.connect(_on_cleanliness_updated)
	EventBus.tool_changed.connect(_on_tool_changed)
	
	# Инициализация начальных значений
	rubles_label.text = "%d крб." % GameState.karbovantsi
	cleanliness_bar.value = 0.0
	cleanliness_label.text = "Чистота двора: 0.0%"

func _process(_delta: float) -> void:
	# Получаем текст подсказки напрямую от игрока
	if not player:
		player = get_tree().get_first_node_in_group("player")
	
	if player:
		prompt_label.text = player.current_prompt

func _on_currency_changed(new_amount: int, delta: int) -> void:
	rubles_label.text = "%d крб." % new_amount
	if delta > 0:
		_flash_rubles()

func _on_cleanliness_updated(_cleaned: int, _total: int, percent: float) -> void:
	cleanliness_bar.value = percent
	cleanliness_label.text = "Чистота двора: %.1f%%" % percent

func _on_tool_changed(_mode: int, tool_name: String) -> void:
	tool_label.text = "Инструмент: [ %s ]" % tool_name

func _flash_rubles() -> void:
	var tween = create_tween()
	rubles_label.modulate = Color(1.0, 0.9, 0.2)
	tween.tween_property(rubles_label, "modulate", Color.WHITE, 0.3)
