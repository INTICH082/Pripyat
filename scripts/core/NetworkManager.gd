extends Node

## Менеджер мультиплеера и сетевого лобби (NetworkManager)
## Поддерживает:
## 1. Игру через интернет по Коду комнаты (Room Code) и внешнему IP.
## 2. Автоматический проброс портов роутера через UPnP с детекцией CGNAT / Double NAT.
## 3. Мульти-интерфейсный автопоиск активных лобби в локальной сети, Wi-Fi и VPN (Radmin / Hamachi / EasyVPN / Tailscale).
## 4. Активный UDP-опрос (Discovery Probe) и мгновенный Unicast-ответ.
## 5. Браузер открытых лобби (Master Server / Matchmaking) с Bearer-авторизацией и Hairpin NAT fallback.
## 6. Кооператив до 4 игроков с выбором классов, синхронизацией мира, экономики и чата.

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
const DISCOVERY_PORTS: Array[int] = [7778, 7779, 7780, 7781]
const MAX_PLAYERS: int = 4
const NETWORK_CONFIG_PATH: String = "user://network_settings.cfg"

const EXTERNAL_IP_ENDPOINTS: Array[String] = [
	"https://api.ipify.org",
	"https://icanhazip.com",
	"https://api4.my-ip.io/ip",
	"https://checkip.amazonaws.com"
]

var is_multiplayer: bool = false
var is_host: bool = false
var local_player_name: String = "Ликвидатор"
var local_class_id: String = "cleaner"
var lobby_title: String = "Смена Сосновки"
var current_port: int = DEFAULT_PORT
var lobby_uid: String = ""

# Сетевые адреса и коды комнаты
var external_ip: String = ""
var local_ip: String = "127.0.0.1"
var local_ips: Array[String] = []
var room_code: String = ""
var local_room_code: String = ""
var upnp_active: bool = false
var upnp_cgnat_detected: bool = false
var upnp_status_text: String = "UPnP не активен"
var upnp_obj: UPNP = null
var upnp_thread: Thread = null
var upnp_mutex: Mutex = Mutex.new()

# LAN / VPN обнаружение
var lan_broadcasters: Array[PacketPeerUDP] = []
var lan_listener: PacketPeerUDP = null
var lan_listener_port: int = 0
var lan_discovered_lobbies: Dictionary = {}
var internet_discovered_lobbies: Dictionary = {}
var lan_broadcast_timer: float = 0.0

# Мастер-сервер (Список публичных серверов в интернете)
var master_server_url: String = "" # Например: "http://my-master-server.com:8080"
var master_registered: bool = false
var master_heartbeat_timer: float = 0.0
var master_lobby_id: String = ""
var master_lobby_token: String = ""

# Реестр игроков: peer_id (int) -> Dictionary
var players: Dictionary = {}

# Хранилище ссылок на заспавненные узлы игроков: peer_id -> PlayerController
var player_nodes: Dictionary = {}

func _ready() -> void:
	randomize()
	var code_num = randi_range(10, 99)
	local_player_name = "Ликвидатор-%d" % code_num
	lobby_title = "Смена #%d — Зачистка" % code_num
	
	load_network_settings()
	refresh_local_network_info()
	_detect_external_ip_async(0)
	_start_lan_listener()

func _process(delta: float) -> void:
	# 1. Периодический опрос входящих пакетов LAN / VPN обнаружения
	_poll_lan_listener()
	
	# 2. Если мы хост — рассылаем маяк по всем локальным и VPN интерфейсам
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
# НАСТРОЙКИ МАСТЕР-СЕРВЕРА
# ==============================================================================

func set_master_server_url(url: String) -> void:
	var clean = url.strip_edges().trim_suffix("/")
	if clean != "" and not clean.begins_with("http://") and not clean.begins_with("https://"):
		clean = "http://" + clean
	master_server_url = clean
	save_network_settings()
	internet_discovered_lobbies.clear()
	lobbies_discovered_updated.emit(get_all_discovered_lobbies())

