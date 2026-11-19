class_name DirtPatch
extends Node3D

## Скопление грязи / мха / пыли, разбитое на отдельные элементы.
## Игрок водит щёткой, и элементы исчезают строго в точке соприкосновения.

@export var grid_width: int = 4
@export var grid_height: int = 3
@export var spacing: float = 0.3
@export var is_wall_mounted: bool = true
@export var base_color: Color = Color(0.24, 0.2, 0.14)

func _ready() -> void:
	# Если дочерние точки ещё не расставлены вручную, генерируем органичный кластер
	if get_child_count() == 0:
		_generate_patch()

func _generate_patch() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var offset_x = (grid_width - 1) * spacing * 0.5
	var offset_y = (grid_height - 1) * spacing * 0.5
	
	for x in range(grid_width):
		for y in range(grid_height):
			var spot = DirtSpot.new()
			spot.name = "Spot_%d_%d" % [x, y]
			
			# Небольшой органичный случайный сдвиг
			var rand_offset = Vector3(
				rng.randf_range(-0.06, 0.06),
				rng.randf_range(-0.06, 0.06),
				0.01
			)
			
			var local_pos = Vector3(x * spacing - offset_x, y * spacing - offset_y, 0.0) + rand_offset
			if not is_wall_mounted:
				# Для пола (XZ плоскость)
				local_pos = Vector3(local_pos.x, 0.01, local_pos.y)
				
			spot.transform.origin = local_pos
			
			# Создаем визуальный меш (приплюснутый диск / декальку)
			var mesh_inst = MeshInstance3D.new()
			mesh_inst.name = "MeshInstance3D"
			
			var cylinder = CylinderMesh.new()
			cylinder.top_radius = rng.randf_range(0.12, 0.18)
			cylinder.bottom_radius = cylinder.top_radius
			cylinder.height = 0.02
			
			var mat = StandardMaterial3D.new()
			# Варьируем цвет каждого пятнышка грязи для реализма
			var col_jitter = rng.randf_range(-0.04, 0.04)
			mat.albedo_color = Color(
				clampf(base_color.r + col_jitter, 0.0, 1.0),
				clampf(base_color.g + col_jitter, 0.0, 1.0),
				clampf(base_color.b + col_jitter, 0.0, 1.0)
			)
			mat.roughness = 0.95
			mesh_inst.mesh = cylinder
			mesh_inst.material_override = mat
			
			if is_wall_mounted:
				mesh_inst.rotation_degrees = Vector3(90, 0, rng.randf_range(0, 360))
			else:
				mesh_inst.rotation_degrees = Vector3(0, rng.randf_range(0, 360), 0)
			
			spot.add_child(mesh_inst)
			
			# Коллизия для детекции лучом RayCast
			var col_shape = CollisionShape3D.new()
			var sphere_shape = SphereShape3D.new()
			sphere_shape.radius = cylinder.top_radius * 1.1
			col_shape.shape = sphere_shape
			spot.add_child(col_shape)
			
			add_child(spot)
