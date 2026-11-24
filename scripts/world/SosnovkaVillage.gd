class_name SosnovkaVillage
extends Node3D

## Контроллер локации «Деревня Сосновка (Торговая тропа)».
## Отвечает за генерацию физических коллизий для геометрии карты,
## спавн сетевого отряда до 4 ликвидаторов и защиту от выпадения за пределы мира.

@export var player_scene: PackedScene = preload("res://scenes/player/Player.tscn")

@export var default_spawn_position: Vector3 = Vector3(25.0, 0.25, 45.0)
@export var spawn_points: Array[Vector3] = [
	Vector3(25.0, 0.25, 45.0),
	Vector3(26.8, 0.25, 43.5),
	Vector3(23.2, 0.25, 43.5),
	Vector3(25.0, 0.25, 42.0)
]

@onready var map_node: Node3D = $SosnovkaMap
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var sun_light: DirectionalLight3D = $DirectionalLight3D
@onready var players_container: Node3D = get_node_or_null("PlayersContainer")

func _ready() -> void:
	if map_node:
		_generate_environment_collisions(map_node)
	
	# Спавним игроков через NetworkManager (одиночно или мультиплеер от 1 до 4 бойцов)
	if not players_container:
		players_container = Node3D.new()
		players_container.name = "PlayersContainer"
		add_child(players_container)
		
	if NetworkManager:
		NetworkManager.spawn_players(players_container, spawn_points, player_scene)
	else:
		_spawn_local_fallback()

func _spawn_local_fallback() -> void:
	if not player_scene or not players_container:
		return
	var p = player_scene.instantiate() as PlayerController
	p.name = "Player_1"
	p.set_multiplayer_authority(1)
	players_container.add_child(p)
	p.global_position = default_spawn_position
	p.setup_player({
		"peer_id": 1,
		"name": "Ликвидатор",
		"class_id": GameState.current_class_id if GameState else "cleaner",
		"is_host": true,
		"slot": 0
	})

func _physics_process(_delta: float) -> void:
	# Защита от выпадения за пределы игрового мира для всех активных игроков
	if players_container:
		for child in players_container.get_children():
			var player = child as CharacterBody3D
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
