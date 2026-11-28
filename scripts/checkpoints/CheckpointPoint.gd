class_name CheckpointPoint
extends Node3D

## Контрольная точка на карте (размещается разработчиками в редакторе или спавнится CheckpointManager).
## При подходе игроков активируется и требует выполнения назначенных задач
## (волны существ, очистка мусора, головоломки, дезактивация, ремонт, доставка).

enum State {
	LOCKED,     # Ожидает завершения предыдущей контрольной точки
	AVAILABLE,  # Открыта для подхода игроков
	ACTIVE,     # Игроки подошли, задачи выполняются
	COMPLETED   # Все задачи точки выполнены
}

signal state_changed(checkpoint: CheckpointPoint, new_state: State)
signal task_progressed(checkpoint: CheckpointPoint, task: CheckpointTask)
signal checkpoint_finished(checkpoint: CheckpointPoint)

@export var checkpoint_id: String = ""
@export var display_name: String = "Контрольная точка"
@export var activation_radius: float = 8.0
@export var require_all_players: bool = false
@export var auto_track_cleanup_events: bool = true
@export var reward_karbovantsi: int = 100
@export var allowed_task_types: Array[CheckpointTask.TaskType] = []
@export var tasks_count: int = 2
@export var preset_tasks: Array[CheckpointTask] = []

var state: State = State.LOCKED
var tasks: Array[CheckpointTask] = []
var sequence_index: int = 0

func _ready() -> void:
	if checkpoint_id.is_empty():
		checkpoint_id = name
	if auto_track_cleanup_events and EventBus:
		EventBus.trash_deposited.connect(_on_global_trash_deposited)
		EventBus.dirt_cleaned.connect(_on_global_dirt_cleaned)

func _physics_process(_delta: float) -> void:
	if state == State.AVAILABLE:
		_check_player_proximity()

## Инициализирует задачи контрольной точки (использует preset_tasks или генерирует случайные).
func initialize_tasks(player_count: int, difficulty_tier: int, rng: RandomNumberGenerator = null) -> void:
	tasks.clear()
	if not preset_tasks.is_empty():
		for preset in preset_tasks:
			if preset:
				var copy := preset.duplicate(true) as CheckpointTask
				copy.reset()
				tasks.append(copy)
		return

	var pool: Array[CheckpointTask.TaskType] = []
	if not allowed_task_types.is_empty():
		pool.append_array(allowed_task_types)
	else:
		pool = [
			CheckpointTask.TaskType.WAVE_DEFENSE,
			CheckpointTask.TaskType.CLEANUP,
			CheckpointTask.TaskType.PUZZLE,
			CheckpointTask.TaskType.DECONTAMINATION,
			CheckpointTask.TaskType.REPAIR,
			CheckpointTask.TaskType.DELIVERY
		]

	var local_rng := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		local_rng.randomize()

	var count := mini(maxi(1, tasks_count), pool.size())
	var shuffled := pool.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := local_rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp

	for i in range(count):
		var task_type: CheckpointTask.TaskType = shuffled[i]
		tasks.append(CheckpointTask.create_default_task(task_type, player_count, difficulty_tier, checkpoint_id))

func unlock() -> void:
	if state != State.LOCKED:
		return
	state = State.AVAILABLE
	state_changed.emit(self, state)
	if EventBus:
		EventBus.checkpoint_unlocked.emit(checkpoint_id, display_name)

func activate() -> void:
	if state != State.AVAILABLE:
		return
	state = State.ACTIVE
	state_changed.emit(self, state)
	if EventBus:
		var serialized: Array = []
		for t in tasks:
			serialized.append(t.to_dict())
		EventBus.checkpoint_activated.emit(checkpoint_id, serialized)

func _check_player_proximity() -> void:
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		return

	var players_in_zone := 0
	var total_players := 0
	for p in players:
		if p is Node3D:
			total_players += 1
			if p.global_position.distance_to(global_position) <= activation_radius:
				players_in_zone += 1

	if total_players == 0:
		return
	if require_all_players:
		if players_in_zone >= total_players:
			activate()
	elif players_in_zone > 0:
		activate()

## Продвигает первую незавершенную задачу указанного типа.
func advance_task_by_type(type: CheckpointTask.TaskType, amount: int = 1) -> bool:
	if state != State.ACTIVE:
		return false
	for task in tasks:
		if task.task_type == type and not task.is_completed:
			task.advance(amount)
			task_progressed.emit(self, task)
			if EventBus:
				EventBus.checkpoint_task_updated.emit(checkpoint_id, task.task_id, task.get_progress(), task.is_completed)
			_check_all_tasks_completed()
			return true
	return false

## Удобные методы для вызова из подсистем (волны, уборка, головоломки, ремонт и т.д.)
func report_wave_cleared(waves_count: int = 1) -> bool:
	return advance_task_by_type(CheckpointTask.TaskType.WAVE_DEFENSE, waves_count)

func report_cleanup_progress(amount: int = 1) -> bool:
	return advance_task_by_type(CheckpointTask.TaskType.CLEANUP, amount)

func report_puzzle_step(steps: int = 1) -> bool:
	return advance_task_by_type(CheckpointTask.TaskType.PUZZLE, steps)

func solve_puzzle() -> bool:
	if state != State.ACTIVE:
		return false
	for task in tasks:
		if task.task_type == CheckpointTask.TaskType.PUZZLE and not task.is_completed:
			task.set_completed()
			task_progressed.emit(self, task)
			if EventBus:
				EventBus.checkpoint_task_updated.emit(checkpoint_id, task.task_id, 1.0, true)
			_check_all_tasks_completed()
			return true
	return false

func report_decontamination_progress(amount: int = 1) -> bool:
	return advance_task_by_type(CheckpointTask.TaskType.DECONTAMINATION, amount)

func report_repair_progress(amount: int = 1) -> bool:
	return advance_task_by_type(CheckpointTask.TaskType.REPAIR, amount)

func report_delivery(amount: int = 1) -> bool:
	return advance_task_by_type(CheckpointTask.TaskType.DELIVERY, amount)

func get_overall_progress() -> float:
	if tasks.is_empty():
		return 1.0 if state == State.COMPLETED else 0.0
	var sum := 0.0
	for task in tasks:
		sum += task.get_progress()
	return sum / float(tasks.size())

func _check_all_tasks_completed() -> void:
	for task in tasks:
		if not task.is_completed:
			return
	state = State.COMPLETED
	state_changed.emit(self, state)
	if GameState and reward_karbovantsi > 0:
		GameState.add_karbovantsi(reward_karbovantsi)
	if EventBus:
		EventBus.checkpoint_completed.emit(checkpoint_id, reward_karbovantsi)
	checkpoint_finished.emit(self)

func _on_global_trash_deposited(_trash_name: String, _reward: int) -> void:
	if state == State.ACTIVE:
		report_cleanup_progress(1)

func _on_global_dirt_cleaned(_reward: int, world_pos: Vector3) -> void:
	if state == State.ACTIVE and world_pos.distance_to(global_position) <= activation_radius * 2.5:
		report_cleanup_progress(1)
