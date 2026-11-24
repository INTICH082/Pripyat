extends Node

## Менеджер мультиплеера и сетевого лобби (NetworkManager)
## Поддерживает:
## 1. Игру через интернет по Коду комнаты (Room Code) и внешнему IP.
## 2. Автоматический проброс портов роутера через UPnP.
## 3. Автопоиск активных лобби в локальной сети, Wi-Fi и виртуальных VPN (Radmin / Hamachi).
## 4. Браузер открытых лобби (Master Server / Matchmaking).
## 5. Кооператив до 4 игроков с выбором классов, синхронизацией мира, экономики и чата.

signal lobby_updated(players: Dictionary)
signal player_joined_lobby(player_info: Dictionary)
signal player_left_lobby(peer_id: int)
signal chat_message_received(sender_name: String, message: String)
signal connection_status_changed(status_text: String, is_error: bool)
signal upnp_status_changed(status_text: String, is_active: bool)
signal lobbies_discovered_updated(lobbies: Array)
signal external_ip_detected(ip: String, code: String)
signal game_started()

const DEFAULT_PORT: int = 7777
const DISCOVERY_PORT: int = 7778
const MAX_PLAYERS: int = 4

var is_multiplayer: bool = false
var is_host: bool = false
var local_player_name: String = "Ликвидатор"
var local_class_id: String = "cleaner"
var lobby_title: String = "Смена Сосновки"
var current_port: int = DEFAULT_PORT

# Сетевые адреса и код комнаты
var external_ip: String = ""
var local_ip: String = "127.0.0.1"
var room_code: String = ""
var upnp_active: bool = false
var upnp_status_text: String = "UPnP не активен"
var upnp_obj: UPNP = null
var upnp_thread: Thread = null

# LAN / VPN обнаружение
var lan_broadcaster: PacketPeerUDP = null
var lan_listener: PacketPeerUDP = null
var lan_discovered_lobbies: Dictionary = {}
var lan_broadcast_timer: float = 0.0

# Мастер-сервер (Список публичных серверов в интернете)
var master_server_url: String = "" # Например: "http://my-master-server.com:8080"
var master_registered: bool = false
var master_heartbeat_timer: float = 0.0
var master_lobby_id: String = ""

# Реестр игроков: peer_id (int) -> Dictionary
var players: Dictionary = {}

# Хранилище ссылок на заспавненные узлы игроков: peer_id -> PlayerController
var player_nodes: Dictionary = {}

func _ready() -> void:
	randomize()
	var code_num = randi_range(10, 99)
	local_player_name = "Ликвидатор-%d" % code_num
	lobby_title = "Смена #%d — Зачистка" % code_num
	
	local_ip = detect_local_ip()
	_detect_external_ip_async()
	_start_lan_listener()

func _process(delta: float) -> void:
	# 1. Периодический опрос входящих пакетов LAN-обнаружения
	_poll_lan_listener()
	
	# 2. Если мы хост — рассылаем маяк в локальную сеть / VPN
	if is_host and is_multiplayer_active():
		lan_broadcast_timer += delta
		if lan_broadcast_timer >= 1.5:
			lan_broadcast_timer = 0.0
			_broadcast_lan_beacon()
			
		# 3. Heartbeat мастер-сервера
		if master_server_url != "" and master_registered:
			master_heartbeat_timer += delta
			if master_heartbeat_timer >= 15.0:
				master_heartbeat_timer = 0.0
				_send_master_heartbeat()

func _exit_tree() -> void:
	disconnect_game()
	_stop_lan_listener()

# ==============================================================================
# КОД КОМНАТЫ (ROOM CODE) И ПАРСИНГ АДРЕСОВ
# ==============================================================================

## Преобразует IPv4 адрес и порт в компактный аутентичный код комнаты ZONE-XXXX-XXXX-XXXX
static func encode_room_code(ip: String, port: int) -> String:
	var parts = ip.split(".")
	if parts.size() != 4:
		return "%s:%d" % [ip, port]
		
	var o1 = int(parts[0]) & 0xFF
	var o2 = int(parts[1]) & 0xFF
	var o3 = int(parts[2]) & 0xFF
	var o4 = int(parts[3]) & 0xFF
	var p = port & 0xFFFF
	
	var hex_str = "%02X%02X%02X%02X%04X" % [o1, o2, o3, o4, p]
	return "ZONE-%s-%s-%s" % [hex_str.substr(0, 4), hex_str.substr(4, 4), hex_str.substr(8, 4)]

