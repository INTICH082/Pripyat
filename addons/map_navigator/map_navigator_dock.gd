@tool
class_name MapNavigatorDock
extends VBoxContainer

## Главная панель инструмента «Map Navigator & Editor».
## Объединяет навигацию по карте, поиск/фильтрацию объектов, закладки камеры,
## приземление на поверхность, рандомизацию и расстановку префабов по клику.

signal place_mode_changed(enabled: bool)

const BOOKMARKS_PATH := "res://.godot/map_navigator_bookmarks.cfg"
const PRESET_SCENES := {
	"Мусор": "res://scenes/interactables/TrashItem.tscn",
	"Грязь": "res://scenes/interactables/DirtPatch.tscn",
	"Урна": "res://scenes/interactables/TrashBin.tscn",
}

var undo_redo: EditorUndoRedoManager
var place_mode_enabled: bool = false
var selected_prefab_path: String = "res://scenes/interactables/TrashItem.tscn"

# UI ссылки
var _scene_label: Label
var _tabs: TabContainer

# Вкладка Навигация
var _speed_slider: HSlider
var _speed_value_label: Label
var _proj_button: Button
var _bookmark_name_edit: LineEdit
var _bookmark_list: ItemList
var _bookmarks: Array[Dictionary] = []

# Вкладка Объекты
var _search_edit: LineEdit
var _filter_option: OptionButton
var _object_tree: Tree
var _tree_node_map: Dictionary = {} # TreeItem -> Node

# Вкладка Редактор
var _scale_min_spin: SpinBox
var _scale_max_spin: SpinBox
var _place_mode_btn: CheckButton
var _prefab_label: Label
var _place_rand_rot_cb: CheckBox
var _place_rand_scale_cb: CheckBox
var _place_align_normal_cb: CheckBox
var _file_dialog: EditorFileDialog

# Быстрая трансформация
var _transform_box: VBoxContainer
var _pos_x_spin: SpinBox
var _pos_y_spin: SpinBox
var _pos_z_spin: SpinBox
var _rot_y_spin: SpinBox
var _updating_transform_ui: bool = false


func _ready() -> void:
	name = "Карта"
	custom_minimum_size = Vector2(280, 400)
	_build_ui()

	if Engine.is_editor_hint():
		var sel := EditorInterface.get_selection()
		if sel and not sel.selection_changed.is_connected(_on_editor_selection_changed):
			sel.selection_changed.connect(_on_editor_selection_changed)
		_sync_camera_speed_from_settings()
		refresh_for_current_scene()


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		var sel := EditorInterface.get_selection()
		if sel and sel.selection_changed.is_connected(_on_editor_selection_changed):
			sel.selection_changed.disconnect(_on_editor_selection_changed)


func refresh_for_current_scene() -> void:
	if not Engine.is_editor_hint():
		return
	var root := EditorInterface.get_edited_scene_root()
	if _scene_label:
		if root:
			_scene_label.text = "Сцена: %s" % root.name
		else:
			_scene_label.text = "Сцена не открыта"
	_load_bookmarks()
	_refresh_object_list()
	_update_quick_transform_ui()


# ==============================================================================
# ПОСТРОЕНИЕ ИНТЕРФЕЙСА
# ==============================================================================

func _build_ui() -> void:
	# Заголовок
	var header := HBoxContainer.new()
	add_child(header)

	_scene_label = Label.new()
	_scene_label.text = "Сцена: —"
	_scene_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_scene_label)

	var refresh_btn := Button.new()
	refresh_btn.text = "Обновить"
	refresh_btn.tooltip_text = "Обновить список объектов и закладки"
	refresh_btn.pressed.connect(refresh_for_current_scene)
	header.add_child(refresh_btn)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)

	_build_navigation_tab()
	_build_objects_tab()
	_build_editor_tab()

	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.title = "Выберите сцену (.tscn) для расстановки"
	_file_dialog.add_filter("*.tscn, *.scn ; Сцены Godot")
	_file_dialog.file_selected.connect(_on_prefab_file_selected)
	add_child(_file_dialog)


