#!/usr/bin/env python3
"""
Lightweight TTS server using Edge TTS.
Runs on the Mac Studio, serves audio to the Sam Glasses app.
"""

import asyncio
import hashlib
import os
import tempfile
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import subprocess
import threading

VOICE = os.environ.get("TTS_VOICE", "en-US-AvaNeural")
PORT = int(os.environ.get("TTS_PORT", "18790"))
CACHE_DIR = os.path.join(tempfile.gettempdir(), "sam-tts-cache")
os.makedirs(CACHE_DIR, exist_ok=True)


class TTSHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/v1/audio/speech":
            self.send_error(404)
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON")
            return

        text = data.get("input", data.get("text", ""))
        voice = data.get("voice", VOICE)

        if not text:
            self.send_error(400, "No text provided")
            return

        # Cache by text+voice hash
        cache_key = hashlib.md5(f"{voice}:{text}".encode()).hexdigest()
        cache_path = os.path.join(CACHE_DIR, f"{cache_key}.mp3")

        if not os.path.exists(cache_path):
            # Generate via edge-tts
            try:
                result = subprocess.run(
                    ["edge-tts", "--voice", voice, "--text", text, "--write-media", cache_path],
                    capture_output=True, text=True, timeout=30
                )
                if result.returncode != 0:
                    self.send_error(500, f"TTS failed: {result.stderr}")
                    return
            except subprocess.TimeoutExpired:
                self.send_error(500, "TTS timeout")
                return

        # Serve the audio
        with open(cache_path, "rb") as f:
            audio_data = f.read()

        self.send_response(200)
        self.send_header("Content-Type", "audio/mpeg")
        self.send_header("Content-Length", str(len(audio_data)))
        self.end_headers()
        self.wfile.write(audio_data)

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "voice": VOICE}).encode())
        else:
            self.send_error(404)

    def log_message(self, format, *args):
        # Quiet logging
        pass


def main():
    server = HTTPServer(("127.0.0.1", PORT), TTSHandler)
    print(f"🔊 Sam TTS Server running on http://127.0.0.1:{PORT}")
    print(f"   Voice: {VOICE}")
    print(f"   Cache: {CACHE_DIR}")
    server.serve_forever()


if __name__ == "__main__":
    main()
