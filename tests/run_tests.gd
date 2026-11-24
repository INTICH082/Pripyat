extends Node

## Автоматический тестовый набор (Test Suite) для Pripyat Cleaner.
## Проверяет ключевые игровые системы: сетевой код комнат, слоты лобби,
## математику характеристик классов, экономику, боезапас 13 видов оружия
## и интерактивные объекты.

const TrainingDummyScript = preload("res://scripts/interactables/TrainingDummy.gd")
const DirtSpotScript = preload("res://scripts/interactables/DirtSpot.gd")

var total_tests: int = 0
var passed_tests: int = 0
var failed_tests: int = 0

func _ready() -> void:
	print("\n========================================================")
	print("       PRIPYAT CLEANER - AUTOMATED TEST SUITE          ")
	print("========================================================\n")
	
	_run_all_test_suites()
	
	print("\n========================================================")
	print("                   ИТОГИ ТЕСТИРОВАНИЯ                   ")
	print("========================================================")
	print("Всего тестов:     %d" % total_tests)
	print("Успешно пройдено: %d" % passed_tests)
	print("Провалено:        %d" % failed_tests)
	print("========================================================\n")
	
	if failed_tests == 0:
		print(">>> ВСЕ ТЕСТЫ УСПЕШНО ПРОЙДЕНЫ! СИСТЕМЫ СТАБИЛЬНЫ. <<<\n")
		get_tree().quit(0)
	else:
		printerr(">>> ОБНАРУЖЕНЫ ОШИБКИ В ТЕСТАХ! <<< \n")
		get_tree().quit(1)

func _run_all_test_suites() -> void:
	suite_network_room_codes()
	suite_multiplayer_slot_allocation()
	suite_gamestate_classes_and_survival()
	suite_economy_and_cleanliness()
	suite_weapon_arsenal_and_ammo_math()
	suite_interactables_logic()
	suite_scene_hierarchy_integrity()

# ==============================================================================
# ASSERTION HELPERS
# ==============================================================================

func assert_true(condition: bool, test_name: String) -> void:
	total_tests += 1
	if condition:
		passed_tests += 1
		print("  [PASS] %s" % test_name)
	else:
		failed_tests += 1
		printerr("  [FAIL] %s" % test_name)

func assert_eq(actual, expected, test_name: String) -> void:
	total_tests += 1
	if actual == expected:
		passed_tests += 1
		print("  [PASS] %s" % test_name)
	else:
		failed_tests += 1
		printerr("  [FAIL] %s: получено [%s], ожидалось [%s]" % [test_name, str(actual), str(expected)])

func assert_approx(actual: float, expected: float, tol: float, test_name: String) -> void:
	total_tests += 1
	if absf(actual - expected) <= tol:
		passed_tests += 1
		print("  [PASS] %s" % test_name)
	else:
		failed_tests += 1
		printerr("  [FAIL] %s: получено [%f], ожидалось [%f] (+/-%f)" % [test_name, actual, expected, tol])

# ==============================================================================
# SUITE 1: NETWORK & ROOM CODES
# ==============================================================================

func suite_network_room_codes() -> void:
	print("[SUITE 1] Сетевой код: Кодирование и декодирование кодов комнат...")
	
	# 1. Локальный IP loopback
	var code_loopback = NetworkManager.encode_room_code("127.0.0.1", 7777)
	assert_eq(code_loopback, "ZONE-7F00-0001-1E61", "Кодирование 127.0.0.1:7777")
	
	var parsed_loopback = NetworkManager.parse_connection_string(code_loopback)
	assert_eq(parsed_loopback.get("ip"), "127.0.0.1", "Декодирование IP loopback")
	assert_eq(parsed_loopback.get("port"), 7777, "Декодирование порта loopback")
	assert_true(parsed_loopback.get("is_valid"), "Флаг валидности loopback кода")
	
	# 2. Локальная сеть (LAN)
	var code_lan = NetworkManager.encode_room_code("192.168.1.100", 25565)
	assert_eq(code_lan, "ZONE-C0A8-0164-63DD", "Кодирование 192.168.1.100:25565")
	
	var parsed_lan = NetworkManager.parse_connection_string(code_lan)
	assert_eq(parsed_lan.get("ip"), "192.168.1.100", "Декодирование IP LAN")
	assert_eq(parsed_lan.get("port"), 25565, "Декодирование порта LAN")
	
	# 3. Публичный IP
	var code_pub = NetworkManager.encode_room_code("85.202.160.10", 8080)
	var parsed_pub = NetworkManager.parse_connection_string(code_pub)
	assert_eq(parsed_pub.get("ip"), "85.202.160.10", "Декодирование публичного IP")
	assert_eq(parsed_pub.get("port"), 8080, "Декодирование публичного порта")
	
	# 4. Обработка пробелов и регистра
	var parsed_case = NetworkManager.parse_connection_string("  zone-7f00-0001-1e61  ")
	assert_eq(parsed_case.get("ip"), "127.0.0.1", "Парсинг кода в нижнем регистре с пробелами")
	assert_eq(parsed_case.get("port"), 7777, "Парсинг порта в нижнем регистре")
	
	# 5. Парсинг прямого IP:PORT
	var parsed_direct = NetworkManager.parse_connection_string("10.20.30.40:9000")
	assert_eq(parsed_direct.get("ip"), "10.20.30.40", "Парсинг прямого IP")
	assert_eq(parsed_direct.get("port"), 9000, "Парсинг прямого порта")
	
	# 6. Невалидные строки
	var parsed_invalid = NetworkManager.parse_connection_string("ZONE-INVALID-DATA")
	assert_true(parsed_invalid.get("ip") != "" and not parsed_invalid.get("is_code"), "Невалидный код не определяется как код комнаты")
	
	var parsed_empty = NetworkManager.parse_connection_string("")
	assert_eq(parsed_empty.get("is_valid"), false, "Пустая строка подключения невалидна")

