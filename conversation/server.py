from __future__ import annotations

import argparse
import json
import mimetypes
import os
import pathlib
import tempfile
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse


ROOT = pathlib.Path(__file__).resolve().parent
WEB_ROOT = ROOT / "web"
MESSAGE_ROOT = ROOT / "messages"
MESSAGE_ROOT.mkdir(parents=True, exist_ok=True)


def read_messages() -> list[dict]:
    messages: list[dict] = []
    for path in MESSAGE_ROOT.glob("*.json"):
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
            if all(key in value for key in ("id", "created_at_utc", "from", "to", "text")):
                messages.append(value)
        except (OSError, ValueError):
            continue
    return sorted(messages, key=lambda item: (item["created_at_utc"], item["id"]))


def write_message(sender: str, recipient: str, text: str, kind: str = "message") -> dict:
    if sender not in {"Alice", "Bob", "Nathan"}:
        raise ValueError("Expediteur invalide")
    if recipient not in {"Alice", "Bob", "Tous"}:
        raise ValueError("Destinataire invalide")
    text = text.strip()
    if not text or len(text) > 4000:
        raise ValueError("Le message doit contenir entre 1 et 4000 caracteres")

    message = {
        "id": uuid.uuid4().hex,
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "from": sender,
        "to": recipient,
        "kind": kind,
        "text": text,
    }
    handle, temporary_name = tempfile.mkstemp(prefix=".message-", suffix=".tmp", dir=MESSAGE_ROOT)
    try:
        with os.fdopen(handle, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(message, stream, ensure_ascii=False, indent=2)
        os.replace(temporary_name, MESSAGE_ROOT / f"{message['id']}.json")
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)
    return message


class Handler(BaseHTTPRequestHandler):
    server_version = "AliceBobBoard/1.0"

    def send_json(self, value: object, status: int = 200) -> None:
        payload = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/api/health":
            self.send_json({"ok": True})
            return
        if parsed.path == "/api/messages":
            self.send_json(read_messages())
            return

        relative = "index.html" if parsed.path in {"", "/"} else parsed.path.lstrip("/")
        requested = (WEB_ROOT / relative).resolve()
        try:
            requested.relative_to(WEB_ROOT.resolve())
        except ValueError:
            self.send_error(403)
            return
        if not requested.is_file():
            self.send_error(404)
            return
        payload = requested.read_bytes()
        media_type = mimetypes.guess_type(requested.name)[0] or "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", f"{media_type}; charset=utf-8" if media_type.startswith("text/") else media_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self) -> None:
        if urlparse(self.path).path != "/api/messages":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length < 1 or length > 16_384:
                raise ValueError("Taille invalide")
            value = json.loads(self.rfile.read(length).decode("utf-8"))
            message = write_message(
                str(value.get("from", "Nathan")),
                str(value.get("to", "Tous")),
                str(value.get("text", "")),
                str(value.get("kind", "message")),
            )
            self.send_json(message, 201)
        except (ValueError, UnicodeError, json.JSONDecodeError) as error:
            self.send_json({"error": str(error)}, 400)

    def log_message(self, fmt: str, *args: object) -> None:
        return


def main() -> None:
    parser = argparse.ArgumentParser(description="Local Alice and Bob conversation board")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Alice & Bob board: http://127.0.0.1:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
