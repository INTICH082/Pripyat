extends Node

## Состояние игры (GameState)
## Управляет кошельком (Советские рубли) и общим прогрессом чистоты локации.

var rubles: int = 0:
	set(value):
		var delta = value - rubles
		rubles = max(0, value)
		EventBus.currency_changed.emit(rubles, delta)

var total_items: int = 0
var cleaned_items: int = 0

func _ready() -> void:
	EventBus.trash_deposited.connect(_on_trash_deposited)
	EventBus.dirt_cleaned.connect(_on_dirt_cleaned)

func register_cleanup_item() -> void:
	total_items += 1
	_emit_progress()

func add_rubles(amount: int) -> void:
	rubles += amount

func _on_trash_deposited(_trash_name: String, reward_rubles: int) -> void:
	add_rubles(reward_rubles)
	cleaned_items += 1
	_emit_progress()

func _on_dirt_cleaned(reward_rubles: int, _world_pos: Vector3) -> void:
	if reward_rubles > 0:
		add_rubles(reward_rubles)
	cleaned_items += 1
	_emit_progress()

func _emit_progress() -> void:
	var percent: float = 0.0
	if total_items > 0:
		percent = clampf((float(cleaned_items) / float(total_items)) * 100.0, 0.0, 100.0)
	EventBus.cleanliness_updated.emit(cleaned_items, total_items, percent)
