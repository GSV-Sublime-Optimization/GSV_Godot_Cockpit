#!/usr/bin/env python3
"""Strict GSV Godot Cockpit acceptance gate.

Godot's exit code and the boot test's PASS banner are not sufficient: scripts
can emit parse/runtime ERROR diagnostics while the SceneTree quits(0).
Runs the repository's boot and portable fixture smoke tests, fails on either
bad exit or engine error diagnostics, and prints a machine-readable receipt.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
from pathlib import Path

ENGINE_ERROR = re.compile(r"(?m)^\s*(?:SCRIPT ERROR:|ERROR:|FATAL:)")
# These are SAFE, fixture-only tests. Live Studio/fleet integration scenes
# require a real authorized service and must remain a separate explicit gate.
CASES = (
    ("import", "--import", "Godot Engine v"),
    ("boot", "res://tests/cockpit_boot_test.gd", "[boot-test] PASS"),
    ("portable", "res://tests/portable_offline_test.gd", "[portable-test] PASS"),
    ("entity", "res://tests/entity_session_test.gd", "ENTITY_SESSION_PASS"),
    ("projection", "res://tests/fleet_body_projection_test.gd", "ENTITY_FLEET_PROJECTION_PASS"),
    ("console", "res://tests/entity_observation_console_test.gd", "ENTITY_OBSERVATION_CONSOLE_PASS"),
    ("studio", "res://tests/studio_entity_bridge_test.gd", "STUDIO_ENTITY_BRIDGE_PASS"),
)


ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def assess(returncode: int, output: str, expected: str) -> dict:
    # Coloured Godot logs and carriage-return progress lines must not hide
    # a fatal parser/error diagnostic behind ANSI/control-byte prefixes.
    cleaned = ANSI_ESCAPE.sub("", output).replace("\r", "\n")
    lines = [line.strip() for line in cleaned.splitlines()]
    errors = [line for line in lines if ENGINE_ERROR.match(line)]
    # A PASS must be an exact, standalone final marker, including bare
    # ENTITY_* sentinels. The old substring check could be fooled by debug
    # prose or a partial success banner.
    marker_seen = (sum(line.startswith(expected) for line in lines) == 1
                   if expected == "Godot Engine v" else lines.count(expected) == 1)
    return {
        "exit_code": returncode,
        "expected_pass_marker": expected,
        "marker_seen": marker_seen,
        "engine_errors": errors,
        "passed": returncode == 0 and marker_seen and not errors,
    }


def _kill_owned_tree(proc: subprocess.Popen) -> None:
    """Bounded cleanup of the process we launched and its descendants only."""
    if os.name == "nt":
        try:
            killed = subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                                    capture_output=True, timeout=10, check=False)
            if killed.returncode != 0 and proc.poll() is None:
                proc.kill()
        except (OSError, subprocess.TimeoutExpired):
            if proc.poll() is None:
                proc.kill()
    else:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    try:
        proc.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()


def isolated_env(source: dict[str, str] | None = None) -> dict[str, str]:
    """A proof declared offline must never opportunistically touch live Studio.

    Local developers may have GSV_STUDIO_LIVE=1 set in their shell. Resetting
    the flag only in CI leaves the portable GSV gate non-hermetic on the MSI.
    """
    env = dict(os.environ if source is None else source)
    env["GSV_STUDIO_LIVE"] = "0"
    env.pop("GSV_STUDIO_ENTITY_PORT", None)
    return env


def run_case(binary: str, project: Path, test: str, expected: str, timeout: int) -> dict:
    command = [binary, "--headless", "--audio-driver", "Dummy", "--path", str(project)]
    if test == "--import":
        command.append("--import")
    else:
        command.extend(["--script", test])
    proc = None
    try:
        proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, errors="replace", start_new_session=os.name != "nt",
                                env=isolated_env())
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        if proc is not None:
            _kill_owned_tree(proc)
        return {"test": test, "passed": False, "execution_error": "timeout (owned process tree stopped)"}
    except OSError as exc:
        return {"test": test, "passed": False, "execution_error": str(exc)}
    output = stdout + "\n" + stderr
    result = assess(proc.returncode, output, expected)
    result["test"] = test
    if not result["passed"]:
        result["diagnostics_tail"] = output[-8000:]
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    results = [run_case(args.godot, args.project.resolve(), name, marker, args.timeout)
               for _, name, marker in CASES]
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