func _build_navigation_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Навигация"
	_tabs.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Скорость камеры
	var speed_title := Label.new()
	speed_title.text = "Скорость камеры (WASD / ПКМ)"
	vbox.add_child(speed_title)

	var speed_row := HBoxContainer.new()
	vbox.add_child(speed_row)

	_speed_slider = HSlider.new()
	_speed_slider.min_value = 2.0
	_speed_slider.max_value = 100.0
	_speed_slider.step = 1.0
	_speed_slider.value = 16.0
	_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_slider.value_changed.connect(_on_camera_speed_changed)
	speed_row.add_child(_speed_slider)

	_speed_value_label = Label.new()
	_speed_value_label.text = "16 м/с"
	_speed_value_label.custom_minimum_size = Vector2(56, 0)
	speed_row.add_child(_speed_value_label)

	vbox.add_child(HSeparator.new())

	# Быстрые виды
	var view_title := Label.new()
	view_title.text = "Быстрые виды и перелёты"
	vbox.add_child(view_title)

	var view_grid := GridContainer.new()
	view_grid.columns = 2
	vbox.add_child(view_grid)

	_add_btn(view_grid, "Сверху (Top)", _on_view_top_pressed)
	_add_btn(view_grid, "Изометрия", _on_view_iso_pressed)
	_add_btn(view_grid, "К выделенному", _on_focus_selected_pressed)
	_add_btn(view_grid, "К точке спавна", _on_focus_spawn_pressed)

	_proj_button = Button.new()
	_proj_button.text = "Переключить: Перспектива / Орто"
	_proj_button.pressed.connect(_on_toggle_projection_pressed)
	vbox.add_child(_proj_button)

	vbox.add_child(HSeparator.new())

	# Закладки камеры
	var bm_title := Label.new()
	bm_title.text = "Закладки камеры (точки на карте)"
	vbox.add_child(bm_title)

	var bm_add_row := HBoxContainer.new()
	vbox.add_child(bm_add_row)

	_bookmark_name_edit = LineEdit.new()
	_bookmark_name_edit.placeholder_text = "Название точки..."
	_bookmark_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bm_add_row.add_child(_bookmark_name_edit)

	_add_btn(bm_add_row, "+ Сохранить", _on_add_bookmark_pressed)

	_bookmark_list = ItemList.new()
	_bookmark_list.custom_minimum_size = Vector2(0, 160)
	_bookmark_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bookmark_list.item_activated.connect(_on_bookmark_activated)
	_bookmark_list.item_selected.connect(_on_bookmark_activated)
	vbox.add_child(_bookmark_list)

	var bm_btn_row := HBoxContainer.new()
	vbox.add_child(bm_btn_row)
	_add_btn(bm_btn_row, "Перелететь", _on_goto_selected_bookmark_pressed)
	_add_btn(bm_btn_row, "Удалить закладку", _on_delete_bookmark_pressed)


func _build_objects_tab() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "Объекты"
	_tabs.add_child(vbox)

	var search_row := HBoxContainer.new()
	vbox.add_child(search_row)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Поиск по имени..."
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(func(_t: String): _refresh_object_list())
	search_row.add_child(_search_edit)

	_filter_option = OptionButton.new()
	_filter_option.add_item("Все объекты", 0)
	_filter_option.add_item("Мусор (Trash)", 1)
	_filter_option.add_item("Грязь (Dirt)", 2)
	_filter_option.add_item("Урны / Баки", 3)
	_filter_option.add_item("Меши / Здания", 4)
	_filter_option.add_item("Свет / Камеры", 5)
	_filter_option.item_selected.connect(func(_idx: int): _refresh_object_list())
	vbox.add_child(_filter_option)

	_object_tree = Tree.new()
	_object_tree.columns = 2
	_object_tree.set_column_title(0, "Объект")
	_object_tree.set_column_title(1, "Позиция")
	_object_tree.column_titles_visible = true
	_object_tree.hide_root = true
	_object_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_object_tree.item_selected.connect(_on_tree_item_selected)
	_object_tree.item_activated.connect(_on_tree_item_activated)
	vbox.add_child(_object_tree)

	var btn_row := HBoxContainer.new()
	vbox.add_child(btn_row)
	_add_btn(btn_row, "Перелететь к выбранному", _on_focus_selected_pressed)
	_add_btn(btn_row, "Обновить", _refresh_object_list)


