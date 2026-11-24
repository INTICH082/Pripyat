#!/usr/bin/env python3
"""
PRIPYAT CLEANER — Public Master Server (Список открытых лобби)
Легковесный сервер координации открытых лобби через интернет.
Не требует внешних библиотек (работает на чистом Python 3 standard library).

Запуск:
    python master_server.py [порт]
По умолчанию порт: 8080 (или $PORT на хостингах типа Render / Railway)
"""

import json
import os
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = int(os.environ.get("PORT", sys.argv[1] if len(sys.argv) > 1 else 8080))
LOBBY_TIMEOUT_SECONDS = 30

# Хранилище активных комнат: id -> { "data": dict, "last_heartbeat": float }
active_lobbies = {}

def clean_expired_lobbies():
    now = time.time()
    expired = [lid for lid, item in active_lobbies.items() if now - item["last_heartbeat"] > LOBBY_TIMEOUT_SECONDS]
    for lid in expired:
        del active_lobbies[lid]

class MasterServerHandler(BaseHTTPRequestHandler):
    def _send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(200)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self):
        clean_expired_lobbies()
        if self.path == "/api/lobbies" or self.path == "/api/lobbies/":
            lobby_list = [item["data"] for item in active_lobbies.values()]
            response_data = json.dumps(lobby_list).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(response_data)
        elif self.path == "/" or self.path == "/health":
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
        body = self.rfile.read(content_length) if content_length > 0 else b"{}"
        
        try:
            data = json.loads(body.decode("utf-8"))
        except Exception:
            data = {}

        # 1. Регистрация нового лобби: POST /api/lobbies
        if self.path == "/api/lobbies" or self.path == "/api/lobbies/":
            lobby_id = data.get("id", f"lobby_{int(time.time()*1000)}")
            data["id"] = lobby_id
            # Если хост не указал внешний IP, определяем адрес клиента
            client_ip = self.client_address[0]
            if not data.get("ip") or data.get("ip") in ["127.0.0.1", "localhost"]:
                data["ip"] = client_ip
                
            active_lobbies[lobby_id] = {
                "data": data,
                "last_heartbeat": time.time()
            }
            print(f"[+] Лобби зарегистрировано: {data.get('name', 'Без названия')} ({data.get('ip')}:{data.get('port')})")
            
            self.send_response(201)
            self.send_header("Content-Type", "application/json")
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "id": lobby_id}).encode("utf-8"))

        # 2. Heartbeat лобби: POST /api/lobbies/<id>/heartbeat
        elif "/api/lobbies/" in self.path and self.path.endswith("/heartbeat"):
            parts = self.path.split("/")
            lobby_id = parts[3]
            if lobby_id in active_lobbies:
                active_lobbies[lobby_id]["last_heartbeat"] = time.time()
                if "players" in data:
                    active_lobbies[lobby_id]["data"]["players"] = data["players"]
                self.send_response(200)
            else:
                self.send_response(404)
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')
        else:
            self.send_response(404)
            self.end_headers()

    def do_DELETE(self):
        # Удаление лобби: DELETE /api/lobbies/<id>
        if self.path.startswith("/api/lobbies/"):
            lobby_id = self.path.replace("/api/lobbies/", "").strip("/")
            if lobby_id in active_lobbies:
                del active_lobbies[lobby_id]
                print(f"[-] Лобби удалено: {lobby_id}")
            self.send_response(200)
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(b'{"status":"deleted"}')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Подавляем лишний шум в консоли
        pass

def run():
    server = HTTPServer(("0.0.0.0", PORT), MasterServerHandler)
    print(f"=== PRIPYAT Master Server запущен на порту {PORT} ===")
    print("API Endpoints:")
    print("  GET    /api/lobbies           - Список активных комнат")
    print("  POST   /api/lobbies           - Регистрация лобби")
    print("  POST   /api/lobbies/:id/heartbeat - Обновление активности")
    print("  DELETE /api/lobbies/:id       - Закрытие лобби")
    print("Ожидание подключений...")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nСервер остановлен.")
        server.server_close()

if __name__ == "__main__":
    run()