func save_network_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("network", "master_server_url", master_server_url)
	cfg.save(NETWORK_CONFIG_PATH)

func load_network_settings() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(NETWORK_CONFIG_PATH) == OK:
		master_server_url = str(cfg.get_value("network", "master_server_url", "")).strip_edges().trim_suffix("/")

# ==============================================================================
# КОД КОМНАТЫ (ROOM CODE), ОПРЕДЕЛЕНИЕ И КЛАССИФИКАЦИЯ IPv4
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

static func is_valid_ipv4(ip: String) -> bool:
	var parts = ip.split(".")
	if parts.size() != 4:
		return false
	for p in parts:
		if p == "" or not p.is_valid_int():
			return false
		var v = int(p)
		if v < 0 or v > 255:
			return false
	return true

static func is_public_ipv4(ip: String) -> bool:
	if not is_valid_ipv4(ip):
		return false
	var parts = ip.split(".")
	var o1 = int(parts[0])
	var o2 = int(parts[1])
	
	if o1 == 0 or o1 == 10 or o1 == 127:
		return false
	if o1 == 169 and o2 == 254:
		return false
	if o1 == 192 and o2 == 168:
		return false
	if o1 == 172 and o2 >= 16 and o2 <= 31:
		return false
	# CGNAT (100.64.0.0/10) и Tailscale
	if o1 == 100 and o2 >= 64 and o2 <= 127:
		return false
	# Виртуальные игровые сети Radmin VPN (26.x) / Hamachi (25.x)
	if o1 == 25 or o1 == 26:
		return false
	return true

static func _get_ip_priority(ip: String) -> int:
	if not is_valid_ipv4(ip):
		return 999
	var parts = ip.split(".")
	var o1 = int(parts[0])
	var o2 = int(parts[1])
	
	# Приоритет 0: Игровые VPN (Radmin 26.x, Hamachi 25.x)
	if o1 == 26 or o1 == 25:
		return 0
	# Приоритет 1: Mesh / Tunnel VPN (Tailscale 100.64-127.x, EasyVPN/OpenVPN 172.16-31.x)
	if (o1 == 100 and o2 >= 64 and o2 <= 127) or (o1 == 172 and o2 >= 16 and o2 <= 31):
		return 1
	# Приоритет 2: Домашний Wi-Fi / LAN (192.168.x.x)
	if o1 == 192 and o2 == 168:
		return 2
	# Приоритет 3: Корпоративные / виртуальные подсети (10.x.x.x)
	if o1 == 10:
		return 3
	# Приоритет 4: Прочие белые/маршрутизируемые адреса
	if o1 != 127 and o1 != 0 and not (o1 == 169 and o2 == 254):
		return 4
	return 999

## Возвращает отсортированный список всех пригодных локальных/VPN IPv4-адресов
func get_all_local_ipv4() -> Array[String]:
	var found: Array[String] = []
	for address in IP.get_local_addresses():
		if is_valid_ipv4(address) and _get_ip_priority(address) < 999:
			if not (address in found):
				found.append(address)
	found.sort_custom(func(a: String, b: String) -> bool:
		return _get_ip_priority(a) < _get_ip_priority(b)
	)
	return found

## Определение наилучшего локального LAN / VPN адреса (с учётом строгого приоритета)
func detect_local_ip() -> String:
	var all_ips = get_all_local_ipv4()
	if all_ips.size() > 0:
		return all_ips[0]
	return "127.0.0.1"

func refresh_local_network_info() -> void:
	local_ips = get_all_local_ipv4()
	local_ip = local_ips[0] if local_ips.size() > 0 else "127.0.0.1"
	_update_room_codes()

func _update_room_codes() -> void:
	local_room_code = encode_room_code(local_ip, current_port)
	if external_ip != "" and is_public_ipv4(external_ip) and not upnp_cgnat_detected:
		room_code = encode_room_code(external_ip, current_port)
	else:
		room_code = local_room_code

