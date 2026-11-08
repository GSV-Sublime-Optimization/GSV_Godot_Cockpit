"""knowledge.py: the colony's knowledge layer for CHORUS (read-only, cached 10 minutes).

- atlas:     the Steward's capability atlas (skills, commands, agents, plugins, MCP, CLIs, lanes,
             services, repos, models), counted by kind and status, with the dead lanes named.
- codegraph: GitNexus indexes per repo (files, symbols, relations, flows) and how stale each is
             against the repo's current HEAD.
- vault:     the Obsidian colony vault (C:/dev/vault): note count and the most recently changed notes.
- decisions: the newest colony decisions (Kilo_Core and dev .continuity logs).
- rivals:    the other Mind View bakeoff entries (GSV_Godot_Cockpit PRs), for compare and contrast.
Every source is optional: a missing one yields an {"error": ...} entry and never stops the feed.
"""
from __future__ import annotations

import collections
import glob
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

VAULT = Path("C:/dev/vault")
DECISION_LOGS = [Path("C:/dev/active/Kilo_Core/.continuity/decisions.json"), Path("C:/dev/.continuity/decisions.json")]
_cache: dict = {"at": 0.0, "data": None}


def _atlas() -> dict:
    roots = sorted(glob.glob(str(Path.home() / ".claude/plugins/cache/gsv-sublime/gsv-steward/*/server")))
    if not roots:
        return {"error": "gsv-steward plugin not found"}
    sys.path.insert(0, roots[-1])
    from steward import atlas  # type: ignore
    a = atlas.build()
    cards = list(a.cards.values())
    by_kind = collections.Counter(c.kind for c in cards)
    by_status = collections.Counter(str(c.status or "unknown") for c in cards)
    dead = [{"id": c.id, "name": c.name, "reason": str(c.status_reason or "")[:120]} for c in cards if str(c.status) == "dead"]
    return {"total": len(cards), "by_kind": dict(by_kind.most_common()), "by_status": dict(by_status.most_common()),
            "dead": dead[:20], "probed_at": str(getattr(a, "probed_at", "") or "")}


def _codegraph() -> list[dict]:
    reg = json.loads((Path.home() / ".gitnexus/registry.json").read_text(encoding="utf-8"))
    out = []
    for r in reg if isinstance(reg, list) else reg.get("repos", []):
        head = subprocess.run(["git", "-C", r.get("path", ""), "rev-parse", "HEAD"], capture_output=True, text=True, timeout=10).stdout.strip()
        behind = None
        if head and r.get("lastCommit") and head != r["lastCommit"]:
            c = subprocess.run(["git", "-C", r["path"], "rev-list", "--count", f"{r['lastCommit']}..{head}"],
                               capture_output=True, text=True, timeout=10).stdout.strip()
            behind = int(c) if c.isdigit() else None
        st = r.get("stats") or {}
        out.append({"repo": r.get("name"), "files": st.get("files"), "symbols": st.get("nodes"), "relations": st.get("edges"),
                    "communities": st.get("communities"), "flows": st.get("processes"), "indexed_at": r.get("indexedAt"),
                    "commits_behind": 0 if head == r.get("lastCommit") else behind})
    return out


def _vault(limit: int = 12) -> dict:
    notes = [p for p in VAULT.rglob("*.md") if ".obsidian" not in p.parts and ".trash" not in p.parts]
    recent = sorted(notes, key=lambda p: p.stat().st_mtime, reverse=True)[:limit]
    return {"notes": len(notes), "recent": [{"note": str(p.relative_to(VAULT)).replace("\\", "/"),
                                              "age_h": round((time.time() - p.stat().st_mtime) / 3600, 1)} for p in recent]}


def _decisions(limit: int = 8) -> list[dict]:
    rows = []
    for f in DECISION_LOGS:
        if not f.exists():
            continue
        d = json.loads(f.read_text(encoding="utf-8"))
        for x in d.get("decisions", d) if isinstance(d, dict) else d:
            if isinstance(x, dict):
                rows.append({"id": str(x.get("id", ""))[-8:], "at": x.get("timestamp") or x.get("created_at") or x.get("date"),
                             "q": str(x.get("question", ""))[:140], "repo": f.parent.parent.name, "tags": x.get("tags", [])[:4]})
    return sorted(rows, key=lambda r: str(r.get("at") or ""), reverse=True)[:limit]


def _rivals() -> list[dict]:
    r = subprocess.run(["gh", "pr", "list", "--repo", "GSV-Sublime-Optimization/GSV_Godot_Cockpit", "--state", "open",
                        "--limit", "20", "--json", "number,title,headRefName,url,updatedAt,body"],
                       capture_output=True, text=True, timeout=40, encoding="utf-8", errors="replace")
    out = []
    for p in json.loads(r.stdout or "[]") if r.returncode == 0 else []:
        if not any(k in (p["headRefName"] + p["title"]).lower() for k in ("mindview", "mind view", "cockpit", "holo", "bakeoff", "seat")):
            continue
        imgs = re.findall(r"https://[^\s)\"']+\.png[^\s)\"']*", p.get("body") or "")
        out.append({"number": p["number"], "title": p["title"][:100], "branch": p["headRefName"], "url": p["url"],
                    "updated": p["updatedAt"], "receipts": imgs[:3]})
    return out


def knowledge() -> dict:
    if _cache["data"] is not None and time.time() - _cache["at"] < 600:
        return _cache["data"]
    data = {}
    for name, fn in (("atlas", _atlas), ("codegraph", _codegraph), ("vault", _vault), ("decisions", _decisions), ("rivals", _rivals)):
        try:
            data[name] = fn()
        except Exception as e:  # noqa: BLE001 - one broken source must not hide the others
            data[name] = {"error": f"{e.__class__.__name__}: {str(e)[:160]}"}
    _cache.update(at=time.time(), data=data)
    return data


if __name__ == "__main__":
    t = time.time()
    k = knowledge()
    print(json.dumps({n: (v if not isinstance(v, list) else v[:3]) for n, v in k.items()}, indent=1, default=str)[:3500])
    print(f"# built in {time.time() - t:.1f} s")
