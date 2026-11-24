extends Node

## Состояние игры (GameState)
## Главное ядро проекта. Управляет:
## 1. Характеристиками выживания (Здоровье, Радиация, Выносливость).
## 2. Классами специалистов ликвидации (Чистильщик, Штурмовик, Медик, Инженер).
## 3. Реестром биоугроз и противников Зоны (Раздел 2 GDD).
## 4. Реестром районов Припяти и торговых хабов (Раздел 5 GDD).
## 5. Экономикой (Карбованцы) и прогрессом чистоты.

# ==============================================================================
# РАЗДЕЛ: КЛАССЫ СПЕЦИАЛИСТОВ (Раздел 9 GDD)
# ==============================================================================
const CLASS_DEFINITIONS: Dictionary = {
	"cleaner": {
		"id": "cleaner",
		"name": "Специалист / Чистильщик",
		"short_name": "Чистильщик",
		"role": "Универсал и виртуоз процесса очистки",
		"health": 100.0,
		"stamina": 140.0,
		"carry_capacity": 30.0,
		"radiation_resistance": 0.60,
		"cleaning_modifier": 1.75,
		"repair_modifier": 1.15,
		"body_model_path": "res://assets/models/field_specialists/cleaner.gltf",
		"fps_model_path": "res://assets/models/fps/cleaner_fps.glb",
		"perk": "+75% к скорости очистки, широкое сопло скребка"
	},
	"soldier": {
		"id": "soldier",
		"name": "Штурмовик",
		"short_name": "Штурмовик",
		"role": "Тяжелая охрана группы, мастер огневого боя",
		"health": 150.0,
		"stamina": 100.0,
		"carry_capacity": 45.0,
		"radiation_resistance": 0.25,
		"cleaning_modifier": 0.80,
		"repair_modifier": 1.00,
		"body_model_path": "res://assets/models/field_specialists/soldier.gltf",
		"fps_model_path": "res://assets/models/fps/soldier_fps.glb",
		"perk": "-30% отдачи, максимальное здоровье (150 HP)"
	},
	"medic": {
		"id": "medic",
		"name": "Медик РХБЗ",
		"short_name": "Медик",
		"role": "Эксперт радиационной безопасности и выживания",
		"health": 90.0,
		"stamina": 115.0,
		"carry_capacity": 25.0,
		"radiation_resistance": 0.75,
		"cleaning_modifier": 1.10,
		"repair_modifier": 0.85,
		"body_model_path": "res://assets/models/field_specialists/medic.gltf",
		"fps_model_path": "res://assets/models/fps/medic_fps.glb",
		"perk": "75% сопротивления радиации, эффективное лечение"
	},
	"engineer": {
		"id": "engineer",
		"name": "Инженер-Механик",
		"short_name": "Инженер",
		"role": "Мастер ремонта архитектуры и оживления техники",
		"health": 110.0,
		"stamina": 105.0,
		"carry_capacity": 35.0,
		"radiation_resistance": 0.40,
		"cleaning_modifier": 1.00,
		"repair_modifier": 1.60,
		"body_model_path": "res://assets/models/field_specialists/engineer.gltf",
		"fps_model_path": "res://assets/models/fps/engineer_fps.glb",
		"perk": "+60% к скорости ремонта, +25% доход от металлолома"
	}
}

