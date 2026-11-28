class_name CheckpointTask
extends Resource

## Описание отдельной задачи на контрольной точке.
## Поддерживает базовые типы (волны врагов, уборка мусора, головоломки)
## и дополнительные типы задач для разнообразия вылазок в Зоне.

enum TaskType {
	WAVE_DEFENSE,      # Отбить волны нападающих существ
	CLEANUP,           # Очистить местность от мусора и загрязнений
	PUZZLE,            # Выполнить головоломку (щиток, код, вентили, частота)
	DECONTAMINATION,   # Дезактивация очага радиации / установка фильтра
	REPAIR,            # Ремонт генератора, насоса или укрепление периметра
	DELIVERY           # Сбор и доставка спецгруза / свинцовых капсул на точку
}

@export var task_id: String = ""
@export var task_type: TaskType = TaskType.CLEANUP
@export var title: String = ""
@export var description: String = ""
@export var target_amount: int = 1
@export var current_amount: int = 0
@export var is_completed: bool = false
@export var metadata: Dictionary = {}

## Продвигает выполнение задачи на указанное значение. Возвращает true, если задача только что завершилась.
func advance(amount: int = 1) -> bool:
	if is_completed or amount <= 0:
		return false
	current_amount = mini(target_amount, current_amount + amount)
	if current_amount >= target_amount:
		is_completed = true
		return true
	return false

## Мгновенно завершает задачу (например, при решении головоломки).
func set_completed() -> bool:
	if is_completed:
		return false
	current_amount = target_amount
	is_completed = true
	return true

## Возвращает прогресс выполнения в диапазоне [0.0, 1.0].
func get_progress() -> float:
	if is_completed:
		return 1.0
	if target_amount <= 0:
		return 0.0
	return clampf(float(current_amount) / float(target_amount), 0.0, 1.0)

## Сбрасывает прогресс задачи (для повторного запуска или тестирования).
func reset() -> void:
	current_amount = 0
	is_completed = false

func to_dict() -> Dictionary:
	return {
		"task_id": task_id,
		"task_type": task_type,
		"title": title,
		"description": description,
		"target_amount": target_amount,
		"current_amount": current_amount,
		"is_completed": is_completed,
		"progress": get_progress(),
		"metadata": metadata.duplicate(true)
	}

## Фабрика создания сбалансированной задачи под количество игроков (1-4) и номер карты (1-9).
static func create_default_task(type: TaskType, player_count: int = 1, difficulty_tier: int = 1, suffix: String = "") -> CheckpointTask:
	var clamped_players := clampi(player_count, 1, 4)
	var clamped_tier := clampi(difficulty_tier, 1, 9)
	var task := CheckpointTask.new()
	task.task_type = type
	var id_suffix := ("_" + suffix) if not suffix.is_empty() else ""

	match type:
		TaskType.WAVE_DEFENSE:
			var waves := 1 + mini(2, int((clamped_tier + 1) / 3))
			var enemies_per_wave := 4 + clamped_players * 2 + clamped_tier
			task.task_id = "wave_defense" + id_suffix
			task.title = "Оборона точки"
			task.description = "Отбить %d волн(ы) мутантов" % waves
			task.target_amount = waves
			task.metadata = {
				"waves_total": waves,
				"enemies_per_wave": enemies_per_wave,
				"current_wave": 0
			}
		TaskType.CLEANUP:
			var trash_target := 4 + clamped_players * 2 + int(clamped_tier / 2)
			task.task_id = "cleanup" + id_suffix
			task.title = "Зачистка территории"
			task.description = "Убрать мусор и загрязнения (%d ед.)" % trash_target
			task.target_amount = trash_target
		TaskType.PUZZLE:
			var steps := 1 if clamped_tier < 4 else 2
			task.task_id = "puzzle" + id_suffix
			task.title = "Восстановление узла"
			task.description = "Решить техническую головоломку (щиток / вентили / код)"
			task.target_amount = steps
		TaskType.DECONTAMINATION:
			var cycles := 2 + int(clamped_tier / 3)
			task.task_id = "decontamination" + id_suffix
			task.title = "Дезактивация очага"
			task.description = "Нейтрализовать радиационный фон реагентом (%d этапа)" % cycles
			task.target_amount = cycles
		TaskType.REPAIR:
			var repair_steps := 2 + int(clamped_players / 2)
			task.task_id = "repair" + id_suffix
			task.title = "Ремонт оборудования"
			task.description = "Починить генератор / насос или укрепить периметр"
			task.target_amount = repair_steps
		TaskType.DELIVERY:
			var canisters := 2 + clamped_players
			task.task_id = "delivery" + id_suffix
			task.title = "Сбор спецгруза"
			task.description = "Доставить %d свинцовых капсул / канистр к точке" % canisters
			task.target_amount = canisters

	return task
