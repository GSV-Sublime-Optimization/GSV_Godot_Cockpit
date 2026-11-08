#!/usr/bin/env python3
"""Compile docs/suggestions/*.md into data/cockpit_suggestions.json.

Stdlib only, zero-token (same pattern as fleet_feed.ps1 / vault_bridge.py:
read local files, schema-pin, cap, write). Run by hand or from a scheduled
job; the room reads the JSON, never this directory.

Schema: {"schema": "cockpit.suggestions/v1", "generated_at": "<ISO UTC>",
"generated_by": "tools/cockpit/suggestions_emit.py", "suggestions": [...]}.
Each suggestion: file / title / author / kind / target / status / reason /
link_pr / evidence. Unknown kind/target/status values are rejected (the
file is left unwritten and the run fails) — never silently mapped.
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

KINDS = {"fix", "edit", "correction", "update", "improvement"}
TARGETS = {
    "room", "table", "seat", "web", "card", "shelf", "ledger", "tape",
    "rail", "legend", "needs", "doors", "docs", "other",
}
STATUSES = {"open", "triaged", "accepted", "declined", "implemented", "closed"}
MAX_FILES = 200
MAX_BYTES = 4096
SCHEMA = "cockpit.suggestions/v1"


def parse_suggestion(path: Path) -> dict:
    raw = path.read_bytes()
    if len(raw) > MAX_BYTES:
        raise ValueError(f"{path.name}: over {MAX_BYTES} bytes")
    text = raw.decode("utf-8")
    header: dict = {}
    for line in text.splitlines():
        line = line.strip()
        if not line:
            break
        if ":" not in line:
            raise ValueError(f"{path.name}: bad header line {line!r}")
        key, value = line.split(":", 1)
        header[key.strip().lower()] = value.strip()
    for field in ("title", "author", "kind", "target", "status"):
        if not header.get(field):
            raise ValueError(f"{path.name}: missing {field}")
    if header["kind"] not in KINDS:
        raise ValueError(f"{path.name}: unknown kind {header['kind']!r}")
    if header["target"] not in TARGETS:
        raise ValueError(f"{path.name}: unknown target {header['target']!r}")
    if header["status"] not in STATUSES:
        raise ValueError(f"{path.name}: unknown status {header['status']!r}")
    return {
        "file": path.name,
        "title": header["title"][:200],
        "author": header["author"][:200],
        "kind": header["kind"],
        "target": header["target"],
        "status": header["status"],
        "reason": header.get("reason", "")[:200],
        "link_pr": header.get("link_pr", "")[:200],
        "evidence": header.get("evidence", "")[:200],
    }


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    src_dir = repo / "docs" / "suggestions"
    out_path = repo / "data" / "cockpit_suggestions.json"
    files = sorted(src_dir.glob("*.md")) if src_dir.is_dir() else []
    files = [p for p in files if p.name != "README.md"][:MAX_FILES]
    suggestions = [parse_suggestion(p) for p in files]
    payload = {
        "schema": SCHEMA,
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "generated_by": "tools/cockpit/suggestions_emit.py",
        "suggestions": suggestions,
    }
    tmp = out_path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(payload, indent=1) + "\n", encoding="utf-8")
    tmp.replace(out_path)
    print(f"SUGGESTIONS_EMIT_PASS {len(suggestions)} suggestions -> {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
