#!/usr/bin/env python3
"""
PRIPYAT CLEANER — Public Master Server (Список открытых лобби)
Легковесный и защищенный сервер координации открытых лобби через интернет.
Не требует внешних библиотек (работает на чистом Python 3 standard library).

Запуск:
    python master_server.py [порт]
По умолчанию порт: 8080 (или $PORT на хостингах типа Render / Railway)
"""

import json
import os
import secrets
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

PORT = int(os.environ.get("PORT", sys.argv[1] if len(sys.argv) > 1 else 8080))
LOBBY_TIMEOUT_SECONDS = 30
MAX_LOBBIES = 1000

# Потокобезопасное хранилище активных комнат
lobbies_lock = threading.Lock()
active_lobbies = {}

def clean_expired_lobbies():
    now = time.time()
    with lobbies_lock:
        expired = [lid for lid, item in active_lobbies.items() if now - item["last_heartbeat"] > LOBBY_TIMEOUT_SECONDS]
        for lid in expired:
            del active_lobbies[lid]

class MasterServerHandler(BaseHTTPRequestHandler):
    def _send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")

    def do_OPTIONS(self):
        self.send_response(200)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self):
        clean_expired_lobbies()
        clean_path = self.path.split("?")[0].rstrip("/")
        
        if clean_path == "/api/lobbies":
            with lobbies_lock:
                lobby_list = [item["data"] for item in active_lobbies.values()]
            response_data = json.dumps(lobby_list, ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(response_data)
        elif clean_path == "" or clean_path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"PRIPYAT Master Server OK")
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        clean_expired_lobbies()
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length > 65536: # Защита от гигантских пейлоадов (64 KB max)
            self.send_response(413)
            self.end_headers()
            return

        body = self.rfile.read(content_length) if content_length > 0 else b"{}"
        try:
            data = json.loads(body.decode("utf-8"))
        except Exception:
            data = {}

        clean_path = self.path.split("?")[0].rstrip("/")

        # 1. Регистрация нового лобби: POST /api/lobbies
        if clean_path == "/api/lobbies":
            with lobbies_lock:
                if len(active_lobbies) >= MAX_LOBBIES:
                    self.send_response(429)
                    self.end_headers()
                    self.wfile.write(b'{"error":"Lobby capacity reached"}')
                    return

            lobby_id = str(data.get("id", f"lobby_{int(time.time()*1000)}"))[:64]
            # Валидация и санитизация
            safe_name = str(data.get("name", "Смена ликвидаторов"))[:64]
            safe_host = str(data.get("host", "Ликвидатор"))[:32]
            safe_code = str(data.get("code", ""))[:32]
            try:
                safe_port = int(data.get("port", 7777))
                if not (1 <= safe_port <= 65535):
                    safe_port = 7777
            except (ValueError, TypeError):
                safe_port = 7777

            client_ip = self.client_address[0]
            provided_ip = str(data.get("ip", "")).strip()
            if not provided_ip or provided_ip in ["127.0.0.1", "localhost", "0.0.0.0"]:
                provided_ip = client_ip

            token = secrets.token_hex(16)
            sanitized_data = {
                "id": lobby_id,
                "name": safe_name,
                "host": safe_host,
                "ip": provided_ip,
                "port": safe_port,
                "code": safe_code,
                "players": int(data.get("players", 1)),
                "max_players": int(data.get("max_players", 4))
            }

            with lobbies_lock:
                active_lobbies[lobby_id] = {
                    "data": sanitized_data,
                    "token": token,
                    "client_ip": client_ip,
                    "last_heartbeat": time.time()
                }

            print(f"[+] Лобби зарегистрировано: {safe_name} ({provided_ip}:{safe_port}) [ID: {lobby_id}]")
            self.send_response(201)
            self.send_header("Content-Type", "application/json")
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "id": lobby_id, "token": token}).encode("utf-8"))

        # 2. Heartbeat лобби: POST /api/lobbies/<id>/heartbeat
        elif clean_path.startswith("/api/lobbies/") and clean_path.endswith("/heartbeat"):
            parts = clean_path.split("/")
            if len(parts) >= 5:
                lobby_id = parts[3]
                with lobbies_lock:
                    if lobby_id in active_lobbies:
                        lobby = active_lobbies[lobby_id]
                        # Проверяем токен или IP
                        auth_header = self.headers.get("Authorization", "")
                        token = auth_header.replace("Bearer ", "").strip()
                        if token == lobby["token"] or self.client_address[0] == lobby["client_ip"]:
                            lobby["last_heartbeat"] = time.time()
                            if "players" in data:
                                try:
                                    lobby["data"]["players"] = int(data["players"])
                                except (ValueError, TypeError):
                                    pass
                            self.send_response(200)
                            self._send_cors_headers()
                            self.end_headers()
                            self.wfile.write(b'{"status":"ok"}')
                            return
                self.send_response(403)
                self.end_headers()
            else:
                self.send_response(400)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()

    def do_DELETE(self):
        clean_expired_lobbies()
        clean_path = self.path.split("?")[0].rstrip("/")
        if clean_path.startswith("/api/lobbies/"):
            parts = clean_path.split("/")
            if len(parts) >= 4:
                lobby_id = parts[3]
                with lobbies_lock:
                    if lobby_id in active_lobbies:
                        lobby = active_lobbies[lobby_id]
                        auth_header = self.headers.get("Authorization", "")
                        token = auth_header.replace("Bearer ", "").strip()
                        # Разрешаем удаление только при совпадении токена или IP владельца
                        if token == lobby["token"] or self.client_address[0] == lobby["client_ip"]:
                            del active_lobbies[lobby_id]
                            print(f"[-] Лобби закрыто владельцем: {lobby_id}")
                            self.send_response(200)
                            self._send_cors_headers()
                            self.end_headers()
                            self.wfile.write(b'{"status":"deleted"}')
                            return
                        else:
                            self.send_response(403)
                            self._send_cors_headers()
                            self.end_headers()
                            self.wfile.write(b'{"error":"Forbidden: invalid token"}')
                            return
                    else:
                        self.send_response(404)
                        self.end_headers()
                        return
        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        pass

def run():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), MasterServerHandler)
    print(f"=== PRIPYAT Master Server (Защищенный) запущен на порту {PORT} ===")
    print("API Endpoints:")
    print("  GET    /api/lobbies               - Список активных комнат")
    print("  POST   /api/lobbies               - Регистрация лобби (возвращает secret_token)")
    print("  POST   /api/lobbies/:id/heartbeat - Обновление активности (по токену)")
    print("  DELETE /api/lobbies/:id           - Закрытие лобби (по токену)")
    print("Ожидание подключений...")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nСервер остановлен.")
        server.server_close()

if __name__ == "__main__":
    run()