## Универсальный парсер: принимает код комнаты ZONE-..., IP:PORT или чистый IP
static func parse_connection_string(raw_input: String, default_port: int = DEFAULT_PORT) -> Dictionary:
	var clean = raw_input.strip_edges()
	clean = clean.replace(" ", "")
	
	# 1. Если это код комнаты формата ZONE-XXXX-XXXX-XXXX или 12 hex-символов
	var hex_clean = clean.to_upper().replace("ZONE-", "").replace("-", "")
	if hex_clean.length() == 12 and _is_hex_string(hex_clean):
		var o1 = ("0x" + hex_clean.substr(0, 2)).hex_to_int()
		var o2 = ("0x" + hex_clean.substr(2, 2)).hex_to_int()
		var o3 = ("0x" + hex_clean.substr(4, 2)).hex_to_int()
		var o4 = ("0x" + hex_clean.substr(6, 2)).hex_to_int()
		var p = ("0x" + hex_clean.substr(8, 4)).hex_to_int()
		var decoded_ip = "%d.%d.%d.%d" % [o1, o2, o3, o4]
		return { "ip": decoded_ip, "port": p, "is_valid": true, "is_code": true }
		
	# 2. Если это формат IP:PORT
	if ":" in clean:
		var split_colon = clean.split(":")
		var ip_part = split_colon[0].strip_edges()
		var port_part = int(split_colon[1].strip_edges())
		if port_part <= 0: port_part = default_port
		return { "ip": ip_part, "port": port_part, "is_valid": (ip_part != ""), "is_code": false }
		
	# 3. Чистый IP или хостнейм
	if clean != "":
		return { "ip": clean, "port": default_port, "is_valid": true, "is_code": false }
		
	return { "ip": "127.0.0.1", "port": default_port, "is_valid": false, "is_code": false }

static func _is_hex_string(s: String) -> bool:
	for c in s:
		if not (c in "0123456789ABCDEFabcdef"):
			return false
	return true

## Определение локального LAN / VPN адреса
func detect_local_ip() -> String:
	for address in IP.get_local_addresses():
		# Приоритет: Radmin VPN (26.x.x.x), Hamachi (25.x.x.x), домашний LAN (192.168.x.x, 10.x.x.x)
		if address.begins_with("26.") or address.begins_with("25."):
			return address
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			return address
	return "127.0.0.1"

## Асинхронное определение внешнего интернет-IP адреса
func _detect_external_ip_async() -> void:
	var http = HTTPRequest.new()
	http.name = "IPDetector"
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var ip_str = body.get_string_from_utf8().strip_edges()
			if ip_str != "" and not ":" in ip_str: # IPv4
				external_ip = ip_str
				room_code = encode_room_code(external_ip, current_port)
				external_ip_detected.emit(external_ip, room_code)
		http.queue_free()
	)
	http.request("https://api.ipify.org")

# ==============================================================================
# UPnP: АВТОМАТИЧЕСКИЙ ПРОБРОС ПОРТОВ РОУТЕРА
# ==============================================================================

func start_upnp_async(port: int) -> void:
	if upnp_thread and upnp_thread.is_alive():
		return
	upnp_thread = Thread.new()
	upnp_thread.start(_upnp_worker.bind(port))

func _upnp_worker(port: int) -> void:
	upnp_status_text = "Поиск UPnP-роутера в локальной сети..."
	upnp_active = false
	call_deferred("_emit_upnp_status", upnp_status_text, false)
	
	upnp_obj = UPNP.new()
	var discover_err = upnp_obj.discover(2000, 2, "InternetGatewayDevice")
	if discover_err != UPNP.UPNP_RESULT_SUCCESS:
		upnp_status_text = "UPnP на роутере не обнаружен. Для игры через интернет используйте Radmin VPN или Port Forwarding."
		call_deferred("_emit_upnp_status", upnp_status_text, false)
		return
		
	var gateway = upnp_obj.get_gateway()
	if not gateway or not gateway.is_valid_gateway():
		upnp_status_text = "Действительный шлюз UPnP не найден."
		call_deferred("_emit_upnp_status", upnp_status_text, false)
		return
		
	var err_udp = upnp_obj.add_port_mapping(port, port, "Pripyat_UDP", "UDP")
	var err_tcp = upnp_obj.add_port_mapping(port, port, "Pripyat_TCP", "TCP")
	
	if err_udp == UPNP.UPNP_RESULT_SUCCESS or err_tcp == UPNP.UPNP_RESULT_SUCCESS:
		upnp_active = true
		var ext = upnp_obj.query_external_address()
		if ext != "" and ext != "0.0.0.0":
			external_ip = ext
			room_code = encode_room_code(external_ip, port)
			call_deferred("_emit_ext_ip", external_ip, room_code)
			
		upnp_status_text = "● UPnP активен! Порт %d открыт для прямого подключения через интернет." % port
		call_deferred("_emit_upnp_status", upnp_status_text, true)
	else:
		upnp_status_text = "Не удалось открыть порт через UPnP (код: %d)." % err_udp
		call_deferred("_emit_upnp_status", upnp_status_text, false)

