#!/usr/bin/env python3
"""Strict GSV Godot Cockpit acceptance gate.

Godot's exit code and the boot test's PASS banner are not sufficient: scripts
can emit parse/runtime ERROR diagnostics while the SceneTree quits(0).
Runs the repository's boot and portable fixture smoke tests, fails on either
bad exit or engine error diagnostics, and prints a machine-readable receipt.

``--shot PATH`` adds an opt-in render case: the standalone war room
(scenes/HoloWarRoom.tscn) runs WINDOWED but parked off-screen and writes the
HoloRoom to PATH as a PNG, then quits. It needs a GPU session, so it is not
part of the headless default; run it only when nothing else is using the
screen.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import subprocess
import sys
from pathlib import Path

ENGINE_ERROR = re.compile(r"(?m)^\s*(?:SCRIPT ERROR:|ERROR:|FATAL:)")
CASES = (
    ("import", "--import", "Godot Engine v"),
    ("boot", "res://tests/cockpit_boot_test.gd", "[boot-test] PASS"),
    ("portable", "res://tests/portable_offline_test.gd", "[portable-test] PASS"),
    ("holo", "res://tests/holo_coordinate_stack_test.gd", "[holo-test] PASS"),
    ("atlas", "res://tests/capability_atlas_test.gd", "[atlas-test] PASS"),
    ("war-room", "res://tests/war_room_agents_test.gd", "[war-room-test] PASS"),
)
SHOT_SCENE = "res://scenes/HoloWarRoom.tscn"
SHOT_MARKER = "[holo-shot] wrote "
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MIN_SHOT_BYTES = 20000


def assess(returncode: int, output: str, expected: str) -> dict:
    errors = [line.strip() for line in output.splitlines() if ENGINE_ERROR.match(line)]
    return {
        "exit_code": returncode,
        "expected_pass_marker": expected,
        "marker_seen": expected in output,
        "engine_errors": errors,
        "passed": returncode == 0 and expected in output and not errors,
    }


def run_case(binary: str, project: Path, test: str, expected: str, timeout: int) -> dict:
    command = [binary, "--headless", "--path", str(project)]
    if test == "--import":
        command.append("--import")
    else:
        command.extend(["--script", test])
    try:
        proc = subprocess.run(command, capture_output=True, text=True, timeout=timeout,
                              errors="replace", check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"test": test, "passed": False, "execution_error": str(exc)}
    output = proc.stdout + "\n" + proc.stderr
    result = assess(proc.returncode, output, expected)
    result["test"] = test
    if not result["passed"]:
        result["diagnostics_tail"] = output[-8000:]
    return result


def png_size(data: bytes) -> tuple[int, int] | None:
    """(width, height) from a PNG's IHDR, or None when it is not a PNG."""
    if len(data) < 24 or not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", data[16:24])


def assess_shot(returncode: int, output: str, data: bytes | None) -> dict:
    """A render passes on exit 0, the shot marker, zero engine errors, and a
    real, non-trivial PNG (a blank or truncated file is not a render)."""
    result = assess(returncode, output, SHOT_MARKER)
    size = png_size(data or b"")
    result["png_bytes"] = len(data or b"")
    result["png_size"] = list(size) if size else None
    result["passed"] = bool(result["passed"] and size and size[0] > 0 and size[1] > 0
                            and len(data or b"") >= MIN_SHOT_BYTES)
    return result


def run_shot(binary: str, project: Path, shot: Path, timeout: int) -> dict:
    shot = shot.resolve()
    if shot.exists():
        shot.unlink()
    command = [binary, "--audio-driver", "Dummy", "--windowed", "--path", str(project),
               SHOT_SCENE, "--", "--offscreen", f"--shot={shot}", "--quit-after=60"]
    try:
        proc = subprocess.run(command, capture_output=True, text=True, timeout=timeout,
                              errors="replace", check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"test": "shot", "passed": False, "execution_error": str(exc)}
    output = proc.stdout + "\n" + proc.stderr
    data = shot.read_bytes() if shot.exists() else None
    result = assess_shot(proc.returncode, output, data)
    result["test"] = "shot"
    result["path"] = str(shot)
    if not result["passed"]:
        result["diagnostics_tail"] = output[-8000:]
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--shot", type=Path,
                        help="also render the war room off-screen to this PNG (needs a GPU session)")
    args = parser.parse_args()
    results = [run_case(args.godot, args.project.resolve(), name, marker, args.timeout)
               for _, name, marker in CASES]
    if args.shot:
        results.append(run_shot(args.godot, args.project.resolve(), args.shot, args.timeout))
    receipt = {
        "schema": "gsv.cockpit.offline-smoke.v1",
        "project": str(args.project.resolve()),
        "godot": args.godot,
        "status": "PASS" if all(r.get("passed", False) for r in results) else "FAIL",
        "tests": results,
    }
    document = json.dumps(receipt, indent=2, ensure_ascii=False)
    print(document)
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(document + "\n", encoding="utf-8")
    return 0 if receipt["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