# ==============================================================================
# РАЗДЕЛ: СУЩНОСТИ И ПРОТИВНИКИ (Бестиарий Чернобыля, Раздел 2 GDD)
# ==============================================================================
const ENEMY_REGISTRY: Dictionary = {
	"rat": {
		"id": "rat",
		"name": "Радиоактивная крыса",
		"category": "Грызун",
		"health": 20.0,
		"damage": 6.0,
		"speed": 3.5,
		"habitat": "Мусорные кучи, подвалы",
		"harm": "Кусает за руки при сборе мусора; растаскивает собранный хлам обратно.",
		"reward_karbovantsi": 3,
		"attracts_to_noise": false,
		"damages_structures": false,
		"is_boss": false
	},
	"crow": {
		"id": "crow",
		"name": "Чернобыльский ворон",
		"category": "Птица",
		"health": 15.0,
		"damage": 8.0,
		"speed": 9.0,
		"habitat": "Фонари, крыши пятиэтажек",
		"harm": "Пикирует на игрока при переноске открытого мусора, роняет ящики.",
		"reward_karbovantsi": 4,
		"attracts_to_noise": false,
		"damages_structures": false,
		"is_boss": false
	},
	"blind_dog": {
		"id": "blind_dog",
		"name": "Слепой пес (Одичавший)",
		"category": "Мутант",
		"health": 65.0,
		"damage": 18.0,
		"speed": 6.5,
		"habitat": "Дворы, проспекты, скверы",
		"harm": "Нападают стаями по 3-5 особей; сбегаются на рев моторов и мойки.",
		"reward_karbovantsi": 15,
		"attracts_to_noise": true,
		"damages_structures": false,
		"is_boss": false
	},
	"wolf": {
		"id": "wolf",
		"name": "Чернобыльский волк",
		"category": "Хищник",
		"health": 130.0,
		"damage": 32.0,
		"speed": 7.8,
		"habitat": "Лес у села Копачи, ЗГРЛС «Дуга»",
		"harm": "Бесшумно атакует со спины одиночных рабочих; накладывает кровотечение.",
		"reward_karbovantsi": 35,
		"attracts_to_noise": false,
		"damages_structures": false,
		"is_boss": false
	},
	"boar": {
		"id": "boar",
		"name": "Чернобыльский Секач (Вепрь)",
		"category": "Мутант",
		"health": 320.0,
		"damage": 45.0,
		"speed": 7.0,
		"habitat": "Сельские дворы, Городской парк",
		"harm": "С разбега сносит игрока, выбивает предметы из рук, ломает скамейки и урны.",
		"reward_karbovantsi": 75,
		"attracts_to_noise": true,
		"damages_structures": true,
		"is_boss": false
	},
	"stag": {
		"id": "stag",
		"name": "Облучённый Олень",
		"category": "Мутант",
		"health": 210.0,
		"damage": 38.0,
		"speed": 9.2,
		"habitat": "Окрестности Дуги, скверы, аллеи",
		"harm": "Разносит свежевысаженные клумбы и ломает деревянные заборы рогами.",
		"reward_karbovantsi": 60,
		"attracts_to_noise": false,
		"damages_structures": true,
		"is_boss": false
	},
	"ant": {
		"id": "ant",
		"name": "Рыжий Муравей-древоточец",
		"category": "Насекомое",
		"health": 140.0,
		"damage": 26.0,
		"speed": 5.5,
		"habitat": "Рыжий лес, село Копачи, склады",
		"harm": "Кислотой разъедает отремонтированные заборы; возводит земляные холмы-муравейники.",
		"reward_karbovantsi": 40,
		"attracts_to_noise": false,
		"damages_structures": true,
		"is_boss": false
	},
	"bloodsucker": {
		"id": "bloodsucker",
		"name": "Полесский Кровосос (Трясинный упырь)",
		"category": "Мутант",
		"health": 260.0,
		"damage": 42.0,
		"speed": 8.5,
		"habitat": "Подвалы хрущевок, бассейн «Лазурный», катакомбы «Юпитера»",
		"harm": "Частичная мимикрия в темноте. Нападает из вентиляции, высасывает кровь и лечится.",
		"reward_karbovantsi": 95,
		"attracts_to_noise": false,
		"damages_structures": false,
		"is_boss": false
	},
	"controller": {
		"id": "controller",
		"name": "Пси-Мутант «Резонатор»",
		"category": "Аномальный",
		"health": 420.0,
		"damage": 35.0,
		"speed": 3.0,
		"habitat": "Бункер ЗГРЛС «Дуга», цеха ЧАЭС",
		"harm": "Генерирует инфразвуковое поле: сбивает прицел, заставляет ронять инструмент, подчиняет собак.",
		"reward_karbovantsi": 220,
		"attracts_to_noise": false,
		"damages_structures": false,
		"is_boss": false
	},
	"bear": {
		"id": "bear",
		"name": "Медведь-шатун (Суперхищник)",
		"category": "Суперхищник / Босс",
		"health": 850.0,
		"damage": 75.0,
		"speed": 6.8,
		"habitat": "Глухие леса у села, промзона ЧАЭС",
		"harm": "Босс локации. Переворачивает ручные тачки, ломает кузова грузовиков.",
		"reward_karbovantsi": 280,
		"attracts_to_noise": false,
		"damages_structures": true,
		"is_boss": true
	},
	"feral": {
		"id": "feral",
		"name": "«Одичавший» (Мародер)",
		"category": "Человек",
		"health": 110.0,
		"damage": 25.0,
		"speed": 4.8,
		"habitat": "Квартиры, темные цеха «Юпитера»",
		"harm": "Засели в зданиях; швыряют кирпичи, стреляют из самопалов, крадут металлолом.",
		"reward_karbovantsi": 50,
		"attracts_to_noise": false,
		"damages_structures": false,
		"is_boss": false
	}
}