func _build_editor_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Редактор"
	_tabs.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Блок 1: Действия с выделением
	var sel_title := Label.new()
	sel_title.text = "Инструменты выделения (Ctrl+Z)"
	vbox.add_child(sel_title)

	var action_grid := GridContainer.new()
	action_grid.columns = 2
	vbox.add_child(action_grid)

	_add_btn(action_grid, "Опустить на землю", _on_drop_to_ground_pressed)
	_add_btn(action_grid, "Выровнять ровно", _on_align_upright_pressed)
	_add_btn(action_grid, "Случ. поворот Y", _on_random_rot_y_pressed)
	_add_btn(action_grid, "Случ. масштаб", _on_random_scale_pressed)
	_add_btn(action_grid, "Дублировать", _on_duplicate_selected_pressed)
	_add_btn(action_grid, "Удалить", _on_delete_selected_pressed)

	# Диапазон случайного масштаба
	var scale_row := HBoxContainer.new()
	vbox.add_child(scale_row)
	var scale_lbl := Label.new()
	scale_lbl.text = "Масштаб:"
	scale_row.add_child(scale_lbl)

	_scale_min_spin = SpinBox.new()
	_scale_min_spin.min_value = 0.1
	_scale_min_spin.max_value = 5.0
	_scale_min_spin.step = 0.05
	_scale_min_spin.value = 0.85
	_scale_min_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(_scale_min_spin)

	_scale_max_spin = SpinBox.new()
	_scale_max_spin.min_value = 0.1
	_scale_max_spin.max_value = 5.0
	_scale_max_spin.step = 0.05
	_scale_max_spin.value = 1.15
	_scale_max_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(_scale_max_spin)

	# Кнопки точного поворота
	var rot_row := HBoxContainer.new()
	vbox.add_child(rot_row)
	_add_btn(rot_row, "-90°", func(): _rotate_selected_y(-90.0))
	_add_btn(rot_row, "-15°", func(): _rotate_selected_y(-15.0))
	_add_btn(rot_row, "+15°", func(): _rotate_selected_y(15.0))
	_add_btn(rot_row, "+90°", func(): _rotate_selected_y(90.0))

	vbox.add_child(HSeparator.new())

	# Блок 2: Расстановка по клику (Place Mode)
	var place_title := Label.new()
	place_title.text = "Расстановка по клику (ЛКМ)"
	vbox.add_child(place_title)

	_place_mode_btn = CheckButton.new()
	_place_mode_btn.text = "Вкл. режим кисти (ЛКМ по карте)"
	_place_mode_btn.toggled.connect(_on_place_mode_toggled)
	vbox.add_child(_place_mode_btn)

	var preset_row := HBoxContainer.new()
	vbox.add_child(preset_row)
	for preset_name in PRESET_SCENES.keys():
		var path: String = PRESET_SCENES[preset_name]
		_add_btn(preset_row, preset_name, func(): _set_selected_prefab(path))
	_add_btn(preset_row, "Файл...", func(): _file_dialog.popup_centered_ratio(0.6))

	_prefab_label = Label.new()
	_prefab_label.text = "Префаб: TrashItem.tscn"
	_prefab_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(_prefab_label)

	_place_rand_rot_cb = CheckBox.new()
	_place_rand_rot_cb.text = "Случайный поворот Y при клике"
	_place_rand_rot_cb.button_pressed = true
	vbox.add_child(_place_rand_rot_cb)

	_place_rand_scale_cb = CheckBox.new()
	_place_rand_scale_cb.text = "Случайный масштаб при клике"
	_place_rand_scale_cb.button_pressed = false
	vbox.add_child(_place_rand_scale_cb)

	_place_align_normal_cb = CheckBox.new()
	_place_align_normal_cb.text = "Прижимать к наклону / стене"
	_place_align_normal_cb.button_pressed = false
	vbox.add_child(_place_align_normal_cb)

	vbox.add_child(HSeparator.new())

	# Блок 3: Быстрая правка координат
	_transform_box = VBoxContainer.new()
	vbox.add_child(_transform_box)

	var tf_title := Label.new()
	tf_title.text = "Быстрая правка координат"
	_transform_box.add_child(tf_title)

	var tf_grid := GridContainer.new()
	tf_grid.columns = 2
	_transform_box.add_child(tf_grid)

	_pos_x_spin = _add_transform_spin(tf_grid, "Pos X:", -5000.0, 5000.0, 0.1)
	_pos_y_spin = _add_transform_spin(tf_grid, "Pos Y:", -500.0, 500.0, 0.1)
	_pos_z_spin = _add_transform_spin(tf_grid, "Pos Z:", -5000.0, 5000.0, 0.1)
	_rot_y_spin = _add_transform_spin(tf_grid, "Rot Y°:", -360.0, 360.0, 1.0)


