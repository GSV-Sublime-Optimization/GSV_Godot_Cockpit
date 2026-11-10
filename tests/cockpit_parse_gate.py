#!/usr/bin/env python3
"""Standalone, strict Godot 4.7.1 parse proof for every first-party cockpit GDScript.

.gsv may call colony-owned parsing tools on a connected workstation. CI must
also prove the scripts from this repository ALONE. No sister repo or backend
must be installed for this read-only source validation.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENGINE_ERROR = re.compile(
    r"(?mi)^\s*(?:SCRIPT ERROR:|ERROR:|FATAL:|Parse Error:|Parser Error:)"
)
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def source_scripts(root: Path = ROOT) -> list[Path]:
    result = list((root / "scripts").rglob("*.gd"))
    result.extend((root / "tests").glob("*.gd"))
    return sorted(result)


def assess_parse(returncode: int, output: str) -> bool:
    cleaned = ANSI_ESCAPE.sub("", output).replace("\r", "\n")
    return returncode == 0 and not ENGINE_ERROR.search(cleaned)


def check(godot: str = "godot", root: Path = ROOT, timeout: int = 35) -> int:
    root = root.resolve()
    scripts = source_scripts(root)
    if not scripts or not (root / "scripts" / "Main.gd").is_file():
        print("COCKPIT_PARSE_FAIL: no real first-party scripts", file=sys.stderr)
        return 2
    failures: list[str] = []
    for file in scripts:
        relative = file.relative_to(root).as_posix()
        command = [godot, "--headless", "--audio-driver", "Dummy", "--path", str(root),
                   "--check-only", "--script", "res://" + relative]
        try:
            process = subprocess.run(
                command, capture_output=True, text=True, errors="replace",
                timeout=timeout, check=False,
            )
            log = process.stdout + "\n" + process.stderr
            if not assess_parse(process.returncode, log):
                failures.append(f"{relative}: exit {process.returncode}\n{log[-4000:]}")
        except (OSError, subprocess.SubprocessError) as exc:
            failures.append(f"{relative}: {exc}")
    if failures:
        for failure in failures:
            print("COCKPIT_PARSE_FAIL: " + failure, file=sys.stderr)
        return 1
    print(f"COCKPIT_SOURCE_PARSE_PASS: {len(scripts)} scripts, Godot headless --check-only")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--project", type=Path, default=ROOT)
    parser.add_argument("--timeout", type=int, default=35)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    return check(args.godot, args.project, args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