# ==============================================================================
# РАЗДЕЛ: ЛОКАЦИИ И РАЙОНЫ (Раздел 5 GDD)
# ==============================================================================
const LOCATION_REGISTRY: Dictionary = {
	"kopachi": {
		"id": "kopachi",
		"index": 1,
		"name": "Заброшенное село Копачи (Стартовый пригород)",
		"landscape": "Песчаные дороги, деревянные избы, колодцы, яблоневые сады, коровники.",
		"tasks": [
			"Уборка сельхозотходов",
			"Спил гнилых заборов",
			"Расчистка дороги к городу"
		],
		"threats": ["Волки", "Кабаны", "Крысы"],
		"radiation_level": "Низкий",
		"is_unlocked": true
	},
	"microdistrict_1": {
		"id": "microdistrict_1",
		"index": 2,
		"name": "1-й Микрорайон Припяти",
		"landscape": "Дворы-колодцы, пятиэтажные хрущевки, детские площадки, подъезды.",
		"tasks": [
			"Уборка бытового мусора",
			"Соскабливание мха с асфальта",
			"Остекление первых этажей"
		],
		"threats": ["Слепые псы", "Радиоактивные крысы", "Чернобыльские вороны"],
		"radiation_level": "Низкий / Средний",
		"is_unlocked": true
	},
	"lenin_prospect": {
		"id": "lenin_prospect",
		"index": 3,
		"name": "Проспект Ленина и Центральная площадь",
		"landscape": "Широкие проспекты, ДК «Энергетик», Гостиница «Полесье», брошенные автобусы.",
		"tasks": [
			"Расчистка проезжей части",
			"Восстановление витражей ДК",
			"Запуск уличных фонарей"
		],
		"threats": ["Слепые псы", "Одичавшие мародеры"],
		"radiation_level": "Средний",
		"is_unlocked": false
	},
	"amusement_park": {
		"id": "amusement_park",
		"index": 4,
		"name": "Городской парк аттракционов",
		"landscape": "Колесо обозрения, автодром, густые дикие заросли тополей.",
		"tasks": [
			"Покос кустарников и бурьяна",
			"Спил аварийных тополей",
			"Очистка ржавых каруселей",
			"Подача питания на колесо обозрения"
		],
		"threats": ["Чернобыльский Секач", "Слепые псы"],
		"radiation_level": "Средний / Высокий",
		"is_unlocked": false
	},
	"azure_pool": {
		"id": "azure_pool",
		"index": 5,
		"name": "Бассейн «Лазурный»",
		"landscape": "Закрытый спорткомплекс, смотровые вышки, чаша бассейна, спортзал.",
		"tasks": [
			"Откачка радиоактивной жижи со дна чаши",
			"Отмывка кафельной плитки мойкой высокого давления",
			"Заделка проломов крыши"
		],
		"threats": ["Полесский Кровосос", "Радиоактивные крысы"],
		"radiation_level": "Средний",
		"is_unlocked": false
	},
	"duga_radar": {
		"id": "duga_radar",
		"index": 6,
		"name": "ЗГРЛС «Дуга» (Объект «Чернобыль-2»)",
		"landscape": "Гигантская 150-метровая стена антенн, плац, казармы, бункер связи с ЭВМ.",
		"tasks": [
			"Демонтаж аварийных кабелей",
			"Сбор сотен тонн металлолома",
			"Зачистка от стай волков и оленей"
		],
		"threats": ["Чернобыльские волки", "Облучённый Олень", "Пси-Мутант «Резонатор»"],
		"radiation_level": "Высокий",
		"is_unlocked": false
	},
	"jupiter_factory": {
		"id": "jupiter_factory",
		"index": 7,
		"name": "Завод «Юпитер»",
		"landscape": "Тяжелые производственные цеха, мостовые краны, административный корпус.",
		"tasks": [
			"Разбор завалов рухнувших перекрытий",
			"Распил станков болгаркой на металлолом",
			"Зачистка от вооруженных мародеров"
		],
		"threats": ["«Одичавшие» мародеры", "Полесский Кровосос"],
		"radiation_level": "Высокий",
		"is_unlocked": false
	},
	"hospital_126": {
		"id": "hospital_126",
		"index": 8,
		"name": "Медсанчасть МСЧ-126 (Больница)",
		"landscape": "Больничные палаты, хирургические блоки, подвал с одеждой пожарных.",
		"tasks": [
			"Дезактивация опасных палат",
			"Утилизация зараженной медицинской тары в свинцовые контейнеры"
		],
		"threats": ["Полесский Кровосос", "Радиоактивные крысы"],
		"radiation_level": "Очень высокий (>50 Р/ч)",
		"is_unlocked": false
	},
	"reactor_block_4": {
		"id": "reactor_block_4",
		"index": 9,
		"name": "ЧАЭС: 4-й Энергоблок и Саркофаг («Укрытие») — [Финал]",
		"landscape": "Разрушенный реакторный зал, труба ВТ-2, графитовые завалы, смертельный фон.",
		"tasks": [
			"Работа в свинцовых костюмах и на БРДМ",
			"Сбор обломков графита в капсулы",
			"Дезактивация бетона",
			"Укрепление стен саркофага"
		],
		"threats": ["Медведь-шатун (Босс)", "Пси-Мутант «Резонатор»"],
		"radiation_level": "Смертельный (>100 Р/ч)",
		"is_unlocked": false
	}
}

