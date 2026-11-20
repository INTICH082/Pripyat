class_name SosnovkaVillage
extends Node3D

## Контроллер локации «Деревня Сосновка (Торговая тропа)».
## Отвечает за генерацию физических коллизий для геометрии карты,
## исключая декоративную растительность, кусты, траву и спрайты щебня,
## а также за отслеживание границ игрового мира.

@export var default_spawn_position: Vector3 = Vector3(25.0, 0.25, 45.0)

@onready var map_node: Node3D = $SosnovkaMap
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var sun_light: DirectionalLight3D = $DirectionalLight3D

func _ready() -> void:
	if map_node:
		_generate_environment_collisions(map_node)
	
	# Позиционируем игрока на точку возрождения Spawn_01, если он найден
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.global_position.distance_squared_to(Vector3.ZERO) < 0.1:
		player.global_position = default_spawn_position

func _physics_process(_delta: float) -> void:
	# Защита от выпадения за пределы игрового мира
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player and player.global_position.y < -15.0:
		player.velocity = Vector3.ZERO
		player.global_position = default_spawn_position

## Рекурсивно генерирует trimesh коллизии для мешей окружения
func _generate_environment_collisions(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		var mesh_name := node.name.to_lower()
		if not _is_pass_through_decor(mesh_name):
			var already_has_collision := false
			for child in node.get_children():
				if child is StaticBody3D:
					already_has_collision = true
					break
			
			if not already_has_collision:
				node.create_trimesh_collision()
				for child in node.get_children():
					if child is StaticBody3D:
						child.collision_layer = 1
						child.collision_mask = 3
	
	for child in node.get_children():
		_generate_environment_collisions(child)

## Проверяет, является ли объект декоративной растительностью или мелким декалем
func _is_pass_through_decor(name_lower: String) -> bool:
	var ignore_patterns: Array[String] = [
		"трава", "курт", "куст", "ветв", "листв", "камен", "щебн", "выбоин",
		"grass", "bush", "leaf", "leaves", "branch", "pebble", "sprite"
	]
	for pattern in ignore_patterns:
		if pattern in name_lower:
			return true
	return false
