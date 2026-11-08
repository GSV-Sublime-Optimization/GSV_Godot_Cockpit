#!/usr/bin/env python3
"""One-way bridge: chorus feed.json -> KiloCore-Studio entity observations (v0).

Reads the merged colony feed (colony.heartbeat/v1 per rig plus xanadu's
backup/mirror receipts) and writes one ``<node-id>.json`` per body in the
``kilocore.entity.fleet-observation.v0`` shape that Studio PR #56 reads from
``KCS_ENTITY_OBSERVATIONS_DIR``.

Honesty rules:
- Timestamps are never refreshed: ``captured_at_utc`` is the heartbeat's own
  ``at`` (or, for xanadu, the newest receipt time). Studio's 300 s window then
  decides fresh vs stale; nothing old can turn green here.
- A heartbeat older than STALE_AFTER_S is still written with its real time, so
  Studio shows ``stale``; a missing rig has its file REMOVED, so Studio shows
  ``unknown`` rather than a leftover reading.
- Authority is always ``execution: none`` with every grant false.
- Fields heartbeats do not carry (cpu_logical) are null, never guessed.

Stdlib only.  Usage:
    python studio_bridge.py --once [--feed PATH] [--out DIR]
    python studio_bridge.py --watch [--interval 30]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

SOURCE_SCHEMA = "kilocore.entity.fleet-observation.v0"
ENTITY_ID = "kilocore.colony.entity.primary.v0"
STALE_AFTER_S = 15 * 60
WATCH_INTERVAL_S = 30
MIB = 1024 * 1024
GB = 1000 ** 3  # heartbeat free_gb is decimal GB

DEFAULT_FEED = Path(__file__).resolve().parent / "feed.json"

# rig key in the feed -> (Studio node id, role, hostname, os_family)
# Hostname/os_family are the colony's KNOWN mapping (START_HERE_FLEET), not a
# reading taken by the heartbeat itself. See report: schema gap.
RIGS = {
    "msi": ("kilo-core-msi", "primary-body", "MSI", "Windows"),
    "i3": ("desktop-i3anuvp", "interactive-body-candidate", "DESKTOP-I3ANUVP", "Windows"),
    "l9": ("desktop-l9v3emb", "evaluation-worker", "DESKTOP-L9V3EMB", "Windows"),
}
XANADU = ("imac-xanadu", "continuity-observer", "xanadu", "Linux")
NODE_IDS = [v[0] for v in RIGS.values()] + [XANADU[0]]


def default_out_dir() -> Path:
    base = os.environ.get("LOCALAPPDATA") or str(Path.home() / ".local" / "share")
    return Path(base) / "KiloCore" / "chorus" / "entity-observations"


def _parse_time(value: Any) -> dt.datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else None


def _iso(when: dt.datetime) -> str:
    return when.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def _nonneg_int(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
        return None
    return int(value)


def _envelope(node: tuple[str, str, str, str], captured: dt.datetime,
              mem: int | None, disk: int | None, provenance: dict[str, Any]) -> dict[str, Any]:
    node_id, role, hostname, os_family = node
    return {
        "schema": SOURCE_SCHEMA,
        "entity_id": ENTITY_ID,
        "body_id": node_id,
        "role": role,
        "observation": {
            "kind": "physical_local_os",
            "captured_at_utc": _iso(captured),
            "hostname": hostname,
            "os_family": os_family,
            "cpu_logical": None,
            "memory_available_bytes": mem,
            "system_volume_free_bytes": disk,
        },
        "authority": {
            "execution": "none",
            "identity_attested": False,
            "remote_work_admitted": False,
            "writes_enabled": False,
        },
        # Dropped by Studio's projection; kept for humans reading the file.
        "bridge": provenance,
    }


def from_heartbeat(rig: str, hb: Any, now: dt.datetime) -> dict[str, Any] | None:
    """Return a v0 observation for one rig heartbeat, or None if unusable."""
    if not isinstance(hb, dict) or hb.get("rig") not in (None, rig):
        return None
    at = _parse_time(hb.get("at"))
    if at is None:
        return None
    mem_mb = _nonneg_int(hb.get("ram_avail_mb"))
    disks = hb.get("disks") if isinstance(hb.get("disks"), dict) else {}
    c_drive = disks.get("C") if isinstance(disks.get("C"), dict) else {}
    free_gb = c_drive.get("free_gb")
    disk = None
    if not isinstance(free_gb, bool) and isinstance(free_gb, (int, float)) and free_gb >= 0:
        disk = int(free_gb * GB)
    age = (now - at).total_seconds()
    checks = hb.get("checks") if isinstance(hb.get("checks"), list) else []
    provenance = {
        "source": "chorus/feed.json heartbeats." + rig,
        "source_schema": hb.get("schema"),
        "observer": hb.get("observer", "self"),
        "heartbeat_green": hb.get("green") is True,
        "failing_checks": [c.get("name") for c in checks
                           if isinstance(c, dict) and c.get("ok") is False],
        "heartbeat_age_s": int(age),
        "heartbeat_stale": age > STALE_AFTER_S,
    }
    return _envelope(RIGS[rig], at, None if mem_mb is None else mem_mb * MIB, disk, provenance)


def from_xanadu(feed: dict[str, Any], served: dt.datetime) -> dict[str, Any] | None:
    """xanadu has no heartbeat; its newest backup/mirror receipt dates it."""
    ages = []
    for key in ("backup", "mirror"):
        rec = feed.get(key)
        if isinstance(rec, dict):
            age_h = rec.get("age_h")
            if not isinstance(age_h, bool) and isinstance(age_h, (int, float)) and age_h >= 0:
                ages.append((age_h, key))
    if not ages:
        return None
    age_h, key = min(ages)
    captured = served - dt.timedelta(hours=age_h)
    provenance = {
        "source": "chorus/feed.json " + key + " receipt",
        "observer": "receipt (no xanadu heartbeat)",
        "backup": feed.get("backup"),
        "mirror": feed.get("mirror"),
    }
    return _envelope(XANADU, captured, None, None, provenance)


def convert(feed: Any, now: dt.datetime | None = None) -> dict[str, dict[str, Any] | None]:
    """Map a feed dict to {node_id: observation or None (= unknown)}."""
    current = now or dt.datetime.now(dt.timezone.utc)
    out: dict[str, dict[str, Any] | None] = {n: None for n in NODE_IDS}
    if not isinstance(feed, dict):
        return out
    beats = feed.get("heartbeats") if isinstance(feed.get("heartbeats"), dict) else {}
    for rig, node in RIGS.items():
        out[node[0]] = from_heartbeat(rig, beats.get(rig), current)
    served = _parse_time(feed.get("served_at")) or current
    out[XANADU[0]] = from_xanadu(feed, served)
    return out


def _atomic_write(path: Path, data: dict[str, Any]) -> None:
    fd, tmp = tempfile.mkstemp(prefix="." + path.stem + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=1)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def write_all(observations: dict[str, dict[str, Any] | None], out_dir: Path) -> dict[str, str]:
    out_dir.mkdir(parents=True, exist_ok=True)
    result = {}
    for node_id, obs in observations.items():
        path = out_dir / (node_id + ".json")
        if obs is None:
            try:
                path.unlink()
                result[node_id] = "removed"
            except FileNotFoundError:
                result[node_id] = "absent"
        else:
            _atomic_write(path, obs)
            result[node_id] = "written"
    return result


def run_once(feed_path: Path, out_dir: Path) -> dict[str, str]:
    try:
        feed = json.loads(feed_path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as exc:
        print(f"studio_bridge: cannot read feed {feed_path}: {exc}", file=sys.stderr)
        feed = None  # everything becomes unknown, never a leftover reading
    return write_all(convert(feed), out_dir)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--once", action="store_true")
    mode.add_argument("--watch", action="store_true")
    ap.add_argument("--feed", type=Path, default=DEFAULT_FEED)
    ap.add_argument("--out", type=Path, default=default_out_dir())
    ap.add_argument("--interval", type=float, default=WATCH_INTERVAL_S)
    args = ap.parse_args(argv)
    while True:
        result = run_once(args.feed, args.out)
        print(json.dumps({"at": _iso(dt.datetime.now(dt.timezone.utc)),
                          "out": str(args.out), "nodes": result}), flush=True)
        if args.once:
            return 0
        time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