# ==============================================================================
# РАЗДЕЛ: ТОРГОВЫЕ ТОЧКИ И ХАБЫ (Раздел 5 GDD)
# ==============================================================================
const HUB_REGISTRY: Dictionary = {
	"hq_liquidation": {
		"id": "hq_liquidation",
		"name": "Штаб Ликвидации",
		"services": ["Доска заказов", "Карта города", "Бесплатная койка для сна", "Ящик хранения"]
	},
	"hardware_store": {
		"id": "hardware_store",
		"name": "Магазин «Хозтовары»",
		"services": ["Продажа щеток", "Лопаты", "Мойки", "Мешки", "Сменные фильтры", "Стройматериалы"]
	},
	"vehicle_base": {
		"id": "vehicle_base",
		"name": "Автобаза «Сельхозтехника»",
		"services": ["Покупка транспорта", "Ремонт", "Улучшение", "Заправка бензином"]
	},
	"scrap_metal": {
		"id": "scrap_metal",
		"name": "Пункт приёма «Вторчермет»",
		"services": ["Сдача черного и цветного металлолома по оптовым ценам"]
	},
	"military_trade": {
		"id": "military_trade",
		"name": "Склад ГО и Военторг",
		"services": ["Продажа оружия", "Боеприпасы", "Бронежилеты", "Гранаты"]
	},
	"medical_post": {
		"id": "medical_post",
		"name": "Медпункт РХБЗ",
		"services": ["Аптечки АИ-2", "Антирадар РД-1", "Радиопротекторы Б-190", "Костюмы ОЗК/Л-1"]
	}
}

