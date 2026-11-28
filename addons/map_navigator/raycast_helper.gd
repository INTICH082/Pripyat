@tool
class_name MapNavigatorRaycastHelper
extends RefCounted

## Вспомогательный класс для точного рейкаста по 3D-карте в редакторе.
## Поддерживает как физические коллизии (StaticBody3D), так и сырые MeshInstance3D
## (актуально для импортированных .glb карт вроде SosnovkaMap, где коллизии создаются в рантайме).

const MAX_RAY_DISTANCE: float = 2000.0


static func raycast_scene(
	origin: Vector3,
	direction: Vector3,
	scene_root: Node,
	exclude_nodes: Array = []
) -> Dictionary:
	if not scene_root or not is_instance_valid(scene_root):
		return {}

	var dir := direction.normalized()
	var best_hit: Dictionary = {}
	var best_dist: float = INF

	# 1. Пробуем физический рейкаст (если в сцене есть StaticBody3D / CollisionShape3D)
	if scene_root is Node3D:
		var world_3d: World3D = (scene_root as Node3D).get_world_3d()
		if world_3d and world_3d.direct_space_state:
			var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * MAX_RAY_DISTANCE)
			var exclude_rids: Array[RID] = []
			for ex in exclude_nodes:
				if is_instance_valid(ex):
					_collect_collision_rids(ex, exclude_rids)
			query.exclude = exclude_rids
			var phys_result := world_3d.direct_space_state.intersect_ray(query)
			if not phys_result.is_empty():
				var dist: float = origin.distance_to(phys_result["position"])
				if dist < best_dist:
					best_dist = dist
					best_hit = {
						"hit": true,
						"position": phys_result["position"],
						"normal": phys_result["normal"],
						"node": phys_result["collider"],
						"distance": dist
					}

	# 2. Дополнительно проверяем MeshInstance3D напрямую (для мешей без коллизий)
	var mesh_hit := _raycast_meshes(origin, dir, scene_root, exclude_nodes, best_dist)
	if not mesh_hit.is_empty() and mesh_hit["distance"] < best_dist:
		best_hit = mesh_hit

	return best_hit


static func _collect_collision_rids(node: Node, out_rids: Array[RID]) -> void:
	if node is CollisionObject3D:
		out_rids.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		_collect_collision_rids(child, out_rids)


static func _is_excluded(node: Node, exclude_nodes: Array) -> bool:
	for ex in exclude_nodes:
		if not is_instance_valid(ex):
			continue
		if node == ex or (ex is Node and (ex as Node).is_ancestor_of(node)):
			return true
	return false


static func _raycast_meshes(
	origin: Vector3,
	dir: Vector3,
	root: Node,
	exclude_nodes: Array,
	max_dist: float
) -> Dictionary:
	var best_hit: Dictionary = {}
	var best_dist: float = max_dist

	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if _is_excluded(current, exclude_nodes):
			continue
		if current is Node3D and not (current as Node3D).visible:
			continue

		if current is MeshInstance3D:
			var mi := current as MeshInstance3D
			if mi.mesh:
				var inv_xform: Transform3D = mi.global_transform.affine_inverse()
				var local_origin: Vector3 = inv_xform * origin
				var local_dir: Vector3 = (inv_xform.basis * dir).normalized()
				var aabb: AABB = mi.mesh.get_aabb()

				if aabb.intersects_ray(local_origin, local_dir) != null:
					var faces: PackedVector3Array = mi.mesh.get_faces()
					var face_count: int = faces.size()
					var i: int = 0
					while i + 2 < face_count:
						var v0: Vector3 = faces[i]
						var v1: Vector3 = faces[i + 1]
						var v2: Vector3 = faces[i + 2]
						var res = Geometry3D.ray_intersects_triangle(local_origin, local_dir, v0, v1, v2)
						if res != null:
							var world_pos: Vector3 = mi.global_transform * (res as Vector3)
							var dist: float = origin.distance_to(world_pos)
							if dist > 0.001 and dist < best_dist:
								best_dist = dist
								var local_normal: Vector3 = (v1 - v0).cross(v2 - v0).normalized()
								var world_normal: Vector3 = (mi.global_transform.basis * local_normal).normalized()
								# Убедимся, что нормаль смотрит навстречу лучу
								if world_normal.dot(dir) > 0.0:
									world_normal = -world_normal
								best_hit = {
									"hit": true,
									"position": world_pos,
									"normal": world_normal,
									"node": mi,
									"distance": dist
								}
						i += 3

		for child in current.get_children():
			stack.append(child)

	return best_hit


## Вычисляет мировой AABB узла (учитывая дочерние MeshInstance3D) для удобного фокуса камеры.
static func get_node_world_bounds(node: Node3D) -> AABB:
	var has_bounds := false
	var combined := AABB()

	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh:
				var local_aabb := mi.mesh.get_aabb()
				var world_aabb := mi.global_transform * local_aabb
				if not has_bounds:
					combined = world_aabb
					has_bounds = true
				else:
					combined = combined.merge(world_aabb)
		for c in cur.get_children():
			stack.append(c)

	if not has_bounds:
		return AABB(node.global_position - Vector3.ONE, Vector3.ONE * 2.0)
	return combined
