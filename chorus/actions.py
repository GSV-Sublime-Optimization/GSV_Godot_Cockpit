"""actions.py: what CHORUS can DO, when Keath presses a button (decision 6ba6a13a, 2026-11-08).

Every action is on a fixed allowlist, bounded (timeout), and undoable or harmless to repeat:
running a colony scheduled task now, restarting one colony container, re-running the doctor, or
pushing a checkout's unpushed commits to a NEW preservation branch (never to main/master, never
forced). Nothing deletes, merges or force-pushes.

Two steps, so a stray click does nothing: `propose()` describes the action and returns a token;
`confirm(token)` within 60 s runs it. Each run posts a {kind: "action"} receipt to the shared
channel so every seat sees who did what and how it went.
"""
from __future__ import annotations

import json
import re
import secrets
import subprocess
import time
from pathlib import Path

TASKS = {  # scheduled tasks Keath may run now
    "heartbeat-msi": ("\\KiloCore-Heartbeat-MSI", "Take MSI's heartbeat now"),
    "mirror-sync": ("\\KiloCore-Mirror-Sync", "Sync the git mirrors now"),
    "offbox-backup": ("\\Colony-Offbox-Backup", "Run the off-box backup to xanadu now"),
    "triage-drone": ("\\KiloCore-L9-Triage-Drone", "Ask the L9 drone to think now"),
}
CONTAINERS = {"kilocore-dev-mentor", "kilocore-model-router", "kilocore-culture-ship", "kilocore-dispatch",
              "kilocore-gordon", "kilocore-serena", "kilocore-nusyq-hub", "kilocore-simulatedverse", "kilocore-skyclaw"}
ROOTS = [Path("C:/dev/active"), Path("K:/dev/worktrees")]
_pending: dict[str, dict] = {}


def catalog() -> list[dict]:
    """What the page can offer (shown as buttons where they apply)."""
    out = [{"action": "task", "target": k, "label": v[1]} for k, v in TASKS.items()]
    out += [{"action": "restart", "target": c, "label": f"Restart the {c.removeprefix('kilocore-')} container"} for c in sorted(CONTAINERS)]
    out += [{"action": "doctor", "target": "all", "label": "Re-measure every failing check now"}]
    return out


def _describe(action: str, target: str) -> str:
    if action == "task" and target in TASKS:
        return f"{TASKS[target][1]} (runs scheduled task {TASKS[target][0]} once)."
    if action == "restart" and target in CONTAINERS:
        return f"Restart container {target}. It is down for a few seconds; other sessions using it will see that."
    if action == "doctor":
        return "Re-run every read-only doctor probe now."
    if action == "preserve":
        p = _checkout(target)
        if p:
            return f"Push {p.name}'s unpushed commits to a new branch on GitHub (nothing else changes; uncommitted files stay)."
    raise ValueError(f"not on the allowlist: {action} {target}")


def _checkout(target: str) -> Path | None:
    p = Path(target)
    return p if any(str(p).lower().startswith(str(r).lower()) for r in ROOTS) and (p / ".git").exists() else None


def propose(action: str, target: str) -> dict:
    desc = _describe(action, target)
    token = secrets.token_urlsafe(9)
    _pending[token] = {"action": action, "target": target, "until": time.time() + 60}
    return {"token": token, "description": desc, "expires_s": 60}


def confirm(token: str) -> dict:
    p = _pending.pop(token, None)
    if not p or time.time() > p["until"]:
        raise ValueError("that confirmation expired; press the button again")
    t0 = time.perf_counter()
    ok, result = _run(p["action"], p["target"])
    return {"action": p["action"], "target": p["target"], "ok": ok, "result": result[:600],
            "ms": round((time.perf_counter() - t0) * 1000)}


def _run(action: str, target: str) -> tuple[bool, str]:
    try:
        if action == "task":
            r = subprocess.run(["schtasks", "/run", "/tn", TASKS[target][0]], capture_output=True, text=True, timeout=30)
            return r.returncode == 0, (r.stdout or r.stderr).strip()
        if action == "restart":
            r = subprocess.run(["docker", "restart", "--time", "20", target], capture_output=True, text=True, timeout=90)
            return r.returncode == 0, (r.stdout or r.stderr).strip() or "restarted"
        if action == "doctor":
            from doctor import diagnose
            feed = json.loads((Path(__file__).parent / "feed.json").read_text(encoding="utf-8"))
            res = diagnose(feed)
            return True, "; ".join(f"{d['key']}: {d['verdict']}" for d in res) or "nothing failing to measure"
        if action == "preserve":
            return _preserve(_checkout(target))
    except subprocess.TimeoutExpired:
        return False, "timed out"
    return False, "unknown action"


def _preserve(path: Path | None) -> tuple[bool, str]:
    if not path:
        return False, "not a colony checkout"
    git = ["git", "-C", str(path)]
    ahead = subprocess.run(git + ["rev-list", "--count", "@{u}..HEAD"], capture_output=True, text=True, timeout=20)
    if ahead.returncode or not ahead.stdout.strip().isdigit() or int(ahead.stdout) == 0:
        return False, "no unpushed commits on a tracked branch (nothing to preserve, or no upstream)"
    name = re.sub(r"[^a-z0-9-]+", "-", path.name.lower()).strip("-")
    branch = f"claude/preserve-{name}-{time.strftime('%Y%m%d-%H%M')}"
    r = subprocess.run(git + ["push", "origin", f"HEAD:refs/heads/{branch}"], capture_output=True, text=True, timeout=120)
    return r.returncode == 0, (f"pushed {ahead.stdout.strip()} commits to {branch}" if r.returncode == 0 else r.stderr.strip())