# Текущее состояние игрока
var current_class_id: String = "cleaner"
var current_location_id: String = "microdistrict_1"

# Характеристики выживания
var health: float = 100.0
var max_health: float = 100.0

var radiation: float = 0.0
var max_radiation: float = 100.0
var radiation_resistance: float = 0.60

var stamina: float = 140.0
var max_stamina: float = 140.0
var stamina_regen_rate: float = 28.0
var stamina_drain_sprint: float = 18.0
var stamina_cost_jump: float = 12.0
var stamina_cost_punch: float = 15.0
var stamina_cooldown: float = 0.0

var cleaning_modifier: float = 1.75
var carry_capacity: float = 30.0

# Настройки управления и камеры
var mouse_sensitivity: float = 0.0025
var invert_y: bool = false
var camera_fov: float = 70.0

# Экономика (Карбованцы)
var _is_syncing_network: bool = false
var karbovantsi: int = 0:
	set(value):
		var delta = value - karbovantsi
		karbovantsi = max(0, value)
		EventBus.currency_changed.emit(karbovantsi, delta)
		if NetworkManager and NetworkManager.is_multiplayer_active() and NetworkManager.is_host and not _is_syncing_network:
			NetworkManager.sync_rubles_across_squad(karbovantsi, delta)

# Обратная совместимость для вызовов
var rubles: int:
	get: return karbovantsi
	set(value): karbovantsi = value

# Статистика чистоты
var total_items: int = 0
var cleaned_items: int = 0

func _ready() -> void:
	EventBus.trash_deposited.connect(_on_trash_deposited)
	EventBus.dirt_cleaned.connect(_on_dirt_cleaned)
	load_settings()
	set_class("cleaner")

func _process(delta: float) -> void:
	# Восстановление выносливости
	if stamina_cooldown > 0.0:
		stamina_cooldown -= delta
	elif stamina < max_stamina:
		var prev_stamina = stamina
		stamina = minf(stamina + stamina_regen_rate * delta, max_stamina)
		if int(prev_stamina) != int(stamina):
			EventBus.stamina_changed.emit(stamina, max_stamina, stamina - prev_stamina)
			
	# Урон от критической радиации (> 75%)
	if radiation > 75.0:
		take_damage(2.0 * delta)

# ==============================================================================
# МЕТОДЫ УПРАВЛЕНИЯ КЛАССАМИ И ХАРАКТЕРИСТИКАМИ
# ==============================================================================
func set_class(class_id: String) -> void:
	if not CLASS_DEFINITIONS.has(class_id):
		return
	current_class_id = class_id
	var def = CLASS_DEFINITIONS[class_id]
	
	max_health = def["health"]
	health = max_health
	
	max_stamina = def["stamina"]
	stamina = max_stamina
	
	radiation_resistance = def["radiation_resistance"]
	cleaning_modifier = def["cleaning_modifier"]
	carry_capacity = def["carry_capacity"]
	
	EventBus.character_class_changed.emit(class_id, def)
	EventBus.health_changed.emit(health, max_health, 0.0)
	EventBus.stamina_changed.emit(stamina, max_stamina, 0.0)
	EventBus.radiation_changed.emit(radiation, max_radiation, 0.0)

func take_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	var _prev_hp = health
	health = maxf(0.0, health - amount)
	EventBus.health_changed.emit(health, max_health, -amount)
	EventBus.player_damaged.emit(amount)

func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	var prev_hp = health
	health = minf(max_health, health + amount)
	EventBus.health_changed.emit(health, max_health, health - prev_hp)

func add_radiation(raw_amount: float) -> void:
	var effective_amount = raw_amount * (1.0 - radiation_resistance)
	if effective_amount <= 0.0:
		return
	var prev_rad = radiation
	radiation = minf(max_radiation, radiation + effective_amount)
	EventBus.radiation_changed.emit(radiation, max_radiation, radiation - prev_rad)