## Асинхронное определение внешнего интернет-IP с резервными серверами
func _detect_external_ip_async(endpoint_idx: int = 0) -> void:
	if endpoint_idx >= EXTERNAL_IP_ENDPOINTS.size():
		return
	var http = HTTPRequest.new()
	http.name = "IPDetector_%d" % endpoint_idx
	http.timeout = 4.0
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		var success = false
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var ip_str = body.get_string_from_utf8().strip_edges()
			if is_valid_ipv4(ip_str) and is_public_ipv4(ip_str):
				external_ip = ip_str
				_update_room_codes()
				external_ip_detected.emit(external_ip, room_code)
				if is_host and master_registered:
					_send_master_heartbeat(true)
				success = true
		http.queue_free()
		if not success:
			_detect_external_ip_async(endpoint_idx + 1)
	)
	http.request(EXTERNAL_IP_ENDPOINTS[endpoint_idx])

# ==============================================================================
# UPnP: АВТОМАТИЧЕСКИЙ ПРОБРОС ПОРТОВ РОУТЕРА И ДЕТЕКЦИЯ CGNAT
# ==============================================================================

func start_upnp_async(port: int) -> void:
	if upnp_thread:
		if upnp_thread.is_alive():
			return
		if upnp_thread.is_started():
			upnp_thread.wait_to_finish()
		upnp_thread = null
	upnp_thread = Thread.new()
	upnp_thread.start(_upnp_worker.bind(port))

func _upnp_worker(port: int) -> void:
	upnp_mutex.lock()
	upnp_status_text = "Поиск UPnP-роутера в локальной сети..."
	upnp_active = false
	upnp_cgnat_detected = false
	upnp_mutex.unlock()
	call_deferred("_emit_upnp_status", upnp_status_text, false)
	
	var local_upnp = UPNP.new()
	var discover_err = local_upnp.discover(2500, 2, "InternetGatewayDevice")
	if discover_err != UPNP.UPNP_RESULT_SUCCESS:
		# Резервный широкий SSDP поиск
		discover_err = local_upnp.discover(2000, 2, "")
		
	if discover_err != UPNP.UPNP_RESULT_SUCCESS:
		upnp_mutex.lock()
		upnp_status_text = "UPnP на роутере не найден. Используйте Radmin/Hamachi VPN или ручной Port Forwarding (%d UDP)." % port
		upnp_mutex.unlock()
		call_deferred("_emit_upnp_status", upnp_status_text, false)
		return
		
	var gateway = local_upnp.get_gateway()
	if not gateway or not gateway.is_valid_gateway():
		upnp_mutex.lock()
		upnp_status_text = "Действительный шлюз UPnP не найден. Используйте VPN или проброс порта %d UDP." % port
		upnp_mutex.unlock()
		call_deferred("_emit_upnp_status", upnp_status_text, false)
		return
		
	var err_udp = local_upnp.add_port_mapping(port, port, "Pripyat_UDP", "UDP")
	var err_tcp = local_upnp.add_port_mapping(port, port, "Pripyat_TCP", "TCP")
	
	if err_udp == UPNP.UPNP_RESULT_SUCCESS or err_tcp == UPNP.UPNP_RESULT_SUCCESS:
		var ext = local_upnp.query_external_address()
		var is_cgnat = false
		if ext != "" and ext != "0.0.0.0":
			if not is_public_ipv4(ext):
				is_cgnat = true
			elif external_ip != "" and ext != external_ip:
				is_cgnat = true
				
		upnp_mutex.lock()
		upnp_obj = local_upnp
		upnp_cgnat_detected = is_cgnat
		if is_cgnat:
			upnp_active = false
			upnp_status_text = "⚠ Серый IP провайдера (CGNAT / Double NAT: %s). Прямой вход из интернета невозможен — используйте VPN-код!" % ext
			upnp_mutex.unlock()
			call_deferred("_on_upnp_cgnat_detected")
			return
		else:
			upnp_active = true
			if ext != "" and ext != "0.0.0.0" and is_public_ipv4(ext):
				external_ip = ext
			upnp_status_text = "● UPnP активен! Порт %d открыт для подключения через интернет." % port
			upnp_mutex.unlock()
			call_deferred("_on_upnp_ready")
	else:
		upnp_mutex.lock()
		upnp_status_text = "Не удалось открыть порт через UPnP (код: %d). Откройте UDP %d вручную или используйте VPN." % [err_udp, port]
		upnp_mutex.unlock()
		call_deferred("_emit_upnp_status", upnp_status_text, false)