func _add_btn(parent: Control, text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn


func _add_transform_spin(parent: GridContainer, label_text: String, min_v: float, max_v: float, step_v: float) -> SpinBox:
	var lbl := Label.new()
	lbl.text = label_text
	parent.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step_v
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(_on_quick_transform_changed)
	parent.add_child(spin)
	return spin


# ==============================================================================
# НАВИГАЦИЯ И КАМЕРА
# ==============================================================================

func _get_editor_camera() -> Camera3D:
	if not Engine.is_editor_hint():
		return null
	var vp := EditorInterface.get_editor_viewport_3d(0)
	return vp.get_camera_3d() if vp else null


func _sync_camera_speed_from_settings() -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings and settings.has_setting("editors/3d/freelook/freelook_base_speed"):
		var spd: float = settings.get_setting("editors/3d/freelook/freelook_base_speed")
		_speed_slider.set_value_no_signal(clampf(spd, _speed_slider.min_value, _speed_slider.max_value))
		_speed_value_label.text = "%d м/с" % int(spd)


func _on_camera_speed_changed(val: float) -> void:
	_speed_value_label.text = "%d м/с" % int(val)
	if Engine.is_editor_hint():
		var settings := EditorInterface.get_editor_settings()
		if settings:
			settings.set_setting("editors/3d/freelook/freelook_base_speed", val)


func _get_focus_target_position() -> Vector3:
	var selected := _get_selected_node3ds()
	if not selected.is_empty():
		return MapNavigatorRaycastHelper.get_node_world_bounds(selected[0]).get_center()
	var root := EditorInterface.get_edited_scene_root()
	if root is Node3D:
		return (root as Node3D).global_position
	return Vector3.ZERO


func _on_view_top_pressed() -> void:
	var cam := _get_editor_camera()
	if not cam:
		return
	var target := _get_focus_target_position()
	cam.global_position = target + Vector3(0.0, 55.0, 0.01)
	cam.look_at(target, Vector3.FORWARD)


func _on_view_iso_pressed() -> void:
	var cam := _get_editor_camera()
	if not cam:
		return
	var target := _get_focus_target_position()
	cam.global_position = target + Vector3(24.0, 26.0, 24.0)
	cam.look_at(target, Vector3.UP)


func _on_focus_selected_pressed() -> void:
	var selected := _get_selected_node3ds()
	if selected.is_empty():
		return
	_focus_camera_on_node(selected[0])


func _focus_camera_on_node(node: Node3D) -> void:
	var cam := _get_editor_camera()
	if not cam or not is_instance_valid(node):
		return
	var bounds := MapNavigatorRaycastHelper.get_node_world_bounds(node)
	var center := bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.5, 2.5)
	var dir := (cam.global_position - center).normalized()
	if dir.length_squared() < 0.01:
		dir = Vector3(0.6, 0.6, 0.6).normalized()
	cam.global_position = center + dir * clampf(radius * 2.2, 4.0, 60.0)
	cam.look_at(center, Vector3.UP)