func _emit_upnp_status(text: String, is_act: bool) -> void:
	upnp_status_changed.emit(text, is_act)

func _emit_ext_ip(ip: String, code: String) -> void:
	external_ip_detected.emit(ip, code)

func cleanup_upnp(port: int) -> void:
	if upnp_active and upnp_obj:
		upnp_obj.delete_port_mapping(port, "UDP")
		upnp_obj.delete_port_mapping(port, "TCP")
		upnp_active = false
		upnp_obj = null
	if upnp_thread and upnp_thread.is_alive():
		upnp_thread.wait_to_finish()
		upnp_thread = null

# ==============================================================================
# LAN / VPN ОБНАРУЖЕНИЕ (DISCOVERY)
# ==============================================================================

func _start_lan_listener() -> void:
	_stop_lan_listener()
	lan_listener = PacketPeerUDP.new()
	var err = lan_listener.bind(DISCOVERY_PORT)
	if err != OK:
		# Порт может быть занят другим инстансом на том же ПК
		pass

func _stop_lan_listener() -> void:
	if lan_listener:
		lan_listener.close()
		lan_listener = null

func _poll_lan_listener() -> void:
	if not lan_listener:
		return
	var changed = false
	var now = Time.get_ticks_msec()
	
	while lan_listener.get_available_packet_count() > 0:
		var sender_ip = lan_listener.get_packet_ip()
		var raw = lan_listener.get_packet().get_string_from_utf8()
		var data = JSON.parse_string(raw)
		if typeof(data) == TYPE_DICTIONARY:
			var port = data.get("port", DEFAULT_PORT)
			var key = "%s:%d" % [sender_ip, port]
			data["ip"] = sender_ip
			data["last_seen"] = now
			data["type"] = "LAN / VPN"
			lan_discovered_lobbies[key] = data
			changed = true
			
	# Удаляем устаревшие лобби (не отвечающие > 4 сек)
	var keys_to_remove = []
	for k in lan_discovered_lobbies:
		if now - lan_discovered_lobbies[k].get("last_seen", 0) > 4000:
			keys_to_remove.append(k)
	for k in keys_to_remove:
		lan_discovered_lobbies.erase(k)
		changed = true
		
	if changed:
		lobbies_discovered_updated.emit(get_all_discovered_lobbies())

func _start_lan_broadcaster() -> void:
	if not lan_broadcaster:
		lan_broadcaster = PacketPeerUDP.new()
		lan_broadcaster.set_broadcast_enabled(true)
		lan_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)

func _stop_lan_broadcaster() -> void:
	if lan_broadcaster:
		lan_broadcaster.close()
		lan_broadcaster = null

func _broadcast_lan_beacon() -> void:
	if not is_host or not lan_broadcaster:
		return
	var payload = {
		"name": lobby_title,
		"host": local_player_name,
		"players": players.size(),
		"max_players": MAX_PLAYERS,
		"port": current_port,
		"code": room_code,
		"class": local_class_id
	}
	var data = JSON.stringify(payload).to_utf8_buffer()
	lan_broadcaster.put_packet(data)

func get_all_discovered_lobbies() -> Array:
	return lan_discovered_lobbies.values()

# ==============================================================================
# МАСТЕР-СЕРВЕР (ОБЩИЙ СПИСОК СЕРВЕРОВ В ИНТЕРНЕТЕ)
# ==============================================================================