func _on_upnp_ready() -> void:
	_update_room_codes()
	external_ip_detected.emit(external_ip, room_code)
	upnp_status_changed.emit(upnp_status_text, true)
	if is_host and master_registered:
		_send_master_heartbeat(true)

func _on_upnp_cgnat_detected() -> void:
	_update_room_codes()
	external_ip_detected.emit(external_ip, room_code)
	upnp_status_changed.emit(upnp_status_text, false)
	if is_host:
		chat_message_received.emit("ШТАБ", "Обнаружен серый IP провайдера (CGNAT). Для игры с друзьями используйте Radmin VPN / Hamachi / EasyVPN — код VPN: %s" % local_room_code)

func _emit_upnp_status(text: String, is_act: bool) -> void:
	upnp_status_changed.emit(text, is_act)

func _emit_ext_ip(ip: String, code: String) -> void:
	external_ip_detected.emit(ip, code)

func cleanup_upnp(port: int) -> void:
	if upnp_thread:
		if upnp_thread.is_started():
			upnp_thread.wait_to_finish()
		upnp_thread = null
		
	upnp_mutex.lock()
	if upnp_obj:
		upnp_obj.delete_port_mapping(port, "UDP")
		upnp_obj.delete_port_mapping(port, "TCP")
		upnp_active = false
		upnp_obj = null
	upnp_cgnat_detected = false
	upnp_mutex.unlock()

# ==============================================================================
# LAN / VPN ОБНАРУЖЕНИЕ (МУЛЬТИ-ИНТЕРФЕЙСНЫЙ BROADCAST + АКТИВНЫЙ PROBE)
# ==============================================================================

func _start_lan_listener() -> void:
	_stop_lan_listener()
	lan_listener = PacketPeerUDP.new()
	for p in DISCOVERY_PORTS:
		if lan_listener.bind(p) == OK:
			lan_listener_port = p
			return
	# Если все стандартные порты заняты (например, 5-й инстанс на том же ПК) — берем эфемерный порт
	if lan_listener.bind(0) == OK:
		lan_listener_port = lan_listener.get_local_port()
	else:
		lan_listener_port = 0

func _stop_lan_listener() -> void:
	if lan_listener:
		lan_listener.close()
		lan_listener = null
		lan_listener_port = 0

func _get_broadcast_targets() -> Array[String]:
	var targets: Array[String] = ["255.255.255.255", "127.0.0.1"]
	for ip in get_all_local_ipv4():
		var parts = ip.split(".")
		if parts.size() != 4:
			continue
		var o1 = int(parts[0])
		var o2 = int(parts[1])
		# Широковещательный адрес /24
		var b24 = "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not (b24 in targets):
			targets.append(b24)
		# Для 172.16-31.x.x и 10.x.x.x также /16
		if (o1 == 172 and o2 >= 16 and o2 <= 31) or o1 == 10:
			var b16 = "%s.%s.255.255" % [parts[0], parts[1]]
			if not (b16 in targets):
				targets.append(b16)
		# Для Radmin (26.x), Hamachi (25.x) и 10.x также /8
		if o1 == 26 or o1 == 25 or o1 == 10:
			var b8 = "%s.255.255.255" % parts[0]
			if not (b8 in targets):
				targets.append(b8)
	return targets