func _on_focus_spawn_pressed() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return
	var spawn_pos := Vector3.ZERO
	var found := false
	if "default_spawn_position" in root:
		spawn_pos = root.get("default_spawn_position")
		found = true
	else:
		var player_node := root.find_child("Player*", true, false)
		if player_node is Node3D:
			spawn_pos = (player_node as Node3D).global_position
			found = true

	if found:
		var cam := _get_editor_camera()
		if cam:
			cam.global_position = spawn_pos + Vector3(6.0, 7.0, 8.0)
			cam.look_at(spawn_pos, Vector3.UP)


func _on_toggle_projection_pressed() -> void:
	var cam := _get_editor_camera()
	if not cam:
		return
	if cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 35.0
		_proj_button.text = "Режим: Ортография (переключить)"
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_proj_button.text = "Режим: Перспектива (переключить)"


# ==============================================================================
# ЗАКЛАДКИ КАМЕРЫ
# ==============================================================================

func _get_scene_bookmark_key() -> String:
	var root := EditorInterface.get_edited_scene_root()
	if root and not root.scene_file_path.is_empty():
		return root.scene_file_path
	return "default"


func _load_bookmarks() -> void:
	_bookmarks.clear()
	_bookmark_list.clear()
	var cfg := ConfigFile.new()
	if cfg.load(BOOKMARKS_PATH) != OK:
		return
	var section := _get_scene_bookmark_key()
	if not cfg.has_section(section):
		return
	var saved: Variant = cfg.get_value(section, "items", [])
	if saved is Array:
		for item in saved:
			if item is Dictionary:
				_bookmarks.append(item)
				_bookmark_list.add_item(item.get("name", "Точка"))


func _save_bookmarks() -> void:
	var cfg := ConfigFile.new()
	cfg.load(BOOKMARKS_PATH)
	cfg.set_value(_get_scene_bookmark_key(), "items", _bookmarks)
	cfg.save(BOOKMARKS_PATH)


func _on_add_bookmark_pressed() -> void:
	var cam := _get_editor_camera()
	if not cam:
		return
	var bm_name := _bookmark_name_edit.text.strip_edges()
	if bm_name.is_empty():
		bm_name = "Точка %d" % (_bookmarks.size() + 1)
	_bookmarks.append({
		"name": bm_name,
		"transform": cam.global_transform
	})
	_bookmark_list.add_item(bm_name)
	_bookmark_name_edit.clear()
	_save_bookmarks()


func _on_bookmark_activated(index: int) -> void:
	if index < 0 or index >= _bookmarks.size():
		return
	var cam := _get_editor_camera()
	if cam and _bookmarks[index].has("transform"):
		cam.global_transform = _bookmarks[index]["transform"]


func _on_goto_selected_bookmark_pressed() -> void:
	var sel := _bookmark_list.get_selected_items()
	if not sel.is_empty():
		_on_bookmark_activated(sel[0])


func _on_delete_bookmark_pressed() -> void:
	var sel := _bookmark_list.get_selected_items()
	if sel.is_empty():
		return
	var idx: int = sel[0]
	_bookmarks.remove_at(idx)
	_bookmark_list.remove_item(idx)
	_save_bookmarks()


# ==============================================================================
# БРАУЗЕР ОБЪЕКТОВ КАРТЫ
# ==============================================================================