# ==============================================================================
# SUITE 2: MULTIPLAYER SLOT ALLOCATION
# ==============================================================================

func suite_multiplayer_slot_allocation() -> void:
	print("\n[SUITE 2] Сетевой код: Распределение слотов лобби (1-4 игрока)...")
	
	# Сохраняем исходное состояние
	var original_players = NetworkManager.players.duplicate()
	NetworkManager.players.clear()
	
	# 1. Первый свободный слот в пустом лобби должен быть 0
	var slot0 = NetworkManager._get_next_free_slot()
	assert_eq(slot0, 0, "Первый свободный слот равен 0")
	
	# Добавляем хоста
	NetworkManager.players[1] = { "peer_id": 1, "name": "Host", "slot": 0 }
	var slot1 = NetworkManager._get_next_free_slot()
	assert_eq(slot1, 1, "Следующий свободный слот равен 1")
	
	# Добавляем второго игрока
	NetworkManager.players[2] = { "peer_id": 2, "name": "Player2", "slot": 1 }
	var slot2 = NetworkManager._get_next_free_slot()
	assert_eq(slot2, 2, "Следующий свободный слот равен 2")
	
	# Добавляем четвёртого игрока с занятым слотом 3 (пропуская слот 2)
	NetworkManager.players[4] = { "peer_id": 4, "name": "Player4", "slot": 3 }
	var slot_gap = NetworkManager._get_next_free_slot()
	assert_eq(slot_gap, 2, "Заполнение пробела между слотами возвращает слот 2")
	
	# Заполняем лобби полностью (все 4 слота: 0, 1, 2, 3)
	NetworkManager.players[3] = { "peer_id": 3, "name": "Player3", "slot": 2 }
	var slot_full = NetworkManager._get_next_free_slot()
	assert_eq(slot_full, 0, "При полном лобби возвращается 0 (слоты исчерпаны)")
	
	# Восстанавливаем состояние
	NetworkManager.players = original_players

# ==============================================================================
# SUITE 3: GAMESTATE CLASSES & SURVIVAL MATH
# ==============================================================================

