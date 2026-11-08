"""Local-only two-endpoint Studio contract stub for Godot transport verification.

This does not create missions on the real Studio. It asserts POST bytes and replies with
a synthetic acknowledgement only on 127.0.0.1 under an ephemeral test port.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread

ROOT = Path(__file__).resolve().parents[1]
GODOT = os.environ.get("GODOT_EXE", "godot")
POSTS: list[dict] = []

class StudioStub(BaseHTTPRequestHandler):
    def _reply(self, code: int, data: dict) -> None:
        raw = json.dumps(data, separators=(",", ":")).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_GET(self) -> None:
        if self.path == "/api/missions/msn_012345abcdef" and len(POSTS) == 1:
            self._reply(200, {
                "id": "msn_012345abcdef", "status": "succeeded", "risk": "R2",
                "review": True, "mergeable": False,
                "result": {"receipt_id": "rcpt_fixture_ack_0001",
                           "validator": {"exit_code": 0, "timed_out": False},
                           "report": {"raw_ok": True, "acceptance": [
                               {"criterion": "Fixture transport only", "met": True}]},
                           "commits": [], "changed_paths": []}})
            return
        if self.path != "/api/projects":
            self._reply(404, {"error": "not found"})
            return
        self._reply(200, {
            "schema": "kilocore-studio.projects-scan.v2", "state": "OBSERVED",
            "projects": [
                {"name": "Fixture Furyline", "path": "C:/dev/active/Furyline",
                 "git": {"is_repo": True, "branch": "main"}},
                {"name": "Denied", "path": "C:/tmp/nope", "git": {"is_repo": False}}
            ]})

    def do_POST(self) -> None:
        if self.path != "/api/missions":
            self._reply(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 16000:
            self._reply(400, {"error": "bad size"})
            return
        try:
            data = json.loads(self.rfile.read(length))
        except ValueError:
            self._reply(400, {"error": "bad JSON"})
            return
        POSTS.append(data)
        if (data.get("repo") != "C:/dev/active/Furyline"
                or data.get("base_branch") != "main"
                or data.get("risk") != "R2"
                or data.get("posted_by") != "godot-workstation"
                or len(data.get("acceptance", [])) != 2):
            self._reply(400, {"error": "invalid mission envelope"})
            return
        self._reply(201, {
            "id": "msn_012345abcdef", "status": "awaiting_approval",
            "repo": data["repo"], "risk": data["risk"],
            "needs_approval": True})

def main() -> int:
    server = ThreadingHTTPServer(("127.0.0.1", 0), StudioStub)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    env = os.environ.copy()
    env["GSV_STUDIO_ENTITY_PORT"] = str(server.server_port)
    try:
        proc = subprocess.run(
            [GODOT, "--headless", "--audio-driver", "Dummy", "--path",
             str(ROOT), "--script", "res://tests/workstation_mission_transport_test.gd"],
            cwd=str(ROOT), capture_output=True, text=True, timeout=25, env=env)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)
    print(proc.stdout)
    if proc.stderr:
        print(proc.stderr, file=sys.stderr)
    if (proc.returncode != 0
            or "WORKSTATION_MISSION_TRANSPORT_PASS" not in proc.stdout
            or "ERROR:" in proc.stderr or "SCRIPT ERROR:" in proc.stderr
            or len(POSTS) != 1):
        return 1
    print("STUDIO_MISSION_HTTP_CONTRACT_PASS")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
