class_name CheckpointManager
extends Node

## Менеджер контрольных точек на карте.
## Разработчики расставляют возможные позиции (слоты) на уровне (в контейнере или группе "checkpoint_slots"),
## а менеджер при старте карты случайно выбирает нужное количество точек,
## генерирует задачи под 1-4 игроков и ведет прогрессию до открытия следующей карты и перехода в хаб.

signal all_checkpoints_completed(location_id: String, next_location_id: String)

@export var slots_container_path: NodePath
@export var checkpoint_scene: PackedScene
@export var checkpoints_per_map: int = 3
@export var auto_initialize_on_ready: bool = true
@export var auto_enter_hub_on_complete: bool = true
@export var random_seed: int = 0 # 0 = случайный seed на каждую вылазку

var active_checkpoints: Array[CheckpointPoint] = []
var current_checkpoint_index: int = -1

func _ready() -> void:
	if auto_initialize_on_ready:
		call_deferred("setup_checkpoints")

## Собирает слоты, случайно выбирает контрольные точки и запускает первую из них.
func setup_checkpoints(override_player_count: int = -1, override_location_id: String = "") -> void:
	_clear_active_checkpoints()

	var slots := _collect_slot_nodes()
	if slots.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	if random_seed != 0:
		rng.seed = random_seed
	else:
		rng.randomize()

	# Перемешиваем слоты и выбираем случайные контрольные точки
	var shuffled_slots := slots.duplicate()
	for i in range(shuffled_slots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = shuffled_slots[i]
		shuffled_slots[i] = shuffled_slots[j]
		shuffled_slots[j] = tmp

	var target_count := mini(maxi(1, checkpoints_per_map), shuffled_slots.size())
	var player_count := override_player_count if override_player_count > 0 else _detect_player_count()
	var loc_id := override_location_id if not override_location_id.is_empty() else (GameState.current_location_id if GameState else "kopachi")
	var difficulty_tier := 1
	if GameState:
		difficulty_tier = int(GameState.get_location(loc_id).get("index", 1))

	for i in range(target_count):
		var slot: Node3D = shuffled_slots[i]
		var cp := _create_or_bind_checkpoint(slot, i)
		if cp:
			cp.sequence_index = i
			cp.initialize_tasks(player_count, difficulty_tier, rng)
			cp.checkpoint_finished.connect(_on_checkpoint_finished)
			active_checkpoints.append(cp)
			if EventBus:
				EventBus.checkpoint_registered.emit(cp.checkpoint_id, i, target_count)

	if not active_checkpoints.is_empty():
		current_checkpoint_index = 0
		active_checkpoints[0].unlock()

func get_current_checkpoint() -> CheckpointPoint:
	if current_checkpoint_index >= 0 and current_checkpoint_index < active_checkpoints.size():
		return active_checkpoints[current_checkpoint_index]
	return null

func get_completed_count() -> int:
	var count := 0
	for cp in active_checkpoints:
		if cp.state == CheckpointPoint.State.COMPLETED:
			count += 1
	return count

func _collect_slot_nodes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not slots_container_path.is_empty():
		var container := get_node_or_null(slots_container_path)
		if container:
			for child in container.get_children():
				if child is Node3D:
					result.append(child)
			return result

	for node in get_tree().get_nodes_in_group("checkpoint_slots"):
		if node is Node3D:
			result.append(node)
	return result

func _create_or_bind_checkpoint(slot: Node3D, index: int) -> CheckpointPoint:
	if slot is CheckpointPoint:
		slot.state = CheckpointPoint.State.LOCKED
		return slot

	var cp: CheckpointPoint = null
	if checkpoint_scene:
		cp = checkpoint_scene.instantiate() as CheckpointPoint
	else:
		cp = CheckpointPoint.new()

	cp.name = "Checkpoint_%d" % (index + 1)
	if cp.checkpoint_id.is_empty():
		cp.checkpoint_id = "cp_%s_%d" % [slot.name, index + 1]
	if cp.display_name == "Контрольная точка":
		cp.display_name = "Точка #%d" % (index + 1)

	slot.add_child(cp)
	cp.position = Vector3.ZERO
	return cp

func _on_checkpoint_finished(checkpoint: CheckpointPoint) -> void:
	if checkpoint != get_current_checkpoint():
		return

	current_checkpoint_index += 1
	if current_checkpoint_index < active_checkpoints.size():
		active_checkpoints[current_checkpoint_index].unlock()
		return

	# Все контрольные точки карты выполнены -> открываем следующую карту и отправляем в хаб
	var completed_loc := GameState.current_location_id if GameState else ""
	var next_loc := ""
	if GameState:
		next_loc = GameState.unlock_next_location(completed_loc)
		if auto_enter_hub_on_complete:
			GameState.enter_hub_before_next_map(next_loc)
	all_checkpoints_completed.emit(completed_loc, next_loc)

func _detect_player_count() -> int:
	if NetworkManager and NetworkManager.has_method("get_connected_player_count"):
		var count: int = int(NetworkManager.call("get_connected_player_count"))
		if count > 0:
			return clampi(count, 1, 4)
	var group_count := get_tree().get_nodes_in_group("players").size()
	return clampi(maxi(1, group_count), 1, 4)

func _clear_active_checkpoints() -> void:
	for cp in active_checkpoints:
		if is_instance_valid(cp) and cp.checkpoint_finished.is_connected(_on_checkpoint_finished):
			cp.checkpoint_finished.disconnect(_on_checkpoint_finished)
	active_checkpoints.clear()
	current_checkpoint_index = -1