func _create_broadcaster_sockets() -> Array[PacketPeerUDP]:
	var sockets: Array[PacketPeerUDP] = []
	# 1. Основной сокет без жесткой привязки к интерфейсу
	var default_sock = PacketPeerUDP.new()
	if default_sock.bind(0) == OK:
		default_sock.set_broadcast_enabled(true)
		sockets.append(default_sock)
		
	# 2. По одному сокету на каждый локальный/VPN интерфейс, чтобы Windows точно отправлял пакеты в VPN!
	for ip in get_all_local_ipv4():
		var iface_sock = PacketPeerUDP.new()
		if iface_sock.bind(0, ip) == OK:
			iface_sock.set_broadcast_enabled(true)
			sockets.append(iface_sock)
	return sockets

func _start_lan_broadcaster() -> void:
	_stop_lan_broadcaster()
	lan_broadcasters = _create_broadcaster_sockets()
	_broadcast_lan_beacon()

func _stop_lan_broadcaster() -> void:
	for sock in lan_broadcasters:
		if sock:
			sock.close()
	lan_broadcasters.clear()

func _build_beacon_payload() -> Dictionary:
	return {
		"proto": "PRIPYAT_LOBBY_V2",
		"lobby_uid": lobby_uid,
		"name": lobby_title,
		"host": local_player_name,
		"players": players.size(),
		"max_players": MAX_PLAYERS,
		"port": current_port,
		"code": room_code,
		"local_code": local_room_code,
		"ips": get_all_local_ipv4(),
		"ext_ip": external_ip,
		"class": local_class_id
	}

func _broadcast_lan_beacon() -> void:
	if not is_host or lan_broadcasters.size() == 0:
		return
	var data = JSON.stringify(_build_beacon_payload()).to_utf8_buffer()
	var targets = _get_broadcast_targets()
	
	for sock in lan_broadcasters:
		if not sock:
			continue
		for target_ip in targets:
			for dport in DISCOVERY_PORTS:
				sock.set_dest_address(target_ip, dport)
				sock.put_packet(data)

func _send_unicast_beacon(target_ip: String, target_port: int) -> void:
	if not is_host or target_ip == "" or target_port <= 0:
		return
	var data = JSON.stringify(_build_beacon_payload()).to_utf8_buffer()
	if lan_broadcasters.size() > 0 and lan_broadcasters[0]:
		lan_broadcasters[0].set_dest_address(target_ip, target_port)
		lan_broadcasters[0].put_packet(data)
	else:
		var tmp = PacketPeerUDP.new()
		tmp.set_dest_address(target_ip, target_port)
		tmp.put_packet(data)
		tmp.close()

## Активный запрос (клиент рассылает ping всем хостам в LAN и VPN)
func send_discovery_probe() -> void:
	if lan_listener_port <= 0:
		_start_lan_listener()
	if lan_listener_port <= 0:
		return
		
	var probe = {
		"proto": "PRIPYAT_DISCOVER",
		"reply_port": lan_listener_port
	}
	var data = JSON.stringify(probe).to_utf8_buffer()
	var targets = _get_broadcast_targets()
	var temp_sockets = _create_broadcaster_sockets()
	
	for sock in temp_sockets:
		for target_ip in targets:
			for dport in DISCOVERY_PORTS:
				sock.set_dest_address(target_ip, dport)
				sock.put_packet(data)
		sock.close()