func _refresh_object_list() -> void:
	if not _object_tree:
		return
	_object_tree.clear()
	_tree_node_map.clear()

	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return

	var tree_root := _object_tree.create_item()
	var search_q := _search_edit.text.strip_edges().to_lower()
	var filter_id := _filter_option.get_selected_id()

	var stack: Array[Node] = [root]
	var nodes_to_show: Array[Node3D] = []
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur != root and cur is Node3D:
			var n3d := cur as Node3D
			if _matches_filter(n3d, search_q, filter_id):
				nodes_to_show.append(n3d)
		# Не проваливаемся внутрь инстансированных под-сцен, кроме корневых контейнеров
		if cur == root or cur.scene_file_path.is_empty():
			var children := cur.get_children()
			for i in range(children.size() - 1, -1, -1):
				stack.append(children[i])

	for n3d in nodes_to_show:
		var item := _object_tree.create_item(tree_root)
		item.set_text(0, n3d.name)
		var p := n3d.global_position
		item.set_text(1, "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z])
		_tree_node_map[item] = n3d


func _matches_filter(node: Node3D, search_q: String, filter_id: int) -> bool:
	var lname := node.name.to_lower()
	var spath := node.scene_file_path.to_lower()
	if not search_q.is_empty() and not lname.contains(search_q):
		return false

	match filter_id:
		1: # Мусор
			return lname.contains("trash") or lname.contains("box") or spath.contains("trashitem")
		2: # Грязь
			return lname.contains("dirt") or spath.contains("dirtpatch")
		3: # Урны / Баки
			return lname.contains("bin") or spath.contains("trashbin")
		4: # Меши / Здания
			return node is MeshInstance3D or lname.contains("building") or lname.contains("house") or lname.contains("map")
		5: # Свет / Камеры
			return node is Light3D or node is Camera3D or node is WorldEnvironment
	return true


func _on_tree_item_selected() -> void:
	var item := _object_tree.get_selected()
	if not item or not _tree_node_map.has(item):
		return
	var node: Node = _tree_node_map[item]
	if is_instance_valid(node):
		var sel := EditorInterface.get_selection()
		sel.clear()
		sel.add_node(node)


func _on_tree_item_activated() -> void:
	_on_tree_item_selected()
	_on_focus_selected_pressed()


# ==============================================================================
# РЕДАКТИРОВАНИЕ ВЫДЕЛЕННЫХ ОБЪЕКТОВ
# ==============================================================================

func _get_selected_node3ds() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not Engine.is_editor_hint():
		return result
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is Node3D:
			result.append(n as Node3D)
	return result


func _on_drop_to_ground_pressed() -> void:
	var nodes := _get_selected_node3ds()
	var root := EditorInterface.get_edited_scene_root()
	if nodes.is_empty() or not root:
		return

	undo_redo.create_action("Опустить объекты на землю")
	for n in nodes:
		var origin := n.global_position + Vector3(0.0, 2.0, 0.0)
		var hit := MapNavigatorRaycastHelper.raycast_scene(origin, Vector3.DOWN, root, [n])
		if not hit.is_empty():
			var old_pos := n.global_position
			var new_pos: Vector3 = hit["position"]
			undo_redo.add_do_property(n, "global_position", new_pos)
			undo_redo.add_undo_property(n, "global_position", old_pos)
	undo_redo.commit_action()
	_update_quick_transform_ui()


func _on_align_upright_pressed() -> void:
	var nodes := _get_selected_node3ds()
	if nodes.is_empty():
		return
	undo_redo.create_action("Выровнять вертикально")
	for n in nodes:
		var old_rot := n.rotation
		var new_rot := Vector3(0.0, n.rotation.y, 0.0)
		undo_redo.add_do_property(n, "rotation", new_rot)
		undo_redo.add_undo_property(n, "rotation", old_rot)
	undo_redo.commit_action()
	_update_quick_transform_ui()


func _on_random_rot_y_pressed() -> void:
	var nodes := _get_selected_node3ds()
	if nodes.is_empty():
		return
	undo_redo.create_action("Случайный поворот Y")
	for n in nodes:
		var old_rot := n.rotation
		var new_rot := Vector3(n.rotation.x, randf_range(0.0, TAU), n.rotation.z)
		undo_redo.add_do_property(n, "rotation", new_rot)
		undo_redo.add_undo_property(n, "rotation", old_rot)
	undo_redo.commit_action()
	_update_quick_transform_ui()


func _on_random_scale_pressed() -> void:
	var nodes := _get_selected_node3ds()
	if nodes.is_empty():
		return
	var min_s := minf(_scale_min_spin.value, _scale_max_spin.value)
	var max_s := maxf(_scale_min_spin.value, _scale_max_spin.value)
	undo_redo.create_action("Случайный масштаб")
	for n in nodes:
		var old_scale := n.scale
		var s := randf_range(min_s, max_s)
		undo_redo.add_do_property(n, "scale", Vector3.ONE * s)
		undo_redo.add_undo_property(n, "scale", old_scale)
	undo_redo.commit_action()


func _rotate_selected_y(degrees: float) -> void:
	var nodes := _get_selected_node3ds()
	if nodes.is_empty():
		return
	var rad := deg_to_rad(degrees)
	undo_redo.create_action("Поворот Y на %.0f°" % degrees)
	for n in nodes:
		var old_rot := n.rotation
		var new_rot := Vector3(n.rotation.x, n.rotation.y + rad, n.rotation.z)
		undo_redo.add_do_property(n, "rotation", new_rot)
		undo_redo.add_undo_property(n, "rotation", old_rot)
	undo_redo.commit_action()
	_update_quick_transform_ui()


func _on_duplicate_selected_pressed() -> void:
	var nodes := _get_selected_node3ds()
	var root := EditorInterface.get_edited_scene_root()
	if nodes.is_empty() or not root:
		return

	undo_redo.create_action("Дублировать объекты")
	var new_nodes: Array[Node] = []
	for n in nodes:
		var dup := n.duplicate() as Node3D
		if dup:
			var parent := n.get_parent() if n.get_parent() else root
			undo_redo.add_do_method(parent, "add_child", dup)
			undo_redo.add_do_property(dup, "owner", root)
			undo_redo.add_do_property(dup, "global_position", n.global_position + Vector3(1.0, 0.0, 1.0))
			undo_redo.add_do_reference(dup)
			undo_redo.add_undo_method(parent, "remove_child", dup)
			new_nodes.append(dup)
	undo_redo.commit_action()

	if not new_nodes.is_empty():
		var sel := EditorInterface.get_selection()
		sel.clear()
		for dn in new_nodes:
			sel.add_node(dn)


func _on_delete_selected_pressed() -> void:
	var nodes := _get_selected_node3ds()
	var root := EditorInterface.get_edited_scene_root()
	if nodes.is_empty():
		return
	undo_redo.create_action("Удалить объекты")
	for n in nodes:
		if n == root:
			continue
		var parent := n.get_parent()
		if parent:
			undo_redo.add_do_method(parent, "remove_child", n)
			undo_redo.add_undo_method(parent, "add_child", n)
			undo_redo.add_undo_property(n, "owner", root)
			undo_redo.add_undo_reference(n)
	undo_redo.commit_action()
	_refresh_object_list()


# ==============================================================================
# РЕЖИМ КИСТИ (РАССТАНОВКА ПО КЛИКУ)
# ==============================================================================

func _on_place_mode_toggled(toggled: bool) -> void:
	place_mode_enabled = toggled
	if toggled:
		# Чтобы _forward_3d_gui_input получал события, должен быть выбран Node3D
		var sel := EditorInterface.get_selection()
		var selected := sel.get_selected_nodes()
		var has_node3d := false
		for n in selected:
			if n is Node3D:
				has_node3d = true
				break
		if not has_node3d:
			var root := EditorInterface.get_edited_scene_root()
			if root is Node3D:
				sel.clear()
				sel.add_node(root)
	place_mode_changed.emit(toggled)


func _set_selected_prefab(path: String) -> void:
	selected_prefab_path = path
	_prefab_label.text = "Префаб: %s" % path.get_file()


func _on_prefab_file_selected(path: String) -> void:
	_set_selected_prefab(path)


func place_prefab_at(world_pos: Vector3, surface_normal: Vector3) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return
	if not ResourceLoader.exists(selected_prefab_path):
		push_warning("MapNavigator: не найден префаб '%s'" % selected_prefab_path)
		return

	var packed := ResourceLoader.load(selected_prefab_path) as PackedScene
	if not packed:
		return

	var instance := packed.instantiate() as Node3D
	if not instance:
		return

	var target_parent := _resolve_target_parent(root, selected_prefab_path)
	var xform := Transform3D(Basis.IDENTITY, world_pos)

	if _place_align_normal_cb.button_pressed and surface_normal.length_squared() > 0.01:
		var up := surface_normal.normalized()
		var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
		var right := up.cross(ref).normalized()
		var forward := right.cross(up).normalized()
		xform.basis = Basis(right, up, forward)

	if _place_rand_rot_cb.button_pressed:
		xform.basis = xform.basis.rotated(xform.basis.y.normalized(), randf_range(0.0, TAU))

	if _place_rand_scale_cb.button_pressed:
		var min_s := minf(_scale_min_spin.value, _scale_max_spin.value)
		var max_s := maxf(_scale_min_spin.value, _scale_max_spin.value)
		var s := randf_range(min_s, max_s)
		xform.basis = xform.basis.scaled(Vector3.ONE * s)

	undo_redo.create_action("Разместить %s" % selected_prefab_path.get_file())
	undo_redo.add_do_method(target_parent, "add_child", instance)
	undo_redo.add_do_property(instance, "owner", root)
	undo_redo.add_do_property(instance, "global_transform", xform)
	undo_redo.add_do_reference(instance)
	undo_redo.add_undo_method(target_parent, "remove_child", instance)
	undo_redo.commit_action()
	_refresh_object_list()


func _resolve_target_parent(root: Node, prefab_path: String) -> Node:
	var lp := prefab_path.to_lower()
	if lp.contains("trashitem"):
		var n := root.get_node_or_null("TrashObjects")
		if n:
			return n
	elif lp.contains("dirtpatch"):
		var n := root.get_node_or_null("DirtPatches")
		if n:
			return n
	return root


# ==============================================================================
# БЫСТРАЯ ПРАВКА КООРДИНАТ
# ==============================================================================

func _on_editor_selection_changed() -> void:
	_update_quick_transform_ui()


func _update_quick_transform_ui() -> void:
	if not _transform_box:
		return
	var nodes := _get_selected_node3ds()
	if nodes.is_empty():
		_transform_box.visible = false
		return

	_transform_box.visible = true
	var n := nodes[0]
	_updating_transform_ui = true
	_pos_x_spin.value = n.position.x
	_pos_y_spin.value = n.position.y
	_pos_z_spin.value = n.position.z
	_rot_y_spin.value = rad_to_deg(n.rotation.y)
	_updating_transform_ui = false


func _on_quick_transform_changed(_val: float) -> void:
	if _updating_transform_ui:
		return
	var nodes := _get_selected_node3ds()
	if nodes.is_empty():
		return
	var n := nodes[0]
	var new_pos := Vector3(_pos_x_spin.value, _pos_y_spin.value, _pos_z_spin.value)
	var new_rot := Vector3(n.rotation.x, deg_to_rad(_rot_y_spin.value), n.rotation.z)

	undo_redo.create_action("Изменить трансформацию")
	undo_redo.add_do_property(n, "position", new_pos)
	undo_redo.add_do_property(n, "rotation", new_rot)
	undo_redo.add_undo_property(n, "position", n.position)
	undo_redo.add_undo_property(n, "rotation", n.rotation)
	undo_redo.commit_action()
