class_name DirtPatch
extends StaticBody3D

## Высокопроизводительное скопление грязи / мха / копоти на MultiMeshInstance3D.
## Использует единый коллайдер и один draw-call на всю сетку пятен вместо десятков Area3D.
## Поддерживает точечное стирание по радиусу воздействия инструмента и модификаторы класса.

@export var grid_width: int = 5
@export var grid_height: int = 4
@export var spacing: float = 0.28
@export var is_wall_mounted: bool = true
@export var base_color: Color = Color(0.24, 0.2, 0.14)
@export var spot_reward: int = 1
@export var spot_health: float = 0.35

var multimesh_instance: MultiMeshInstance3D
var collision_shape: CollisionShape3D

class SpotData:
	var local_pos: Vector3
	var base_scale: Vector3
	var rotation: Vector3
	var health: float
	var max_health: float
	var is_cleared: bool = false
	var index: int

var spots: Array[SpotData] = []
var active_spots_count: int = 0

func _ready() -> void:
	add_to_group("dirt_patch")
	collision_layer = 1
	collision_mask = 3
	_setup_multimesh()
	_setup_collision()

func _setup_multimesh() -> void:
	var total_count = grid_width * grid_height
	multimesh_instance = MultiMeshInstance3D.new()
	multimesh_instance.name = "MultiMeshInstance3D"
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = total_count
	
	# Общий плоский цилиндрический меш
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.16
	cylinder.bottom_radius = 0.16
	cylinder.height = 0.015
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	cylinder.material = mat
	mm.mesh = cylinder
	
	multimesh_instance.multimesh = mm
	add_child(multimesh_instance)
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var offset_x = (grid_width - 1) * spacing * 0.5
	var offset_y = (grid_height - 1) * spacing * 0.5
	
	spots.clear()
	active_spots_count = total_count
	
	var idx = 0
	for x in range(grid_width):
		for y in range(grid_height):
			var spot = SpotData.new()
			spot.index = idx
			spot.health = spot_health
			spot.max_health = spot_health
			
			var jitter = Vector3(
				rng.randf_range(-0.04, 0.04),
				rng.randf_range(-0.04, 0.04),
				0.005 + idx * 0.0005 # Небольшой сдвиг по оси Z для исключения Z-fighting
			)
			
			if is_wall_mounted:
				spot.local_pos = Vector3(x * spacing - offset_x, y * spacing - offset_y, 0.0) + jitter
				spot.rotation = Vector3(deg_to_rad(90), 0, deg_to_rad(rng.randf_range(0, 360)))
			else:
				spot.local_pos = Vector3(x * spacing - offset_x, 0.01, y * spacing - offset_y) + Vector3(jitter.x, jitter.z, jitter.y)
				spot.rotation = Vector3(0, deg_to_rad(rng.randf_range(0, 360)), 0)
				
			var s = rng.randf_range(0.9, 1.25)
			spot.base_scale = Vector3(s, 1.0, s)
			
			# Устанавливаем начальную матрицу в MultiMesh
			var t = Transform3D()
			t = t.scaled(spot.base_scale)
			t = t.rotated(Vector3(1, 0, 0), spot.rotation.x)
			t = t.rotated(Vector3(0, 1, 0), spot.rotation.y)
			t = t.rotated(Vector3(0, 0, 1), spot.rotation.z)
			t.origin = spot.local_pos
			mm.set_instance_transform(idx, t)
			
			var col_jitter = rng.randf_range(-0.04, 0.04)
			var c = Color(
				clampf(base_color.r + col_jitter, 0.0, 1.0),
				clampf(base_color.g + col_jitter, 0.0, 1.0),
				clampf(base_color.b + col_jitter, 0.0, 1.0)
			)
			mm.set_instance_color(idx, c)
			
			spots.append(spot)
			if GameState:
				GameState.register_cleanup_item()
			idx += 1

func _setup_collision() -> void:
	collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var box = BoxShape3D.new()
	
	var total_w = grid_width * spacing + 0.15
	var total_h = grid_height * spacing + 0.15
	if is_wall_mounted:
		box.size = Vector3(total_w, total_h, 0.12)
		collision_shape.position = Vector3(0, 0, 0.02)
	else:
		box.size = Vector3(total_w, 0.12, total_h)
		collision_shape.position = Vector3(0, 0.02, 0)
		
	collision_shape.shape = box
	add_child(collision_shape)

## Соскабливание пятен в радиусе от точки соприкосновения
func scrub_at_point(world_hit_pos: Vector3, scrub_delta: float, brush_radius: float = 0.35) -> bool:
	if active_spots_count <= 0 or not multimesh_instance:
		return false
		
	var local_hit = to_local(world_hit_pos)
	var mm = multimesh_instance.multimesh
	var any_scrubbed = false
	var radius_sq = brush_radius * brush_radius
	
	for spot in spots:
		if spot.is_cleared:
			continue
			
		var dist_sq = local_hit.distance_squared_to(spot.local_pos)
		if dist_sq <= radius_sq:
			any_scrubbed = true
			spot.health -= scrub_delta
			
			var ratio = clampf(spot.health / spot.max_health, 0.0, 1.0)
			if spot.health <= 0.0:
				spot.is_cleared = true
				active_spots_count -= 1
				
				# Прячем инстанс
				var zero_t = Transform3D()
				zero_t = zero_t.scaled(Vector3.ZERO)
				zero_t.origin = spot.local_pos
				mm.set_instance_transform(spot.index, zero_t)
				
				EventBus.dirt_cleaned.emit(spot_reward, to_global(spot.local_pos))
			else:
				# Уменьшаем масштаб инстанса
				var cur_scale = spot.base_scale * ratio
				var t = Transform3D()
				t = t.scaled(cur_scale)
				t = t.rotated(Vector3(1, 0, 0), spot.rotation.x)
				t = t.rotated(Vector3(0, 1, 0), spot.rotation.y)
				t = t.rotated(Vector3(0, 0, 1), spot.rotation.z)
				t.origin = spot.local_pos
				mm.set_instance_transform(spot.index, t)
				
	if active_spots_count <= 0 and collision_shape:
		collision_shape.disabled = true
		
	return any_scrubbed

## Метод совместимости со старыми вызовами
func scrub(delta_time: float) -> void:
	scrub_at_point(global_position, delta_time, 1.0)
