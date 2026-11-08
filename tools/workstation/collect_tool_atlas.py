#!/usr/bin/env python3
"""Bounded read-only presence scan for the Godot Workstation's optional Tool Atlas.

No connectors are authenticated, no processes are executed, no repository files are
read, and no capabilities are considered qualified. Writes only the explicit JSON
output, atomically. Run manually or from an owner-approved scheduled collector.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import tempfile
import time

SCHEMA = "gsv.workstation.tool-atlas.v1"
DEFAULTS = (
    ("omnisynapse", "OMNISYNAPSE", "OMNISYNAPSE"),
    ("gsv-steward", "GSV Steward", "gsv-steward"),
    ("gsv-cockpit", "GSV Godot Cockpit", "GSV_Godot_Cockpit"),
    ("kilocore-studio", "KiloCore Studio", "KiloCore-Studio"),
    ("kilocore-governance", "Kilo_Core", "Kilo_Core"),
    ("nusyq-hub", "NuSyQ Hub", "NuSyQ-Hub"),
    ("dev-mentor", "Dev-Mentor", "Dev-Mentor"),
    ("fleetbridge", "FleetBridge", "FleetBridge"),
)
IDENTIFIER = re.compile(r"^[a-z0-9_-]{1,48}$")


def observe(name: str, identifier: str, location: Path) -> dict:
    # Presence is deliberately weaker than connectivity or tool admission.
    if not location.is_dir():
        state = "not_found"
    elif (location / ".git").exists():
        state = "source_present"
    else:
        state = "directory_seen"
    return {"id": identifier, "name": name, "state": state, "path": str(location)}


def build_snapshot(root: Path, extras: list[str], now: int | None = None) -> dict:
    if not root.is_absolute() or not root.is_dir():
        raise ValueError("The authorized workspace root must be an existing absolute directory")
    registered = {}
    for identifier, name, dirname in DEFAULTS:
        registered[identifier] = (name, root / dirname)
    for value in extras:
        if "=" not in value:
            raise ValueError("Each --extra must have the form id=absolute-path")
        identifier, supplied_path = value.split("=", 1)
        if not IDENTIFIER.fullmatch(identifier) or identifier in registered:
            raise ValueError("Invalid or duplicate --extra identifier")
        location = Path(supplied_path)
        if not location.is_absolute():
            raise ValueError("Extra paths must be explicitly absolute")
        registered[identifier] = (identifier.replace("-", " ").title(), location)
    if len(registered) > 32:
        raise ValueError("Maximum 32 tools")
    return {
        "schema": SCHEMA,
        "observed_at_unix": int(time.time()) if now is None else now,
        "tools": [observe(name, identifier, location) for identifier, (name, location)
                  in registered.items()],
    }


def atomic_write(destination: Path, payload: dict) -> None:
    if not destination.is_absolute():
        raise ValueError("Output path must be absolute")
    destination.parent.mkdir(parents=True, exist_ok=True)
    blob = (json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    if len(blob) > 65536:
        raise ValueError("Atlas exceeds the 64 KiB UI contract")
    name = None
    try:
        with tempfile.NamedTemporaryFile(mode="wb", prefix=".workstation-atlas-", suffix=".tmp",
                                         dir=destination.parent, delete=False) as file:
            name = Path(file.name)
            file.write(blob)
            file.flush()
            os.fsync(file.fileno())
        os.replace(name, destination)
    finally:
        if name is not None and name.exists():
            name.unlink()


def main() -> int:
    default_root = Path("C:/dev/active") if os.name == "nt" else Path.home() / "dev" / "active"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=default_root,
                        help="Existing authorized workspace root (no recursive scan)")
    parser.add_argument("--out", type=Path, default=None,
                        help="Explicit absolute output path, also set GSV_WORKSTATION_TOOL_ATLAS")
    parser.add_argument("--extra", action="append", default=[], metavar="ID=ABSOLUTE_PATH",
                        help="Opt in a further directory, e.g. Obsidian vault or GitNexus index")
    args = parser.parse_args()
    output = args.out or Path(os.environ["GSV_WORKSTATION_TOOL_ATLAS"]) if (
        args.out or os.environ.get("GSV_WORKSTATION_TOOL_ATLAS")) else None
    if output is None:
        parser.error("--out or GSV_WORKSTATION_TOOL_ATLAS is required; no implicit writes")
    try:
        payload = build_snapshot(args.root, args.extra)
        atomic_write(output, payload)
    except (ValueError, OSError) as exc:
        parser.exit(2, f"ATLAS_UNAVAILABLE: {exc}\n")
    counts = {state: sum(item["state"] == state for item in payload["tools"])
              for state in ("source_present", "directory_seen", "not_found")}
    print("TOOL_ATLAS_WRITTEN", output, counts)
    print("Presence does not establish runtime connectivity, authentication or admission.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