func _poll_lan_listener() -> void:
	if not lan_listener:
		return
	var changed = false
	var now = Time.get_ticks_msec()
	
	while lan_listener.get_available_packet_count() > 0:
		var sender_ip = lan_listener.get_packet_ip()
		var raw = lan_listener.get_packet().get_string_from_utf8()
		var data = JSON.parse_string(raw)
		if typeof(data) != TYPE_DICTIONARY:
			continue
			
		var proto = str(data.get("proto", ""))
		# Запрос от клиента в поиске: хост немедленно отвечает прямым unicast-пакетом
		if proto == "PRIPYAT_DISCOVER":
			if is_host and is_multiplayer_active():
				var reply_port = int(data.get("reply_port", 0))
				if reply_port > 0:
					_send_unicast_beacon(sender_ip, reply_port)
			continue
			
		# Игнорируем собственное лобби хоста (защита от эхо на всех интерфейсах)
		var inc_uid = str(data.get("lobby_uid", ""))
		var inc_code = str(data.get("code", ""))
		if is_host:
			if inc_uid != "" and inc_uid == lobby_uid:
				continue
			if sender_ip == "127.0.0.1" or sender_ip in local_ips or (inc_code != "" and inc_code == room_code):
				continue
				
		var port = int(data.get("port", DEFAULT_PORT))
		var dedup_key = inc_uid if inc_uid != "" else ("%s:%d" % [sender_ip, port])
		
		# Если пакет пришел с 127.0.0.1, оставляем его только если нет более точного адреса
		if lan_discovered_lobbies.has(dedup_key):
			var existing_ip = str(lan_discovered_lobbies[dedup_key].get("ip", ""))
			if sender_ip == "127.0.0.1" and existing_ip != "" and existing_ip != "127.0.0.1":
				lan_discovered_lobbies[dedup_key]["last_seen"] = now
				continue
				
		data["ip"] = sender_ip
		data["last_seen"] = now
		data["type"] = "LAN / VPN (%s)" % sender_ip
		lan_discovered_lobbies[dedup_key] = data
		changed = true
		
	# Удаляем устаревшие LAN-лобби (не отвечающие > 6 сек)
	var lan_expired = []
	for k in lan_discovered_lobbies:
		if now - lan_discovered_lobbies[k].get("last_seen", 0) > 6000:
			lan_expired.append(k)
	for k in lan_expired:
		lan_discovered_lobbies.erase(k)
		changed = true
		
	# Удаляем устаревшие Интернет-лобби (не обновлялись > 45 сек)
	var inet_expired = []
	for k in internet_discovered_lobbies:
		if now - internet_discovered_lobbies[k].get("last_seen", 0) > 45000:
			inet_expired.append(k)
	for k in inet_expired:
		internet_discovered_lobbies.erase(k)
		changed = true
		
	if changed:
		lobbies_discovered_updated.emit(get_all_discovered_lobbies())

func get_all_discovered_lobbies() -> Array:
	var result: Array = []
	var seen_uids: Dictionary = {}
	
	# 1. Сначала прямые LAN/VPN лобби (минимальный пинг, не нужен внешний IP)
	for lobby in lan_discovered_lobbies.values():
		var uid = str(lobby.get("lobby_uid", ""))
		if uid != "":
			seen_uids[uid] = true
		result.append(lobby)
		
	# 2. Затем интернет-лобби с мастер-сервера (исключая дубликаты уже найденных в LAN)
	for lobby in internet_discovered_lobbies.values():
		var uid = str(lobby.get("lobby_uid", ""))
		if uid != "" and seen_uids.has(uid):
			continue
		result.append(lobby)
		
	return result

## Выбирает оптимальный IP для подключения к обнаруженному лобби (избегая Hairpin NAT)
func resolve_best_ip_for_lobby(lobby: Dictionary) -> String:
	var primary_ip = str(lobby.get("ip", "127.0.0.1"))
	var candidate_ips = lobby.get("ips", [])
	if typeof(candidate_ips) == TYPE_ARRAY and candidate_ips.size() > 0:
		var my_ips = get_all_local_ipv4()
		for remote_ip_var in candidate_ips:
			var r_ip = str(remote_ip_var)
			for my_ip in my_ips:
				if _are_in_same_subnet(my_ip, r_ip):
					return r_ip
	return primary_ip

static func _are_in_same_subnet(ip_a: String, ip_b: String) -> bool:
	var pa = ip_a.split(".")
	var pb = ip_b.split(".")
	if pa.size() != 4 or pb.size() != 4:
		return false
	# Radmin 26.x / Hamachi 25.x используют маску /8
	if (pa[0] == "26" and pb[0] == "26") or (pa[0] == "25" and pb[0] == "25"):
		return true
	# Стандартные LAN/VPN подсети /24
	return pa[0] == pb[0] and pa[1] == pb[1] and pa[2] == pb[2]

# ==============================================================================
# МАСТЕР-СЕРВЕР (ОБЩИЙ СПИСОК СЕРВЕРОВ В ИНТЕРНЕТЕ)
# ==============================================================================

func register_master_server(title: String, port: int) -> void:
	if master_server_url == "":
		return
	# Используем безопасный ASCII-идентификатор для URL
	master_lobby_id = "lobby_%d_%04x" % [int(Time.get_unix_time_from_system()), randi_range(0, 0xFFFF)]
	master_lobby_token = ""
	var http = HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	var url = master_server_url.trim_suffix("/") + "/api/lobbies"
	var payload = {
		"id": master_lobby_id,
		"lobby_uid": lobby_uid,
		"name": title,
		"host": local_player_name,
		"ip": external_ip if (external_ip != "" and is_public_ipv4(external_ip)) else local_ip,
		"ips": get_all_local_ipv4(),
		"port": port,
		"code": room_code,
		"local_code": local_room_code,
		"players": players.size(),
		"max_players": MAX_PLAYERS
	}
	var body = JSON.stringify(payload)
	http.request_completed.connect(func(res: int, code: int, _h: PackedStringArray, resp_body: PackedByteArray):
		if res == HTTPRequest.RESULT_SUCCESS and (code == 200 or code == 201):
			master_registered = true
			var parsed = JSON.parse_string(resp_body.get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY:
				master_lobby_token = str(parsed.get("token", ""))
		http.queue_free()
	)
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)

func _send_master_heartbeat(include_network_info: bool = false) -> void:
	if master_server_url == "" or master_lobby_id == "":
		return
	var http = HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	var url = "%s/api/lobbies/%s/heartbeat" % [master_server_url.trim_suffix("/"), master_lobby_id.uri_encode()]
	var payload: Dictionary = { "players": players.size() }
	if include_network_info:
		payload["code"] = room_code
		payload["ips"] = get_all_local_ipv4()
		if external_ip != "" and is_public_ipv4(external_ip):
			payload["ip"] = external_ip
			
	var headers: PackedStringArray = ["Content-Type: application/json"]
	if master_lobby_token != "":
		headers.append("Authorization: Bearer %s" % master_lobby_token)
	http.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray):
		http.queue_free()
	)
	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

func unregister_master_server() -> void:
	if master_server_url == "" or master_lobby_id == "":
		return
	var http = HTTPRequest.new()
	http.timeout = 3.0
	add_child(http)
	var url = "%s/api/lobbies/%s" % [master_server_url.trim_suffix("/"), master_lobby_id.uri_encode()]
	var headers: PackedStringArray = []
	if master_lobby_token != "":
		headers.append("Authorization: Bearer %s" % master_lobby_token)
	http.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray):
		http.queue_free()
	)
	http.request(url, headers, HTTPClient.METHOD_DELETE)
	master_registered = false
	master_lobby_id = ""
	master_lobby_token = ""

