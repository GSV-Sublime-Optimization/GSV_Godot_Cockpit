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
import re
import subprocess
import sys
from pathlib import Path

ENGINE_ERROR = re.compile(r"(?m)^\s*(?:SCRIPT ERROR:|ERROR:|FATAL:)")
CASES = (
    ("boot", "res://tests/cockpit_boot_test.gd", "[boot-test] PASS"),
    ("portable", "res://tests/portable_offline_test.gd", "[portable-test] PASS"),
)


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
    command = [binary, "--headless", "--path", str(project), "--script", test]
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