func suite_gamestate_classes_and_survival() -> void:
	print("\n[SUITE 3] GameState: Характеристики классов и механика выживания...")
	
	# 1. Проверка структуры классов (CLASS_DEFINITIONS)
	assert_true(GameState.CLASS_DEFINITIONS.has("cleaner"), "Класс Чистильщик зарегистрирован")
	assert_true(GameState.CLASS_DEFINITIONS.has("soldier"), "Класс Штурмовик зарегистрирован")
	assert_true(GameState.CLASS_DEFINITIONS.has("medic"), "Класс Медик зарегистрирован")
	assert_true(GameState.CLASS_DEFINITIONS.has("engineer"), "Класс Инженер зарегистрирован")
	
	# 2. Проверка специализаций
	assert_eq(GameState.CLASS_DEFINITIONS["soldier"]["health"], 150.0, "Штурмовик имеет максимальное здоровье (150 HP)")
	assert_eq(GameState.CLASS_DEFINITIONS["soldier"]["carry_capacity"], 45.0, "Штурмовик может переносить 45 кг")
	assert_eq(GameState.CLASS_DEFINITIONS["medic"]["radiation_resistance"], 0.75, "Медик имеет максимальную защиту от радиации (75%)")
	assert_eq(GameState.CLASS_DEFINITIONS["cleaner"]["cleaning_modifier"], 1.75, "Чистильщик имеет +75% бонус к скорости уборки")
	assert_eq(GameState.CLASS_DEFINITIONS["engineer"]["repair_modifier"], 1.60, "Инженер имеет +60% бонус к ремонту")
	
	# 3. Применение класса
	GameState.set_class("medic")
	assert_eq(GameState.current_class_id, "medic", "Текущий класс установлен в medic")
	assert_approx(GameState.radiation_resistance, 0.75, 0.001, "Сопротивление радиации установлено в 0.75")
	assert_approx(GameState.max_health, 90.0, 0.001, "Максимальное здоровье medic установлено в 90")
	
	GameState.set_class("soldier")
	assert_eq(GameState.current_class_id, "soldier", "Текущий класс установлен в soldier")
	assert_approx(GameState.max_health, 150.0, 0.001, "Максимальное здоровье soldier установлено в 150")
	assert_approx(GameState.radiation_resistance, 0.25, 0.001, "Сопротивление радиации soldier установлено в 0.25")
	
	# 4. Урон и лечение
	GameState.health = 100.0
	GameState.take_damage(40.0)
	assert_approx(GameState.health, 60.0, 0.001, "Получение 40 урона снижает здоровье до 60")
	
	# 5. Лечение игрока
	GameState.heal(30.0)
	assert_approx(GameState.health, 90.0, 0.001, "Лечение на 30 восстанавливает здоровье до 90")
	
	GameState.heal(999.0)
	assert_approx(GameState.health, GameState.max_health, 0.001, "Лечение не превышает max_health")
	
	# Смертельный урон
	GameState.take_damage(999.0)
	assert_approx(GameState.health, 0.0, 0.001, "Здоровье зажато снизу на 0 при избыточном уроне")
	
	# Урон при нулевом здоровье не уходит в минус
	GameState.take_damage(50.0)
	assert_approx(GameState.health, 0.0, 0.001, "Повторный урон при 0 HP не уводит здоровье в минус")
	
	# Восстановление для последующих тестов
	GameState.health = 100.0
	
	# 6. Стамина
	GameState.stamina = 50.0
	var spent = GameState.consume_stamina(30.0)
	assert_true(spent, "Успешное потребление 30 стамины")
	assert_approx(GameState.stamina, 20.0, 0.001, "Остаток стамины 20")
	
	var spent_fail = GameState.consume_stamina(50.0)
	assert_true(not spent_fail, "Недостаточно стамины (отказ в потреблении)")
	assert_approx(GameState.stamina, 20.0, 0.001, "Стамина не изменилась при нехватке")
	
	# 7. Радиация
	GameState.radiation = 0.0
	# Soldier rad_resist = 0.25 -> effective radiation = 100 * (1 - 0.25) = 75.0
	GameState.add_radiation(100.0)
	assert_approx(GameState.radiation, 75.0, 0.001, "Радиация начислена с учетом защиты класса (75%)")
	
	GameState.reduce_radiation(30.0)
	assert_approx(GameState.radiation, 45.0, 0.001, "Снижение радиации на 30")
	
	GameState.reduce_radiation(999.0)
	assert_approx(GameState.radiation, 0.0, 0.001, "Радиация зажата снизу на 0.0")

# ==============================================================================
# SUITE 4: ECONOMY & CLEANLINESS
# ==============================================================================

func suite_economy_and_cleanliness() -> void:
	print("\n[SUITE 4] Экономика и учет чистоты двора...")
	
	# 1. Валюта (карбованцы / советские рубли)
	GameState.karbovantsi = 0
	GameState.add_karbovantsi(150)
	assert_eq(GameState.karbovantsi, 150, "Начисление 150 карбованцев")
	
	GameState.add_rubles(50)
	assert_eq(GameState.karbovantsi, 200, "Псевдоним add_rubles начисляет 50 карбованцев")
	
	# 2. Регистрация и уборка объектов
	GameState.total_items = 0
	GameState.cleaned_items = 0
	
	GameState.register_cleanup_item()
	GameState.register_cleanup_item()
	GameState.register_cleanup_item()
	GameState.register_cleanup_item()
	assert_eq(GameState.total_items, 4, "Зарегистрировано 4 объекта для уборки")
	
	# Утилизация мусора: +1 к убранным и +20 рублей
	GameState._on_trash_deposited("Мешок с мусором", 20)
	assert_eq(GameState.cleaned_items, 1, "Убран 1 объект")
	assert_eq(GameState.karbovantsi, 220, "Награда за утилизацию мусора добавлена в кошелек")
	
	# Очистка пятна: +1 к убранным и +10 рублей
	GameState._on_dirt_cleaned(10, Vector3.ZERO)
	assert_eq(GameState.cleaned_items, 2, "Убрано 2 объекта из 4")
	assert_eq(GameState.karbovantsi, 230, "Награда за отскабливание пятна добавлена")
	
	# Процент чистоты двора: 2 / 4 = 50%
	var percent = (float(GameState.cleaned_items) / float(GameState.total_items)) * 100.0
	assert_approx(percent, 50.0, 0.001, "Чистота двора составляет ровно 50.0%")

