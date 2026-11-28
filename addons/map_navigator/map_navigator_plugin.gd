@tool
extends EditorPlugin

## EditorPlugin «Map Navigator & Editor».
## Подключает панель навигации и редактирования карты к редактору Godot 4,
## перехватывает клики в 3D-вьюпорте для режима кисти и отображает 3D-маркер прицела.

const DockScript = preload("res://addons/map_navigator/map_navigator_dock.gd")

var _dock: MapNavigatorDock
var _preview_marker: MeshInstance3D


func _enter_tree() -> void:
	_dock = DockScript.new()
	_dock.undo_redo = get_undo_redo()
	_dock.place_mode_changed.connect(_on_place_mode_changed)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

	if not scene_changed.is_connected(_on_scene_changed):
		scene_changed.connect(_on_scene_changed)


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)

	_destroy_preview_marker()

	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _handles(object: Object) -> bool:
	return object is Node3D


func _on_scene_changed(_scene_root: Node) -> void:
	_destroy_preview_marker()
	if _dock:
		_dock.refresh_for_current_scene()


func _on_place_mode_changed(enabled: bool) -> void:
	if enabled:
		_ensure_preview_marker()
	else:
		_destroy_preview_marker()


func _ensure_preview_marker() -> void:
	if is_instance_valid(_preview_marker):
		return
	var root := EditorInterface.get_edited_scene_root()
	if not root:
		return

	_preview_marker = MeshInstance3D.new()
	_preview_marker.name = "__MapNavigatorPreviewMarker__"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.28
	torus.outer_radius = 0.36
	_preview_marker.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.9, 1.0, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_preview_marker.material_override = mat
	_preview_marker.visible = false

	# owner оставляем null, чтобы маркер никогда не сохранялся в .tscn файл
	root.add_child(_preview_marker)


func _destroy_preview_marker() -> void:
	if is_instance_valid(_preview_marker):
		_preview_marker.queue_free()
	_preview_marker = null


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not _dock or not _dock.place_mode_enabled:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var root := EditorInterface.get_edited_scene_root()
	if not root or not viewport_camera:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Выход из режима кисти по Escape
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_dock._place_mode_btn.button_pressed = false
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Обновляем позицию 3D-маркера при движении мыши
	if event is InputEventMouseMotion:
		_ensure_preview_marker()
		var origin := viewport_camera.project_ray_origin(event.position)
		var dir := viewport_camera.project_ray_normal(event.position)
		var exclude: Array = [_preview_marker] if is_instance_valid(_preview_marker) else []
		var hit := MapNavigatorRaycastHelper.raycast_scene(origin, dir, root, exclude)
		if is_instance_valid(_preview_marker):
			if not hit.is_empty():
				_preview_marker.visible = true
				var pos: Vector3 = hit["position"]
				var nrm: Vector3 = hit["normal"]
				var up := nrm.normalized() if nrm.length_squared() > 0.01 else Vector3.UP
				var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
				var right := up.cross(ref).normalized()
				var forward := right.cross(up).normalized()
				_preview_marker.global_transform = Transform3D(Basis(right, up, forward), pos + up * 0.03)
			else:
				_preview_marker.visible = false
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Размещение префаба по обычному ЛКМ (не мешаем Alt/Ctrl/ПКМ навигации)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.alt_pressed and not mb.ctrl_pressed and not mb.shift_pressed:
			var origin := viewport_camera.project_ray_origin(mb.position)
			var dir := viewport_camera.project_ray_normal(mb.position)
			var exclude: Array = [_preview_marker] if is_instance_valid(_preview_marker) else []
			var hit := MapNavigatorRaycastHelper.raycast_scene(origin, dir, root, exclude)
			if not hit.is_empty():
				_dock.place_prefab_at(hit["position"], hit["normal"])
				return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS
