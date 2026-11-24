class_name MultiplayerLobby
extends Control

## Экран лобби и сетевого браузера ликвидаторов (до 4 игроков).
## Обеспечивает:
## 1. Полноценную игру через интернет по Коду комнаты (Room Code) и внешнему IP.
## 2. Автоматический проброс портов UPnP для прямого соединения без настройки роутера.
## 3. Автопоиск комнат в локальной сети / Radmin VPN / Hamachi.
## 4. Браузер открытых серверов (Master Server).
## 5. Копирование кода приглашения для друзей в один клик.

@onready var connection_view: Control = $MarginContainer/ConnectionView
@onready var lobby_room_view: Control = $MarginContainer/LobbyRoomView

# Поля экрана подключения
@onready var name_input: LineEdit = $MarginContainer/ConnectionView/VBox/TopRow/NameBox/NameInput
@onready var direct_code_input: LineEdit = $MarginContainer/ConnectionView/VBox/TabContainer/DirectTab/VBox/CodeHBox/CodeInput
@onready var host_title_input: LineEdit = $MarginContainer/ConnectionView/VBox/TabContainer/HostTab/VBox/TitleHBox/TitleInput
@onready var host_port_input: LineEdit = $MarginContainer/ConnectionView/VBox/TabContainer/HostTab/VBox/PortHBox/PortInput
@onready var upnp_checkbox: CheckBox = $MarginContainer/ConnectionView/VBox/TabContainer/HostTab/VBox/UPnPCheck
@onready var status_label: Label = $MarginContainer/ConnectionView/VBox/StatusLabel

# Браузер серверов
@onready var scroll_container: ScrollContainer = $MarginContainer/ConnectionView/VBox/TabContainer/BrowserTab/VBox/Scroll
@onready var lobbies_list_container: VBoxContainer = $MarginContainer/ConnectionView/VBox/TabContainer/BrowserTab/VBox/Scroll/LobbiesList
@onready var no_lobbies_label: Label = $MarginContainer/ConnectionView/VBox/TabContainer/BrowserTab/VBox/NoLobbiesLabel

# Поля экрана комнаты лобби
@onready var room_info_label: Label = $MarginContainer/LobbyRoomView/VBox/Header/RoomInfoLabel
@onready var room_code_label: Label = $MarginContainer/LobbyRoomView/VBox/NetworkDetails/HBox/CodeValueLabel
@onready var ext_ip_label: Label = $MarginContainer/LobbyRoomView/VBox/NetworkDetails/HBox/ExtIPValueLabel
@onready var local_ip_label: Label = $MarginContainer/LobbyRoomView/VBox/NetworkDetails/HBox/LocalIPValueLabel
@onready var upnp_badge_label: Label = $MarginContainer/LobbyRoomView/VBox/NetworkDetails/HBox/UPnPStatusLabel
@onready var copy_invite_button: Button = $MarginContainer/LobbyRoomView/VBox/NetworkDetails/CopyInviteButton

@onready var cards_container: HBoxContainer = $MarginContainer/LobbyRoomView/VBox/CardsContainer
@onready var chat_log: RichTextLabel = $MarginContainer/LobbyRoomView/VBox/ChatSection/ChatLog
@onready var chat_input: LineEdit = $MarginContainer/LobbyRoomView/VBox/ChatSection/HBox/ChatInput
@onready var ready_button: Button = $MarginContainer/LobbyRoomView/VBox/BottomBar/ReadyButton
@onready var start_game_button: Button = $MarginContainer/LobbyRoomView/VBox/BottomBar/StartGameButton

# Карточки слотов (4 слота)
var slot_cards: Array[PanelContainer] = []
var selected_class: String = "cleaner"

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_init_slot_card_references()
	
	if NetworkManager:
		NetworkManager.lobby_updated.connect(_on_lobby_updated)
		NetworkManager.chat_message_received.connect(_on_chat_message_received)
		NetworkManager.connection_status_changed.connect(_on_connection_status_changed)
		NetworkManager.lobbies_discovered_updated.connect(_on_lobbies_discovered_updated)
		NetworkManager.upnp_status_changed.connect(_on_upnp_status_changed)
		NetworkManager.external_ip_detected.connect(_on_external_ip_detected)
		
		name_input.text = NetworkManager.local_player_name
		selected_class = NetworkManager.local_class_id
	else:
		name_input.text = "Ликвидатор-86"
		
	_show_connection_view()
	_refresh_lobbies_list()

func _init_slot_card_references() -> void:
	slot_cards.clear()
	for i in range(1, 5):
		var card = cards_container.get_node_or_null("SlotCard_%d" % i) as PanelContainer
		if card:
			slot_cards.append(card)

func _show_connection_view() -> void:
	connection_view.visible = true
	lobby_room_view.visible = false

func _show_lobby_room_view() -> void:
	connection_view.visible = false
	lobby_room_view.visible = true
	_update_lobby_room_ui()
	_update_network_details_header()

# ==============================================================================
# ОБРАБОТЧИКИ ЭКРАНА ПОДКЛЮЧЕНИЯ
# ==============================================================================

## Одиночный запуск игры без сети
func _on_solo_play_pressed() -> void:
	var p_name = name_input.text.strip_edges()
	if p_name == "": p_name = "Ликвидатор"
	if NetworkManager:
		NetworkManager.disconnect_game()
		NetworkManager.local_player_name = p_name
		NetworkManager.local_class_id = selected_class
	if GameState:
		GameState.set_class(selected_class)
	get_tree().change_scene_to_file("res://scenes/world/SosnovkaVillage.tscn")

## Создание лобби (Хост)
func _on_host_lobby_pressed() -> void:
	var p_name = name_input.text.strip_edges()
	var title = host_title_input.text.strip_edges()
	if title == "": title = "Смена Сосновки"
	var port = int(host_port_input.text.strip_edges())
	if port <= 0: port = NetworkManager.DEFAULT_PORT
	var use_upnp = upnp_checkbox.button_pressed if upnp_checkbox else true
	
	if NetworkManager:
		var err = NetworkManager.host_game(port, p_name, selected_class, title, use_upnp)
		if err == OK:
			_show_lobby_room_view()
			_add_chat_entry("ШТАБ", "Лобби отряда создано! Код комнаты: %s" % NetworkManager.room_code)

## Прямое подключение по Коду комнаты или IP:PORT
func _on_direct_connect_pressed() -> void:
	var target = direct_code_input.text.strip_edges()
	if target == "":
		_on_connection_status_changed("Введите код комнаты (ZONE-...) или IP:порт сервера!", true)
		return
		
	var p_name = name_input.text.strip_edges()
	if NetworkManager:
		var err = NetworkManager.join_game(target, NetworkManager.DEFAULT_PORT, p_name, selected_class)
		if err == OK:
			_show_lobby_room_view()

## Обновление списка доступных серверов
func _on_refresh_lobbies_pressed() -> void:
	_refresh_lobbies_list()

func _refresh_lobbies_list() -> void:
	if NetworkManager:
		NetworkManager.refresh_master_server_lobbies()
		_on_lobbies_discovered_updated(NetworkManager.get_all_discovered_lobbies())

func _on_lobbies_discovered_updated(lobbies: Array) -> void:
	if not lobbies_list_container:
		return
		
	for child in lobbies_list_container.get_children():
		child.queue_free()
		
	if lobbies.size() == 0:
		if no_lobbies_label: no_lobbies_label.visible = true
		if scroll_container: scroll_container.visible = false
		return
		
	if no_lobbies_label: no_lobbies_label.visible = false
	if scroll_container: scroll_container.visible = true
	
	for lobby in lobbies:
		var row = _create_lobby_row(lobby)
		lobbies_list_container.add_child(row)

func _create_lobby_row(lobby: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.15, 0.13, 0.9)
	style.set_corner_radius_all(4)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.25, 0.4, 0.3)
	panel.add_theme_stylebox_override("panel", style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	margin.add_child(hbox)
	
	# Название и хост
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l_name = Label.new()
	l_name.text = lobby.get("name", "Смена ликвидации")
	l_name.add_theme_font_size_override("font_size", 16)
	l_name.modulate = Color(0.95, 0.85, 0.3)
	info_vbox.add_child(l_name)
	
	var l_sub = Label.new()
	var host = lobby.get("host", "Неизвестно")
	var l_type = lobby.get("type", "LAN")
	l_sub.text = "Командир: %s  |  Сеть: [%s]" % [host, l_type]
	l_sub.add_theme_font_size_override("font_size", 12)
	l_sub.modulate = Color(0.7, 0.75, 0.7)
	info_vbox.add_child(l_sub)
	hbox.add_child(info_vbox)
	
	# Количество игроков
	var players_lbl = Label.new()
	var p_cur = lobby.get("players", 1)
	var p_max = lobby.get("max_players", 4)
	players_lbl.text = "Бойцы: %d / %d" % [p_cur, p_max]
	players_lbl.add_theme_font_size_override("font_size", 14)
	players_lbl.modulate = Color(0.4, 0.9, 0.6)
	hbox.add_child(players_lbl)
	
	# Кнопка входа
	var join_btn = Button.new()
	join_btn.text = "➔ ВОЙТИ"
	join_btn.custom_minimum_size = Vector2(100, 36)
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.18, 0.32, 0.22)
	btn_style.set_corner_radius_all(4)
	join_btn.add_theme_stylebox_override("normal", btn_style)
	
	var ip = lobby.get("ip", "127.0.0.1")
	var port = lobby.get("port", NetworkManager.DEFAULT_PORT)
	join_btn.pressed.connect(func():
		var p_name = name_input.text.strip_edges()
		if NetworkManager:
			NetworkManager.join_game(ip, port, p_name, selected_class)
			_show_lobby_room_view()
	)
	hbox.add_child(join_btn)
	
	return panel

func _on_connection_status_changed(text: String, is_error: bool) -> void:
	status_label.text = text
	status_label.modulate = Color(1.0, 0.35, 0.35) if is_error else Color(0.4, 0.95, 0.6)

func _on_upnp_status_changed(text: String, is_act: bool) -> void:
	if upnp_badge_label:
		upnp_badge_label.text = text
		upnp_badge_label.modulate = Color(0.3, 1.0, 0.4) if is_act else Color(1.0, 0.8, 0.3)

func _on_external_ip_detected(_ip: String, _code: String) -> void:
	_update_network_details_header()

# ==============================================================================
# ОБРАБОТЧИКИ ЭКРАНА КОМНАТЫ ЛОББИ
# ==============================================================================

func _on_lobby_updated(players: Dictionary) -> void:
	if not lobby_room_view.visible and players.size() > 0:
		_show_lobby_room_view()
	_update_lobby_room_ui()
	_update_network_details_header()

func _update_network_details_header() -> void:
	if not NetworkManager:
		return
	if room_code_label:
		room_code_label.text = NetworkManager.room_code if NetworkManager.room_code != "" else "Определение..."
	if ext_ip_label:
		ext_ip_label.text = "%s:%d" % [NetworkManager.external_ip if NetworkManager.external_ip != "" else "Не определен", NetworkManager.current_port]
	if local_ip_label:
		local_ip_label.text = "%s:%d" % [NetworkManager.local_ip, NetworkManager.current_port]
	if upnp_badge_label:
		upnp_badge_label.text = NetworkManager.upnp_status_text
		upnp_badge_label.modulate = Color(0.3, 1.0, 0.4) if NetworkManager.upnp_active else Color(1.0, 0.8, 0.3)

## Копирование кода приглашения для друзей в буфер обмена
func _on_copy_invite_pressed() -> void:
	if not NetworkManager:
		return
	var code = NetworkManager.room_code
	var ext_ip = "%s:%d" % [NetworkManager.external_ip, NetworkManager.current_port]
	var loc_ip = "%s:%d" % [NetworkManager.local_ip, NetworkManager.current_port]
	
	var invite_text = "Вступай в отряд ликвидации PRIPYAT!\nКод комнаты: %s\nВнешний IP: %s\nЛокальный IP (LAN/Radmin/Hamachi): %s" % [code, ext_ip, loc_ip]
	DisplayServer.clipboard_set(invite_text)
	
	if copy_invite_button:
		var orig = copy_invite_button.text
		copy_invite_button.text = "✓ СКОПИРОВАНО В БУФЕР!"
		copy_invite_button.modulate = Color(0.3, 1.0, 0.4)
		get_tree().create_timer(1.8).timeout.connect(func():
			if is_instance_valid(copy_invite_button):
				copy_invite_button.text = orig
				copy_invite_button.modulate = Color.WHITE
		)

func _update_lobby_room_ui() -> void:
	if not NetworkManager:
		return
		
	var players = NetworkManager.players
	var is_host = NetworkManager.is_host
	var my_id = multiplayer.get_unique_id() if NetworkManager.is_multiplayer_active() else 1
	
	var role_str = "КОМАНДИР [ХОСТ]" if is_host else "БОЕЦ [КЛИЕНТ]"
	room_info_label.text = "СМЕНА ДЕЗАКТИВАЦИИ: %s | Статус: %s | Бойцов в отряде: %d / 4" % [NetworkManager.lobby_title, role_str, players.size()]
	
	start_game_button.visible = is_host
	start_game_button.disabled = not NetworkManager.can_start_game()
	
	if players.has(my_id):
		var my_ready = players[my_id].get("ready", false)
		ready_button.text = "✓ ГОТОВ К ВЫСАДКЕ" if my_ready else "⏳ НЕ ГОТОВ"
		ready_button.modulate = Color(0.3, 1.0, 0.4) if my_ready else Color(1.0, 0.8, 0.3)
	
	var slot_to_player: Dictionary = {}
	for pid in players:
		var p = players[pid]
		var s = p.get("slot", 0)
		slot_to_player[s] = p
		
	for s_idx in range(4):
		if s_idx >= slot_cards.size():
			continue
		var card = slot_cards[s_idx]
		_render_slot_card(card, s_idx, slot_to_player.get(s_idx, null))

func _render_slot_card(card: PanelContainer, slot_idx: int, p_data: Variant) -> void:
	var slot_title = card.get_node_or_null("VBox/SlotTitle") as Label
	var name_lbl = card.get_node_or_null("VBox/PlayerName") as Label
	var class_lbl = card.get_node_or_null("VBox/PlayerClass") as Label
	var perk_lbl = card.get_node_or_null("VBox/ClassPerk") as Label
	var status_lbl = card.get_node_or_null("VBox/ReadyBadge") as Label
	
	if not p_data:
		if slot_title: slot_title.text = "СЛОТ #%d" % (slot_idx + 1)
		if name_lbl:
			name_lbl.text = "[ Свободно ]"
			name_lbl.modulate = Color(0.5, 0.5, 0.5)
		if class_lbl: class_lbl.text = "Ожидание ликвидатора..."
		if perk_lbl: perk_lbl.text = "—"
		if status_lbl:
			status_lbl.text = "СВОБОДЕН"
			status_lbl.modulate = Color(0.4, 0.4, 0.4)
		card.modulate = Color(0.7, 0.7, 0.7, 0.5)
		return
		
	card.modulate = Color.WHITE
	var is_host_player = p_data.get("is_host", false)
	var p_name = p_data.get("name", "Ликвидатор")
	var c_id = p_data.get("class_id", "cleaner")
	var is_ready = p_data.get("ready", false)
	
	if slot_title:
		slot_title.text = "СЛОТ #%d %s" % [(slot_idx + 1), "★ [КОМАНДИР]" if is_host_player else ""]
		slot_title.modulate = Color(1.0, 0.85, 0.3) if is_host_player else Color(0.7, 0.85, 1.0)
		
	if name_lbl:
		name_lbl.text = p_name
		name_lbl.modulate = Color.WHITE
		
	var c_info = GameState.CLASS_DEFINITIONS.get(c_id, {}) if GameState else {}
	var c_name = c_info.get("name", "Чистильщик")
	var c_perk = c_info.get("perk", "")
	
	if class_lbl:
		class_lbl.text = "[ %s ]" % c_name.to_upper()
		class_lbl.modulate = _get_class_color(c_id)
		
	if perk_lbl:
		perk_lbl.text = c_perk
		
	if status_lbl:
		if is_host_player or is_ready:
			status_lbl.text = "● ГОТОВ К БОЮ"
			status_lbl.modulate = Color(0.3, 1.0, 0.4)
		else:
			status_lbl.text = "⏳ ВЫБИРАЕТ СНАРЯЖЕНИЕ"
			status_lbl.modulate = Color(1.0, 0.8, 0.2)

func _get_class_color(c_id: String) -> Color:
	match c_id:
		"cleaner": return Color(0.3, 0.9, 0.6)
		"soldier": return Color(0.95, 0.4, 0.3)
		"medic": return Color(0.3, 0.8, 1.0)
		"engineer": return Color(1.0, 0.75, 0.2)
	return Color.WHITE

# ==============================================================================
# СМЕНА КЛАССА В ЛОББИ
# ==============================================================================

func _on_select_class_pressed(class_id: String) -> void:
	selected_class = class_id
	if NetworkManager:
		NetworkManager.set_local_class(class_id)
	_update_lobby_room_ui()

func _on_class_cleaner_pressed() -> void: _on_select_class_pressed("cleaner")
func _on_class_soldier_pressed() -> void: _on_select_class_pressed("soldier")
func _on_class_medic_pressed() -> void: _on_select_class_pressed("medic")
func _on_class_engineer_pressed() -> void: _on_select_class_pressed("engineer")

# ==============================================================================
# ГОТОВНОСТЬ, СТАРТ И ВЫХОД
# ==============================================================================

func _on_ready_button_pressed() -> void:
	if NetworkManager:
		NetworkManager.toggle_local_ready()

func _on_start_game_pressed() -> void:
	if NetworkManager and NetworkManager.is_host:
		NetworkManager.host_start_game("res://scenes/world/SosnovkaVillage.tscn")

func _on_leave_lobby_pressed() -> void:
	if NetworkManager:
		NetworkManager.disconnect_game()
	_show_connection_view()

# ==============================================================================
# РАДИОСВЯЗЬ / ЧАТ ЛОББИ
# ==============================================================================

func _on_send_chat_pressed() -> void:
	var msg = chat_input.text.strip_edges()
	if msg == "": return
	chat_input.text = ""
	if NetworkManager:
		NetworkManager.send_chat_message(msg)

func _on_chat_input_text_submitted(_new_text: String) -> void:
	_on_send_chat_pressed()

func _on_chat_message_received(sender_name: String, message: String) -> void:
	_add_chat_entry(sender_name, message)

func _add_chat_entry(sender: String, message: String) -> void:
	var color = "#66ccff"
	if sender == "ШТАБ": color = "#ffcc00"
	elif sender == NetworkManager.local_player_name: color = "#44ff88"
	
	chat_log.append_text("[color=%s][b][%s][/b][/color]: %s\n" % [color, sender, message])
