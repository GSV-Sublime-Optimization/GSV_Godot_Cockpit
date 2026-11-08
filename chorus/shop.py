"""shop.py: the Forge's two real data layers - work orders, and where every agent is.

WORK ORDERS live in the shared channel (xanadu:~/steward/cockpit/channel.jsonl) as two kinds of line:
    {"kind": "order", "id": "o-...", "at", "from", "to": <seat or "any">, "station", "text"}
    {"kind": "order-status", "id": "o-...", "at", "from": <seat>, "status": "taken|working|done|declined",
     "note", "link"}
`orders(channel)` folds them into the current state of each order. CHORUS only writes the order line
(Keath posting it); agents write status lines with their own tools, and do the work with their own
permissions. That is how pressing a button changes the fleet while the cockpit itself acts on nothing.

SMITHS are the agents, placed at the station that matches what they last really did:
    anvil   - editing code (claims, MSI Claude's Edit/Write steps)
    quench  - tests and checks (Bash steps that test/verify; Minds checking health)
    bellows - a Mind thinking on a local model
    pegs    - reviewing / opening pull requests
    vault   - backups, mirrors, the record (xanadu)
    hearth  - idle / talking in the channel
"""
from __future__ import annotations

import re
import time
from datetime import datetime

STATIONS = ("anvil", "quench", "bellows", "pegs", "vault", "hearth")
TEST_WORDS = re.compile(r"\b(test|pytest|verify|check|probe|smoke|doctor|lint|scan|trivy)\b", re.I)
PR_WORDS = re.compile(r"\b(pr|pull request|review|merge|push)\b", re.I)


def _ts(s) -> float:
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def orders(channel: list[dict]) -> list[dict]:
    state: dict[str, dict] = {}
    for m in channel:
        if m.get("kind") == "order" and m.get("id"):
            if m["id"] in state:
                continue        # a re-posted order line must never reset an order's history
            state[m["id"]] = {"id": m["id"], "at": m.get("at"), "from": m.get("from"), "to": m.get("to", "any"),
                              "station": str(m.get("station") or "anvil")[:24],   # other cockpits add stations (ledger, act, factory)
                              "text": m.get("text", ""), "status": "posted", "by": None, "note": "", "link": "",
                              "history": [{"at": m.get("at"), "status": "posted", "by": m.get("from")}]}
        elif m.get("kind") == "order-status" and m.get("id") in state:
            o = state[m["id"]]
            o.update(status=m.get("status", o["status"]), by=m.get("from"), note=m.get("note", o["note"]),
                     link=m.get("link", o["link"]))
            o["history"].append({"at": m.get("at"), "status": m.get("status"), "by": m.get("from")})
    rank = {"working": 0, "taken": 1, "posted": 2, "declined": 3, "done": 4}
    return sorted(state.values(), key=lambda o: (rank.get(o["status"], 5), o["at"] or ""))


def _station_for_step(tool: str, label: str) -> str:
    if tool in ("Edit", "Write", "NotebookEdit"):
        return "anvil"
    if PR_WORDS.search(label):
        return "pegs"
    if TEST_WORDS.search(label):
        return "quench"
    if tool in ("Agent",):
        return "hearth"
    return "anvil" if tool in ("Bash", "PowerShell") else "hearth"


def smiths(feed: dict, now: float | None = None) -> list[dict]:
    """One entry per agent seen in the last 3 hours, with the station of its latest real activity."""
    now = now or time.time()
    seen: dict[str, dict] = {}

    def see(name, at, station, doing, rig):
        t = _ts(at)
        if not t or now - t > 3 * 3600:
            return
        cur = seen.get(name)
        if not cur or t > cur["t"]:
            seen[name] = {"name": name, "t": t, "at": at, "station": station, "doing": doing[:120], "rig": rig}

    for a in feed.get("claude_activity") or []:
        see("MSI Claude", a.get("at"), _station_for_step(a.get("tool", ""), a.get("label", "")),
            f"{a.get('tool')}: {a.get('label')}", "msi")
    for e in feed.get("events") or []:
        mind = e.get("mind") or "a Mind"
        rig = "l9" if "l9" in mind else "i3" if "i3" in mind else "msi"
        see(mind, e.get("at"), "bellows", f"thought: {e.get('line', '')}", rig)
    for m in feed.get("channel") or []:
        who = m.get("from") or ""
        if who.startswith("keath") or m.get("kind") == "read":
            continue
        name = {"claude (i3 seat)": "i3 Claude", "claude (msi seat)": "MSI Claude", "i3-mind": "i3 Mind"}.get(who, who)
        rig = "i3" if "i3" in who else "msi"
        if m.get("kind") == "order-status":
            see(name, m.get("at"), "anvil" if m.get("status") == "working" else "pegs",
                f"order {m.get('id')}: {m.get('status')}", rig)
        else:
            see(name, m.get("at"), "hearth", f"said: {m.get('text', '')}", rig)
    for p in feed.get("prs_recent") or []:
        see(p["agent"], p["updated"], "pegs", f"{p['repo']}#{p['number']} {p['title']}", p.get("rig", "cloud"))
    backup = feed.get("backup") or {}
    if backup.get("in_progress"):
        see("Steward", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)), "vault", "off-box backup running", "xanadu")
    return sorted(seen.values(), key=lambda s: -s["t"])


AGENT_PREFIXES = (("agent/chatgpt-gpt6", "GPT-6", "cloud"), ("gpt6/", "GPT-6", "cloud"), ("muse/", "Muse", "cloud"),
                  ("codex/", "Codex", "cloud"), ("bakeoff/mindview-gpt6", "GPT-6", "cloud"),
                  ("bakeoff/mindview-i3claude", "i3 Claude", "i3"), ("claude/", "a Claude", "msi"),
                  ("sol/", "Sol", "cloud"))


def agent_of_branch(branch: str) -> tuple[str, str] | None:
    for prefix, name, rig in AGENT_PREFIXES:
        if branch.startswith(prefix):
            return name, rig
    return None