func refresh_master_server_lobbies() -> void:
	if master_server_url == "":
		return
	var http = HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	var url = master_server_url.trim_suffix("/") + "/api/lobbies"
	http.request_completed.connect(func(res: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		if res == HTTPRequest.RESULT_SUCCESS and code == 200:
			var data = JSON.parse_string(body.get_string_from_utf8())
			if typeof(data) == TYPE_ARRAY:
				var now = Time.get_ticks_msec()
				internet_discovered_lobbies.clear()
				for lobby in data:
					if typeof(lobby) == TYPE_DICTIONARY:
						var uid = str(lobby.get("lobby_uid", lobby.get("id", "")))
						if is_host and uid != "" and uid == lobby_uid:
							continue
						var key = uid if uid != "" else ("%s:%d" % [lobby.get("ip", ""), lobby.get("port", DEFAULT_PORT)])
						lobby["type"] = "ИНТЕРНЕТ"
						lobby["last_seen"] = now
						internet_discovered_lobbies[key] = lobby
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
	lobby_uid = "%d_%04x" % [Time.get_ticks_msec(), randi_range(0, 0xFFFF)]
	
	refresh_local_network_info()
		
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
	
	# Если внешний IP еще не определился, попробуем еще раз
	if external_ip == "":
		_detect_external_ip_async(0)
	
	# Запуск UPnP проброса в фоне
	if use_upnp:
		start_upnp_async(port)
	else:
		upnp_status_text = "UPnP отключен (используется LAN / VPN / ручной проброс)"
		upnp_status_changed.emit(upnp_status_text, false)
		
	# Запуск мульти-интерфейсного LAN / VPN маяка
	_start_lan_broadcaster()
	
	# Регистрация на мастер-сервере (если задан)
	if master_server_url != "":
		register_master_server(lobby_title, port)
		
	connection_status_changed.emit("Лобби открыто! Код: %s (VPN-код: %s). Ожидание бойцов..." % [room_code, local_room_code], false)
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
	connection_status_changed.emit("⏳ Подключение к [%s:%d]... Ожидание ответа сервера" % [target_ip, target_port], false)
	return OK

## Отключение от сети
func disconnect_game() -> void:
	cleanup_upnp(current_port)
	if is_host:
		_stop_lan_broadcaster()
		unregister_master_server()
		
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		
	_clear_multiplayer_signals()
	is_multiplayer = false
	is_host = false
	lobby_uid = ""
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

func _on_peer_connected(_peer_id: int) -> void:
	if not is_host:
		return

func _on_peer_disconnected(peer_id: int) -> void:
	if is_host:
		if players.has(peer_id):
			var left_name = players[peer_id].get("name", "Игрок")
			players.erase(peer_id)
			player_left_lobby.emit(peer_id)
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
	connection_status_changed.emit("Ошибка подключения: хост не отвечает. Проверьте VPN (Radmin/Hamachi), брандмауэр или порт %d UDP." % current_port, true)
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
		
	var remote_id = multiplayer.get_remote_sender_id()
	if remote_id != 0:
		peer_id = remote_id
		
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
	player_joined_lobby.emit(players[peer_id])
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
	var remote_id = multiplayer.get_remote_sender_id()
	if remote_id != 0:
		peer_id = remote_id
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
	var remote_id = multiplayer.get_remote_sender_id()
	if remote_id != 0:
		peer_id = remote_id
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
	var remote_id = multiplayer.get_remote_sender_id()
	if remote_id != 0 and players.has(remote_id):
		sender_name = players[remote_id].get("name", sender_name)
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
# СИНХРОНИЗАЦИЯ ЭКОНОМИКИ И ЧИСТОТЫ
# ==============================================================================

func sync_rubles_across_squad(new_rubles: int, delta: int) -> void:
	if is_multiplayer_active() and is_host:
		rpc_sync_rubles.rpc(new_rubles, delta)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_rubles(new_rubles: int, _delta: int) -> void:
	var remote_id = multiplayer.get_remote_sender_id()
	if remote_id == 1 or is_host:
		if GameState and GameState.karbovantsi != new_rubles:
			GameState._is_syncing_network = true
			GameState.karbovantsi = new_rubles
			GameState._is_syncing_network = false

func sync_cleanliness_across_squad(cleaned: int, total: int, pct: float) -> void:
	if is_multiplayer_active() and is_host:
		rpc_sync_cleanliness.rpc(cleaned, total, pct)

@rpc("authority", "call_remote", "reliable")
func rpc_sync_cleanliness(cleaned: int, total: int, pct: float) -> void:
	var remote_id = multiplayer.get_remote_sender_id()
	if remote_id == 1 or is_host:
		if GameState:
			GameState._is_syncing_network = true
			GameState.cleaned_items = cleaned
			GameState.total_items = total
			GameState._is_syncing_network = false
		EventBus.cleanliness_updated.emit(cleaned, total, pct)
