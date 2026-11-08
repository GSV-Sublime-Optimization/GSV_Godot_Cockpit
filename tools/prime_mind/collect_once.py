#!/usr/bin/env python3
"""One-shot, read-only Xanadu Mind archive fetch for ΞNuSyQ-Prime.

Only an existing *authenticated operator* SSH alias is used. No daemon,
remote write, process restart, token handling, synthetic observations,
or autonomous polling. A successful SSH snapshot is not fleet admission.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any

SCHEMA = "colony.mindview-feed/v0"
SSH_HOST = "xanadu"
MAX_RESPONSE_BYTES = 180_000
REMOTE_SCRIPT = r'''
import datetime, glob, json, os, pathlib
root = pathlib.Path.home() / "steward"
data = {"events": [], "heartbeats": {}}
files = sorted((root / "events").glob("*.jsonl"))[-2:]
lines = []
for path in files:
    if not path.is_file() or path.stat().st_size > 400000:
        continue
    with path.open(encoding="utf-8") as stream:
        lines.extend(stream.readlines()[-80:])
for line in lines[-80:]:
    try:
        obj = json.loads(line)
        if isinstance(obj, dict):
            data["events"].append(obj)
    except (ValueError, TypeError):
        pass
for name in ("msi", "i3", "l9"):
    path = root / "heartbeats" / (name + ".json")
    if not path.is_file() or path.stat().st_size > 8192:
        continue
    try:
        data["heartbeats"][name] = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        pass
print(json.dumps(data, separators=(",", ":")))
'''


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def elapsed(stamp: Any, now: dt.datetime) -> int | None:
    if not isinstance(stamp, str):
        return None
    try:
        observed = dt.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        if observed.tzinfo is None:
            return None
        return int((now - observed).total_seconds())
    except (TypeError, ValueError, OverflowError):
        return None


def project(remote: dict[str, Any], *, now: dt.datetime) -> dict[str, Any]:
    if not isinstance(remote, dict):
        raise ValueError("invalid_remote_source")
    events = remote.get("events", [])
    heartbeats = remote.get("heartbeats", {})
    if not isinstance(events, list) or not isinstance(heartbeats, dict):
        raise ValueError("invalid_remote_schema")
    bodies: dict[str, dict[str, Any]] = {}
    for rig in ("msi", "i3", "l9", "xanadu"):
        body = {
            "label": rig.upper(), "role": "observation node",
            "status": "unknown", "failing": [],
            "age_s": None, "detail": "No current authenticated heartbeat",
        }
        hb = heartbeats.get(rig)
        if rig == "xanadu":
            body["detail"] = "SSH read of Xanadu archive succeeded; host health not independently qualified"
        elif isinstance(hb, dict) and hb.get("schema") == "colony.heartbeat/v1" and hb.get("rig") == rig:
            age = elapsed(hb.get("at"), now)
            checks = hb.get("checks", [])
            failed = []
            if isinstance(checks, list):
                for c in checks[:20]:
                    if isinstance(c, dict) and c.get("ok") is False and isinstance(c.get("name"), str):
                        failed.append(c["name"][:80])
            body["age_s"] = max(0, age) if age is not None else None
            if age is None or age < -120 or age > 900:
                body["status"] = "silent"
            else:
                body["status"] = "green" if hb.get("green") is True else "red"
            body["failing"] = failed
            body["detail"] = "Heartbeat from Xanadu archive, not a runtime attachment"
        bodies[rig] = body
    cleaned = []
    for e in events[-80:]:
        if not isinstance(e, dict):
            continue
        if not all(isinstance(e.get(field), str) for field in ("at", "mind", "line", "level")):
            continue
        focus = e.get("focus")
        if focus is not None and focus not in bodies:
            focus = None
        reasons = e.get("reasons", [])
        if not isinstance(reasons, list):
            reasons = []
        model = e.get("model")
        if model is not None and not isinstance(model, str):
            model = None
        level = e["level"] if e["level"] in ("routine", "notable", "alarm", "calm") else "routine"
        cleaned.append({
            "at": e["at"][:40], "mind": e["mind"][:64], "model": model,
            "level": level, "line": e["line"][:600], "focus": focus,
            "reasons": [r[:320] for r in reasons[:8] if isinstance(r, str)],
            "simulated": e.get("simulated") is True,
        })
    return {
        "schema": SCHEMA,
        "at": now.isoformat(timespec="seconds").replace("+00:00", "Z"),
        "source_ok": True,
        "bodies": bodies, "events": cleaned,
        "attention": cleaned[-1].get("focus") if cleaned else None,
        "screen": "",
    }


def collect_once(*, output: Path, timeout: float = 16.0) -> dict[str, Any]:
    cmd = ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
           "-o", "ConnectTimeout=6", SSH_HOST, "python3 -"]
    creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0
    result = subprocess.run(
        cmd, input=REMOTE_SCRIPT, capture_output=True, text=True,
        encoding="utf-8", timeout=timeout, check=False, creationflags=creationflags,
    )
    if result.returncode != 0 or len(result.stdout.encode("utf-8")) > MAX_RESPONSE_BYTES:
        raise RuntimeError("authenticated_archive_fetch_unavailable")
    remote = json.loads(result.stdout)
    feed = project(remote, now=utc_now())
    output.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps(feed, ensure_ascii=False, separators=(",", ":"))
    if len(content.encode("utf-8")) > MAX_RESPONSE_BYTES:
        raise RuntimeError("projected_feed_oversized")
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=output.parent,
        prefix=".prime-mind-", suffix=".tmp", delete=False,
    ) as stream:
        tmp = Path(stream.name)
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    try:
        tmp.replace(output)
    finally:
        if tmp.exists():
            tmp.unlink()
    return {"output": str(output), "events": len(feed["events"]),
            "source_ok": feed["source_ok"],
            "note": "one authorized read; no remote changes"}


def main(argv: list[str] | None = None) -> int:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--output", type=Path, required=True,
                     help="Local-only file for --feed in the Godot scene")
    args = cli.parse_args(argv)
    try:
        result = collect_once(output=args.output)
    except (subprocess.TimeoutExpired, OSError, RuntimeError, ValueError) as error:
        print(json.dumps({"state": "unavailable", "reason": str(error)}), file=sys.stderr)
        return 2
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