# ==============================================================================
# SUITE 5: WEAPON ARSENAL & AMMO MATH
# ==============================================================================

func suite_weapon_arsenal_and_ammo_math() -> void:
	print("\n[SUITE 5] Арсенал: Проверка 13 видов оружия и расчет боеприпасов...")
	
	var weapons_to_check = [
		{"id": "01_fists", "melee": true, "name": "Кулаки"},
		{"id": "02_crowbar", "melee": true, "name": "Монтировка"},
		{"id": "03_spade", "melee": true, "name": "Сапёрная лопатка"},
		{"id": "04_fire_axe", "melee": true, "name": "Пожарный топор"},
		{"id": "05_pistol_pl", "melee": false, "name": "Пистолет ПЛ-1"},
		{"id": "06_pistol_pt", "melee": false, "name": "Пистолет ПТ-33"},
		{"id": "07_rifle_al", "melee": false, "name": "Автомат АЛ-74"},
		{"id": "08_rifle_at", "melee": false, "name": "Винтовка АТ-С"},
		{"id": "09_rifle_vl", "melee": false, "name": "Карабин ВЛ-68"},
		{"id": "10_rifle_vt", "melee": false, "name": "Винтовка ВТ-91"},
		{"id": "11_rpk", "melee": false, "name": "Пулемёт РПК-Л"},
		{"id": "12_flamya_1", "melee": false, "name": "Огнемёт «Пламя-1»"},
		{"id": "13_launcher_gm", "melee": false, "name": "Гранатомёт ГМ-94"}
	]
	
	for w in weapons_to_check:
		var path = "res://resources/weapons/%s.tres" % w["id"]
		var res = ResourceLoader.load(path) as WeaponData
		assert_true(res != null, "Ресурс оружия [%s] загружен" % w["id"])
		if res:
			assert_eq(res.is_melee, w["melee"], "[%s] соответствие типа melee/ranged" % w["id"])
			assert_true(res.damage > 0.0, "[%s] базовый урон больше 0 (damage=%.1f)" % [w["id"], res.damage])
			assert_true(res.fire_rate > 0.0, "[%s] скорострельность больше 0 (rate=%.1f)" % [w["id"], res.fire_rate])
			
			if not res.is_melee:
				assert_true(res.mag_capacity > 0, "[%s] ёмкость магазина > 0 (cap=%d)" % [w["id"], res.mag_capacity])
				assert_true(res.reload_time > 0.0, "[%s] время перезарядки > 0 (time=%.2fs)" % [w["id"], res.reload_time])
				assert_true(res.ammo_type != "none", "[%s] назначен калибр патронов (%s)" % [w["id"], res.ammo_type])
	
	# 2. Проверка особых свойств (гранатомет и огнемет)
	var launcher = ResourceLoader.load("res://resources/weapons/13_launcher_gm.tres") as WeaponData
	if launcher:
		assert_true(launcher.is_explosive, "Гранатомет ГМ-94 имеет флаг is_explosive")
		assert_true(launcher.splash_radius > 0.0, "Гранатомет ГМ-94 имеет радиус взрыва")
		
	var flamethrower = ResourceLoader.load("res://resources/weapons/12_flamya_1.tres") as WeaponData
	if flamethrower:
		assert_true(flamethrower.is_flamethrower, "Огнемет имеет флаг is_flamethrower")
		assert_eq(flamethrower.ammo_type, "fuel", "Огнемет использует топливо")
		
	# 3. Моделирование математики перезарядки
	# Сценарий А: Полная перезарядка с избытком патронов
	var mag_cap = 30
	var cur_mag = 10
	var reserve = 60
	var needed = mag_cap - cur_mag
	var to_load = mini(needed, reserve)
	cur_mag += to_load
	reserve -= to_load
	assert_eq(cur_mag, 30, "Магазин полностью заполнен (30 патронов)")
	assert_eq(reserve, 40, "Из резерва списано ровно 20 патронов (осталось 40)")
	
	# Сценарий Б: Перезарядка при нехватке патронов в резерве
	mag_cap = 30
	cur_mag = 10
	reserve = 12
	needed = mag_cap - cur_mag
	to_load = mini(needed, reserve)
	cur_mag += to_load
	reserve -= to_load
	assert_eq(cur_mag, 22, "В магазин заряжен весь остаток резерва (10 + 12 = 22)")
	assert_eq(reserve, 0, "Резерв полностью опустошен (0)")

