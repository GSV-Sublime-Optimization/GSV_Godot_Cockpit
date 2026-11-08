"""work.py: what the colony is doing right now, and which work is at risk (read-only).

- claims: who is editing what, from the colony coordination board (`colony.py status --json`).
- at_risk: git checkouts with uncommitted changes or unpushed commits. The 2026-08-04 wipe
  destroyed tracked, uncommitted edits; this makes that state visible before it is lost.

Both are cached (claims 60 s, scan 5 min) so the 15 s feeder loop stays cheap.
"""
from __future__ import annotations

import json
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

COLONY = Path("C:/dev/tools/colony/colony.py")
ROOTS = [Path("C:/dev/active"), Path("K:/dev/worktrees")]
_cache: dict[str, tuple[float, object]] = {}


def _cached(key: str, ttl: float, fn):
    at, val = _cache.get(key, (0.0, None))
    if time.time() - at > ttl:
        try:
            val = fn()
        except (OSError, ValueError, subprocess.SubprocessError):
            pass                      # keep the last good value
        _cache[key] = (time.time(), val)
    return val


def _claims() -> list[dict]:
    r = subprocess.run(["python", str(COLONY), "status", "--json"], capture_output=True, text=True,
                       timeout=30, encoding="utf-8", errors="replace")
    rows = json.loads(r.stdout or "[]")
    groups: dict[tuple, dict] = {}
    for c in rows:
        p = Path(c.get("path", ""))
        repo = _repo_label(p)
        g = groups.setdefault((c.get("agent"), repo), {"agent": c.get("agent"), "repo": repo, "files": [], "age_min": 9e9})
        g["files"].append(p.name)
        g["age_min"] = min(g["age_min"], round(c.get("age_minutes", 0), 1))
    return sorted(groups.values(), key=lambda g: g["age_min"])


def _repo_label(p: Path) -> str:
    parts = [x.lower() for x in p.parts]
    for anchor in ("worktrees", "active"):
        if anchor in parts:
            i = parts.index(anchor)
            return "/".join(p.parts[i + 1:i + 3 if anchor == "worktrees" else i + 2])
    return p.parent.name


def _label(path: Path) -> str:
    for root in ROOTS:
        try:
            return path.relative_to(root).as_posix()
        except ValueError:
            continue
    return path.name


def _checkouts() -> list[Path]:
    out = []
    for root in ROOTS:
        if not root.exists():
            continue
        for d in root.iterdir():
            if (d / ".git").exists():
                out.append(d)
            elif d.is_dir() and root.name == "worktrees":
                out += [x for x in d.iterdir() if (x / ".git").exists()]
    return out


def _state(path: Path) -> dict | None:
    r = subprocess.run(["git", "-C", str(path), "status", "--porcelain=v1", "-b"], capture_output=True,
                       text=True, timeout=20, encoding="utf-8", errors="replace")
    if r.returncode:
        return None
    lines = r.stdout.splitlines()
    head = lines[0] if lines else ""
    dirty = len(lines) - 1
    ahead = 0
    if "[ahead " in head:
        ahead = int(head.split("[ahead ")[1].split("]")[0].split(",")[0])
    no_upstream = "..." not in head and "no branch" not in head
    if not dirty and not ahead:
        return None
    t = subprocess.run(["git", "-C", str(path), "log", "-1", "--format=%ct"], capture_output=True, text=True, timeout=10)
    last = float(t.stdout.strip() or 0)
    branch = head[3:].split("...")[0].strip()
    return {"path": str(path), "label": _label(path), "branch": branch, "dirty": dirty, "ahead": ahead,
            "no_upstream": no_upstream, "last_commit_h": round((time.time() - last) / 3600, 1) if last else None}


def _scan() -> list[dict]:
    with ThreadPoolExecutor(8) as ex:
        found = [s for s in ex.map(lambda p: _safe_state(p), _checkouts()) if s]
    # riskiest first: unpushed commits, then many uncommitted files
    return sorted(found, key=lambda s: (-s["ahead"], -s["dirty"]))


def _safe_state(p: Path) -> dict | None:
    try:
        return _state(p)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


def work() -> dict:
    return {"claims": _cached("claims", 60, _claims) or [], "at_risk": _cached("scan", 300, _scan) or []}


if __name__ == "__main__":
    t = time.time()
    w = work()
    print(json.dumps(w, indent=1)[:3000])
    print(f"# {len(w['claims'])} claim groups, {len(w['at_risk'])} at-risk checkouts in {time.time() - t:.1f} s")