func register_master_server(title: String, port: int) -> void:
	if master_server_url == "":
		return
	master_lobby_id = "%s_%d_%d" % [local_player_name, port, randi_range(1000, 9999)]
	var http = HTTPRequest.new()
	add_child(http)
	var url = master_server_url.trim_suffix("/") + "/api/lobbies"
	var payload = {
		"id": master_lobby_id,
		"name": title,
		"host": local_player_name,
		"ip": external_ip if external_ip != "" else local_ip,
		"port": port,
		"code": room_code,
		"players": players.size(),
		"max_players": MAX_PLAYERS
	}
	var body = JSON.stringify(payload)
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, _b: PackedByteArray):
		if code == 200 or code == 201:
			master_registered = true
		http.queue_free()
	)
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)

func _send_master_heartbeat() -> void:
	if master_server_url == "" or master_lobby_id == "":
		return
	var http = HTTPRequest.new()
	add_child(http)
	var url = "%s/api/lobbies/%s/heartbeat" % [master_server_url.trim_suffix("/"), master_lobby_id]
	var payload = { "players": players.size() }
	http.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray):
		http.queue_free()
	)
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))

func unregister_master_server() -> void:
	if master_server_url == "" or master_lobby_id == "":
		return
	var http = HTTPRequest.new()
	add_child(http)
	var url = "%s/api/lobbies/%s" % [master_server_url.trim_suffix("/"), master_lobby_id]
	http.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray):
		http.queue_free()
	)
	http.request(url, [], HTTPClient.METHOD_DELETE)
	master_registered = false
	master_lobby_id = ""

func refresh_master_server_lobbies() -> void:
	if master_server_url == "":
		return
	var http = HTTPRequest.new()
	add_child(http)
	var url = master_server_url.trim_suffix("/") + "/api/lobbies"
	http.request_completed.connect(func(res: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		if res == HTTPRequest.RESULT_SUCCESS and code == 200:
			var data = JSON.parse_string(body.get_string_from_utf8())
			if typeof(data) == TYPE_ARRAY:
				for lobby in data:
					if typeof(lobby) == TYPE_DICTIONARY:
						var key = "%s:%d" % [lobby.get("ip", ""), lobby.get("port", DEFAULT_PORT)]
						lobby["type"] = "ИНТЕРНЕТ"
						lan_discovered_lobbies[key] = lobby
				lobbies_discovered_updated.emit(get_all_discovered_lobbies())
		http.queue_free()
	)
	http.request(url)

# ==============================================================================
# ОСНОВНЫЕ МЕТОДЫ ХОСТИНГА И ПОДКЛЮЧЕНИЯ
# ==============================================================================

## Создание сервера (Хост)
func host_game(port: int = DEFAULT_PORT, player_name: String = "", class_id: String = "cleaner", title: String = "", use_upnp: bool = true) -> Error:
	disconnect_game()
	
	current_port = port
	if player_name.strip_edges() != "":
		local_player_name = player_name.strip_edges()
	if title.strip_edges() != "":
		lobby_title = title.strip_edges()
	local_class_id = class_id
	
	local_ip = detect_local_ip()
	if external_ip != "":
		room_code = encode_room_code(external_ip, current_port)
	else:
		room_code = encode_room_code(local_ip, current_port)
		
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		connection_status_changed.emit("Ошибка запуска сервера на порту %d (код: %d)" % [port, err], true)
		return err
		
	multiplayer.multiplayer_peer = peer
	is_multiplayer = true
	is_host = true
	
	_setup_multiplayer_signals()
	
	players.clear()
	players[1] = {
		"peer_id": 1,
		"name": local_player_name,
		"class_id": local_class_id,
		"ready": true,
		"is_host": true,
		"slot": 0
	}
	
	GameState.set_class(local_class_id)
	
	# Запуск UPnP проброса в фоне
	if use_upnp:
		start_upnp_async(port)
		
	# Запуск LAN маяка
	_start_lan_broadcaster()
	
	# Регистрация на мастер-сервере (если задан)
	if master_server_url != "":
		register_master_server(lobby_title, port)
		
	connection_status_changed.emit("Лобби открыто! Код комнаты: %s. Ожидание бойцов..." % room_code, false)
	lobby_updated.emit(players)
	return OK

## Подключение клиента к лобби по коду или IP:PORT
func join_game(connection_target: String, port: int = DEFAULT_PORT, player_name: String = "", class_id: String = "cleaner") -> Error:
	disconnect_game()
	
	var parsed = parse_connection_string(connection_target, port)
	if not parsed.is_valid:
		connection_status_changed.emit("Неверный формат адреса или кода комнаты!", true)
		return ERR_INVALID_PARAMETER
		
	var target_ip = parsed.ip
	var target_port = parsed.port
	
	if player_name.strip_edges() != "":
		local_player_name = player_name.strip_edges()
	local_class_id = class_id
	
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(target_ip, target_port)
	if err != OK:
		connection_status_changed.emit("Не удалось начать подключение к %s:%d (код: %d)" % [target_ip, target_port, err], true)
		return err
		
	multiplayer.multiplayer_peer = peer
	is_multiplayer = true
	is_host = false
	
	_setup_multiplayer_signals()
	connection_status_changed.emit("Подключение к отряду [%s:%d]..." % [target_ip, target_port], false)
	return OK

## Отключение от сети
func disconnect_game() -> void:
	if is_host:
		_stop_lan_broadcaster()
		cleanup_upnp(current_port)
		unregister_master_server()
		
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		
	_clear_multiplayer_signals()
	is_multiplayer = false
	is_host = false
	players.clear()
	player_nodes.clear()
	lobby_updated.emit(players)

func _setup_multiplayer_signals() -> void:
	_clear_multiplayer_signals()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _clear_multiplayer_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)