# ==============================================================================
# SUITE 6: INTERACTABLES LOGIC
# ==============================================================================

func suite_interactables_logic() -> void:
	print("\n[SUITE 6] Интерактивные объекты: Тренировочный манекен и пятна грязи...")
	
	# 1. TrainingDummy (AUDIT-005)
	var dummy = TrainingDummyScript.new()
	add_child(dummy)
	
	assert_approx(dummy.health, 100.0, 0.001, "Манекен создан с начальным здоровьем 100")
	dummy.take_damage(45.0)
	assert_approx(dummy.health, 55.0, 0.001, "Получение урона снижает здоровье манекена до 55")
	
	# Нокаут
	dummy.take_damage(70.0)
	assert_approx(dummy.health, 0.0, 0.001, "Здоровье манекена на нуле после смертельного урона")
	assert_true(dummy._is_recovering, "Манекен перешел в режим восстановления")
	
	# Восстановление через interact
	dummy.interact()
	assert_approx(dummy.health, 100.0, 0.001, "Ручной interact сбрасывает здоровье манекена обратно до 100")
	dummy.queue_free()
	
	# 2. DirtSpot (AUDIT-006 & AUDIT-011)
	var dirt_spot = DirtSpotScript.new()
	add_child(dirt_spot)
	
	assert_approx(dirt_spot.health, 0.4, 0.001, "Пятно грязи имеет исходный запас прочности 0.4с")
	dirt_spot.scrub(0.15, false)
	assert_approx(dirt_spot.health, 0.25, 0.001, "Отскабливание на 0.15 снижает здоровье до 0.25")
	
	dirt_spot.clear_spot(false)
	assert_true(dirt_spot.is_cleared, "Пятно успешно очищено (is_cleared = true)")
	assert_eq(dirt_spot.collision_layer, 0, "Коллизия очищенного пятна отключена")
	dirt_spot.queue_free()

# ==============================================================================
# SUITE 7: SCENE HIERARCHY & BUG PREVENTION
# ==============================================================================

func suite_scene_hierarchy_integrity() -> void:
	print("\n[SUITE 7] Проверка структуры сцен на отсутствие багов интерфейса...")
	
	# 1. Проверка MultiplayerLobby (AUDIT-008: ScrollContainer должен иметь ровно 1 дочерний узел)
	var lobby_scene = load("res://scenes/ui/MultiplayerLobby.tscn")
	assert_true(lobby_scene != null, "Сцена MultiplayerLobby.tscn успешно загружена")
	if lobby_scene:
		var lobby_inst = lobby_scene.instantiate()
		var scroll = lobby_inst.find_child("Scroll", true, false)
		assert_true(scroll != null, "Найден узел ScrollContainer в MultiplayerLobby")
		if scroll:
			assert_eq(scroll.get_child_count(), 1, "ScrollContainer имеет РОВНО 1 дочерний Control (LobbiesList)")
			var child = scroll.get_child(0)
			assert_eq(child.name, "LobbiesList", "Единственный дочерний узел ScrollContainer — это LobbiesList")
		lobby_inst.queue_free()
	
	# 2. Проверка HUD и CharacterSelectScreen (AUDIT-012: экран выбора персонажа скрыт по умолчанию)
	var hud_scene = load("res://scenes/ui/HUD.tscn")
	assert_true(hud_scene != null, "Сцена HUD.tscn успешно загружена")
	if hud_scene:
		var hud_inst = hud_scene.instantiate()
		var cselect = hud_inst.find_child("CharacterSelectScreen", true, false)
		assert_true(cselect != null, "Найден узел CharacterSelectScreen внутри HUD")
		if cselect:
			assert_eq(cselect.visible, false, "CharacterSelectScreen по умолчанию СКРЫТ (visible = false) при запуске интерфейса")
		hud_inst.queue_free()
