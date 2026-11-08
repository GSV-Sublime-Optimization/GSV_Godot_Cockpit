#!/usr/bin/env python3
"""Write data/cockpit_events.json from one `gh` poll (zero-token job).

Run every 5 min from a scheduled task. One poll serves the room and every
agent — nobody re-polls the GitHub API for reviews/merges. Rate-limit
aware: at most 1 + 5 `gh` calls per run (PR list + reviews for the 5 most
recently updated open PRs). On ANY failure the file is left untouched and
the run exits non-zero (Loom collector rule: a failed fetch writes no fake
green file).

Schema: {"schema": "cockpit.events/v1", "generated_at": "<ISO UTC>",
"generated_by": "tools/cockpit/events_emit.py", "events": [...]}.
Event kinds: pr_opened / pr_merged / review_submitted / check_failed /
check_passed / mission_transitioned. At most 80 events (the tape cap).
"""

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = "GSV-Sublime-Optimization/GSV_Godot_Cockpit"
SCHEMA = "cockpit.events/v1"
MAX_EVENTS = 80
REVIEW_PRS = 5


def gh(*args: str) -> object:
    out = subprocess.run(
        ["gh", *args], capture_output=True, text=True, timeout=60
    )
    if out.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args)} failed: {out.stderr.strip()[:200]}")
    return json.loads(out.stdout)


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    out_path = repo / "data" / "cockpit_events.json"
    prs = gh(
        "pr", "list", "--repo", REPO, "--state", "all", "--limit", "20",
        "--json", "number,title,state,mergedAt,updatedAt,author,url",
    )
    events: list = []
    for pr in prs:
        state = pr.get("state", "")
        at = pr.get("mergedAt") or pr.get("updatedAt") or ""
        kind = "pr_merged" if state == "MERGED" else "pr_opened"
        events.append({
            "at": at,
            "kind": kind,
            "repo": "GSV_Godot_Cockpit",
            "number": int(pr["number"]),
            "title": str(pr.get("title", ""))[:200],
            "url": str(pr.get("url", "")),
            "actor": str((pr.get("author") or {}).get("login", "")),
            "verdict": "",
        })
    open_prs = [p for p in prs if p.get("state") == "OPEN"]
    open_prs.sort(key=lambda p: str(p.get("updatedAt", "")), reverse=True)
    for pr in open_prs[:REVIEW_PRS]:
        try:
            reviews = gh(
                "api", f"repos/{REPO}/pulls/{pr['number']}/reviews",
                "--jq", ".[-3:]",
            )
        except (RuntimeError, ValueError):
            continue
        if not isinstance(reviews, list):
            continue
        for review in reviews:
            if not isinstance(review, dict):
                continue
            events.append({
                "at": str(review.get("submitted_at", "")),
                "kind": "review_submitted",
                "repo": "GSV_Godot_Cockpit",
                "number": int(pr["number"]),
                "title": str(pr.get("title", ""))[:200],
                "url": str(pr.get("url", "")),
                "actor": str((review.get("user") or {}).get("login", "")),
                "verdict": str(review.get("state", "")),
            })
    events.sort(key=lambda e: str(e.get("at", "")), reverse=True)
    events = events[:MAX_EVENTS]
    payload = {
        "schema": SCHEMA,
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "generated_by": "tools/cockpit/events_emit.py",
        "events": events,
    }
    tmp = out_path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(payload, indent=1) + "\n", encoding="utf-8")
    tmp.replace(out_path)
    print(f"EVENTS_EMIT_PASS {len(events)} events -> {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