func _on_peer_connected(peer_id: int) -> void:
	if not is_host:
		return

func _on_peer_disconnected(peer_id: int) -> void:
	if is_host:
		if players.has(peer_id):
			var left_name = players[peer_id].get("name", "Игрок")
			players.erase(peer_id)
			sync_lobby_state.rpc(players)
			broadcast_chat_message.rpc("ШТАБ", "Ликвидатор %s покинул смену." % left_name)
	
	if player_nodes.has(peer_id):
		if is_instance_valid(player_nodes[peer_id]):
			player_nodes[peer_id].queue_free()
		player_nodes.erase(peer_id)
		
	player_left_lobby.emit(peer_id)

func _on_connected_to_server() -> void:
	connection_status_changed.emit("Связь с базой установлена! Регистрация в отряде...", false)
	var my_id = multiplayer.get_unique_id()
	request_join_lobby.rpc_id(1, my_id, local_player_name, local_class_id)

func _on_connection_failed() -> void:
	connection_status_changed.emit("Ошибка подключения. Проверьте код комнаты, IP и доступность порта.", true)
	disconnect_game()

func _on_server_disconnected() -> void:
	connection_status_changed.emit("Связь с сервером потеряна (хост закрыл лобби).", true)
	disconnect_game()
	if get_tree().current_scene and get_tree().current_scene.name != "MultiplayerLobby":
		get_tree().change_scene_to_file("res://scenes/ui/MultiplayerLobby.tscn")

# ==============================================================================
# RPC СИНХРОНИЗАЦИЯ ЛОББИ
# ==============================================================================

@rpc("any_peer", "reliable")
func request_join_lobby(peer_id: int, p_name: String, p_class: String) -> void:
	if not is_host:
		return
		
	if players.size() >= MAX_PLAYERS:
		reject_join.rpc_id(peer_id, "Лобби переполнено (максимум %d игрока)." % MAX_PLAYERS)
		return
		
	var slot = _get_next_free_slot()
	players[peer_id] = {
		"peer_id": peer_id,
		"name": p_name,
		"class_id": p_class,
		"ready": false,
		"is_host": false,
		"slot": slot
	}
	
	sync_lobby_state.rpc(players)
	broadcast_chat_message.rpc("ШТАБ", "Ликвидатор %s прибыл на базу (Слот #%d)." % [p_name, slot + 1])

@rpc("reliable")
func reject_join(reason: String) -> void:
	connection_status_changed.emit("Отказ в доступе: %s" % reason, true)
	disconnect_game()

@rpc("call_local", "reliable")
func sync_lobby_state(synced_players: Dictionary) -> void:
	players = synced_players
	lobby_updated.emit(players)

func _get_next_free_slot() -> int:
	var occupied = []
	for p in players.values():
		occupied.append(p.get("slot", 0))
	for s in range(MAX_PLAYERS):
		if not s in occupied:
			return s
	return 0

func set_local_class(class_id: String) -> void:
	local_class_id = class_id
	GameState.set_class(class_id)
	
	if is_multiplayer_active():
		var my_id = multiplayer.get_unique_id()
		if is_host:
			if players.has(my_id):
				players[my_id]["class_id"] = class_id
				sync_lobby_state.rpc(players)
		else:
			request_change_class.rpc_id(1, my_id, class_id)

