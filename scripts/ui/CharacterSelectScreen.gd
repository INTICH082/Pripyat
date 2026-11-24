class_name CharacterSelectScreen
extends Control

## Экран выбора специалиста ликвидации при старте игры.
## Отображает 4 интерактивных экранчика с вращающимися 3D-моделями всех 4 классов:
## Чистильщик, Штурмовик, Медик, Инженер.

signal character_selected(class_id: String)

@onready var cleaner_model_pivot: Node3D = get_node_or_null("MarginContainer/VBox/CardsContainer/Card_Cleaner/VBox/ViewportContainer/SubViewport/ModelPivot")
@onready var soldier_model_pivot: Node3D = get_node_or_null("MarginContainer/VBox/CardsContainer/Card_Soldier/VBox/ViewportContainer/SubViewport/ModelPivot")
@onready var medic_model_pivot: Node3D = get_node_or_null("MarginContainer/VBox/CardsContainer/Card_Medic/VBox/ViewportContainer/SubViewport/ModelPivot")
@onready var engineer_model_pivot: Node3D = get_node_or_null("MarginContainer/VBox/CardsContainer/Card_Engineer/VBox/ViewportContainer/SubViewport/ModelPivot")

var model_pivots: Array[Node3D] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Если экран открыт внутри игрового HUD, скрываем его по умолчанию
	if get_parent() != null and (get_parent() is CanvasLayer or get_parent().name == "HUD" or get_parent().name.ends_with("HUD")):
		visible = false
	else:
		visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if cleaner_model_pivot: model_pivots.append(cleaner_model_pivot)
	if soldier_model_pivot: model_pivots.append(soldier_model_pivot)
	if medic_model_pivot: model_pivots.append(medic_model_pivot)
	if engineer_model_pivot: model_pivots.append(engineer_model_pivot)
	
	_play_animations_on_pivots()

func _play_animations_on_pivots() -> void:
	for pivot in model_pivots:
		var anim = _find_animation_player(pivot)
		if anim:
			for a in anim.get_animation_list():
				if a.ends_with("Idle-loop") or a == "Idle-loop" or a.ends_with("Unarmed_Idle-loop"):
					anim.play(a)
					break

func _find_animation_player(node: Node) -> AnimationPlayer:
	if not node: return null
	if node is AnimationPlayer: return node
	for c in node.get_children():
		var found = _find_animation_player(c)
		if found: return found
	return null

func _process(delta: float) -> void:
	if not visible:
		return
	# Плавное вращение 3D-моделек на экранчиках
	for pivot in model_pivots:
		if pivot:
			pivot.rotation.y += delta * 0.75

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("character_select") and not visible:
		open_screen()
	elif event.is_action_pressed("ui_cancel") and visible:
		# Если уже в игре, можно закрыть по Esc
		close_screen()

func open_screen() -> void:
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close_screen() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func select_character(class_id: String) -> void:
	if GameState:
		GameState.set_class(class_id)
	character_selected.emit(class_id)
	close_screen()

func _on_select_cleaner_pressed() -> void:
	select_character("cleaner")

func _on_select_soldier_pressed() -> void:
	select_character("soldier")

func _on_select_medic_pressed() -> void:
	select_character("medic")

func _on_select_engineer_pressed() -> void:
	select_character("engineer")