func reduce_radiation(amount: float) -> void:
	if amount <= 0.0:
		return
	var prev_rad = radiation
	radiation = maxf(0.0, radiation - amount)
	EventBus.radiation_changed.emit(radiation, max_radiation, radiation - prev_rad)

func consume_stamina(amount: float) -> bool:
	if stamina >= amount:
		stamina -= amount
		stamina_cooldown = 0.8
		EventBus.stamina_changed.emit(stamina, max_stamina, -amount)
		return true
	return false

func drain_stamina_continuous(amount_per_sec: float, delta: float) -> bool:
	var needed = amount_per_sec * delta
	if stamina > 0.0:
		stamina = maxf(0.0, stamina - needed)
		stamina_cooldown = 0.4
		EventBus.stamina_changed.emit(stamina, max_stamina, -needed)
		return true
	return false

func can_sprint() -> bool:
	return stamina > 5.0

# ==============================================================================
# МЕТОДЫ РАБОТЫ С СУЩНОСТЯМИ И ЛОКАЦИЯМИ
# ==============================================================================
func get_enemy(enemy_id: String) -> Dictionary:
	return ENEMY_REGISTRY.get(enemy_id, {})

func get_all_enemies() -> Array:
	return ENEMY_REGISTRY.values()

func get_location(location_id: String) -> Dictionary:
	return LOCATION_REGISTRY.get(location_id, {})

func get_all_locations() -> Array:
	return LOCATION_REGISTRY.values()

func get_hub(hub_id: String) -> Dictionary:
	return HUB_REGISTRY.get(hub_id, {})

func get_all_hubs() -> Array:
	return HUB_REGISTRY.values()

func switch_location(new_loc_id: String) -> void:
	if LOCATION_REGISTRY.has(new_loc_id):
		current_location_id = new_loc_id
		var loc_data = LOCATION_REGISTRY[new_loc_id]
		EventBus.location_changed.emit(new_loc_id, loc_data)

func defeat_enemy(enemy_id: String) -> void:
	var enemy = get_enemy(enemy_id)
	if not enemy.is_empty():
		var reward = enemy.get("reward_karbovantsi", 0)
		add_karbovantsi(reward)
		EventBus.enemy_defeated.emit(enemy_id, reward)

# ==============================================================================
# ЭКОНОМИКА И ПРОГРЕСС
# ==============================================================================
func register_cleanup_item() -> void:
	total_items += 1
	_emit_progress()

func add_karbovantsi(amount: int) -> void:
	karbovantsi += amount

func add_rubles(amount: int) -> void:
	add_karbovantsi(amount)

func _on_trash_deposited(_trash_name: String, reward_rubles: int) -> void:
	add_rubles(reward_rubles)
	cleaned_items += 1
	_emit_progress()

func _on_dirt_cleaned(reward_rubles: int, _world_pos: Vector3) -> void:
	if reward_rubles > 0:
		add_rubles(reward_rubles)
	cleaned_items += 1
	_emit_progress()

func _emit_progress() -> void:
	var percent: float = 0.0
	if total_items > 0:
		percent = clampf((float(cleaned_items) / float(total_items)) * 100.0, 0.0, 100.0)
	EventBus.cleanliness_updated.emit(cleaned_items, total_items, percent)
	if NetworkManager and NetworkManager.is_multiplayer_active() and NetworkManager.is_host and not _is_syncing_network:
		NetworkManager.sync_cleanliness_across_squad(cleaned_items, total_items, percent)

# ==============================================================================
# НАСТРОЙКИ
# ==============================================================================
func save_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("display", "camera_fov", camera_fov)
	cfg.save("user://pripyat_settings.cfg")

func load_settings() -> void:
	var cfg = ConfigFile.new()
	if cfg.load("user://pripyat_settings.cfg") == OK:
		mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
		invert_y = cfg.get_value("controls", "invert_y", invert_y)
		camera_fov = cfg.get_value("display", "camera_fov", camera_fov)