@rpc("any_peer", "reliable")
func request_change_class(peer_id: int, class_id: String) -> void:
	if not is_host:
		return
	if players.has(peer_id):
		players[peer_id]["class_id"] = class_id
		sync_lobby_state.rpc(players)

func toggle_local_ready() -> void:
	if is_multiplayer_active():
		var my_id = multiplayer.get_unique_id()
		if players.has(my_id):
			var current_ready = players[my_id].get("ready", false)
			var new_ready = not current_ready
			if is_host:
				players[my_id]["ready"] = new_ready
				sync_lobby_state.rpc(players)
			else:
				request_set_ready.rpc_id(1, my_id, new_ready)

@rpc("any_peer", "reliable")
func request_set_ready(peer_id: int, is_ready: bool) -> void:
	if not is_host:
		return
	if players.has(peer_id):
		players[peer_id]["ready"] = is_ready
		sync_lobby_state.rpc(players)

func can_start_game() -> bool:
	if not is_host or players.size() == 0:
		return false
	for p in players.values():
		if not p.get("is_host", false) and not p.get("ready", false):
			return false
	return true

func host_start_game(scene_path: String = "res://scenes/world/SosnovkaVillage.tscn") -> void:
	if not is_host:
		return
	start_game_rpc.rpc(scene_path)

@rpc("call_local", "reliable")
func start_game_rpc(scene_path: String) -> void:
	game_started.emit()
	get_tree().change_scene_to_file(scene_path)

func send_chat_message(text: String) -> void:
	if text.strip_edges() == "":
		return
	var sender = local_player_name
	if is_multiplayer_active():
		broadcast_chat_message.rpc(sender, text.strip_edges())
	else:
		chat_message_received.emit(sender, text.strip_edges())

@rpc("any_peer", "call_local", "reliable")
func broadcast_chat_message(sender_name: String, message: String) -> void:
	chat_message_received.emit(sender_name, message)

# ==============================================================================
# СПАВН ИГРОКОВ В МИРЕ
# ==============================================================================

func is_multiplayer_active() -> bool:
	return is_multiplayer and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED

func get_local_player_node() -> PlayerController:
	var my_id = multiplayer.get_unique_id() if is_multiplayer_active() else 1
	if player_nodes.has(my_id):
		return player_nodes[my_id]
	return null

func spawn_players(parent_container: Node, spawn_points: Array[Vector3], player_scene: PackedScene) -> void:
	player_nodes.clear()
	
	if not is_multiplayer_active() or players.size() == 0:
		var p = player_scene.instantiate() as PlayerController
		p.name = "Player_1"
		p.set_multiplayer_authority(1)
		parent_container.add_child(p)
		var sp = spawn_points[0] if spawn_points.size() > 0 else Vector3(25.0, 0.25, 45.0)
		p.global_position = sp
		var solo_info = {
			"peer_id": 1,
			"name": local_player_name,
			"class_id": local_class_id,
			"ready": true,
			"is_host": true,
			"slot": 0
		}
		p.setup_player(solo_info)
		player_nodes[1] = p
		return
		
	for pid in players:
		var p_info = players[pid]
		var p = player_scene.instantiate() as PlayerController
		p.name = "Player_%d" % pid
		p.set_multiplayer_authority(pid)
		parent_container.add_child(p)
		
		var slot = p_info.get("slot", 0)
		var sp_idx = slot % spawn_points.size()
		p.global_position = spawn_points[sp_idx]
		
		p.setup_player(p_info)
		player_nodes[pid] = p

# ==============================================================================
# СИНХРОНИЗАЦИЯ ЭКОНОМИКИ
# ==============================================================================

func sync_rubles_across_squad(new_rubles: int, delta: int) -> void:
	if is_multiplayer_active():
		rpc_sync_rubles.rpc(new_rubles, delta)

@rpc("any_peer", "call_local", "reliable")
func rpc_sync_rubles(new_rubles: int, delta: int) -> void:
	if GameState and GameState.karbovantsi != new_rubles:
		GameState.karbovantsi = new_rubles

func sync_cleanliness_across_squad(cleaned: int, total: int, pct: float) -> void:
	if is_multiplayer_active():
		rpc_sync_cleanliness.rpc(cleaned, total, pct)

@rpc("any_peer", "call_local", "reliable")
func rpc_sync_cleanliness(cleaned: int, total: int, pct: float) -> void:
	if GameState:
		GameState.cleaned_items = cleaned
		GameState.total_items = total
	EventBus.cleanliness_updated.emit(cleaned, total, pct)
