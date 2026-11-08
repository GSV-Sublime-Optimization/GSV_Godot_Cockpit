#!/usr/bin/env python3
"""mindview_feed.py: serve CHORUS on 127.0.0.1 with live data from xanadu (Mind View bakeoff, MSI entry).

Every 15 s it makes ONE read-only SSH call to xanadu, collects the last two days of
~/steward/events/*.jsonl and every ~/steward/heartbeats/*.json, and writes feed.json next to
index.html (atomically). It never writes to xanadu, starts nothing there, and binds to loopback only.

    python chorus/mindview_feed.py            # then open http://127.0.0.1:8767/
    python chorus/mindview_feed.py --once     # write feed.json once and exit (for receipts)
"""
from __future__ import annotations

import argparse
import functools
import re
import shlex
import http.server
import json
import os
import subprocess
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PORT = 8767
REMOTE = r"""python3 - <<'PY'
import glob, json, os, time
home = os.path.expanduser("~/steward")
days = sorted(glob.glob(os.path.join(home, "events", "*.jsonl")))[-2:]
events = []
for f in days:
    for line in open(f, encoding="utf-8"):
        line = line.strip()
        if line:
            try: events.append(json.loads(line))
            except ValueError: pass
beats = {}
for f in glob.glob(os.path.join(home, "heartbeats", "*.json")):
    try: beats[os.path.basename(f)[:-5]] = json.load(open(f))
    except ValueError: pass
import re
now = time.time()
sets = sorted(f for f in glob.glob(os.path.expanduser("~/backups/colony/20*")) if re.fullmatch(r"\d{4}-\d{2}-\d{2}", os.path.basename(f)))
backup = {"set": os.path.basename(sets[-1]), "age_h": round((now - os.path.getmtime(sets[-1])) / 3600, 1),
          "in_progress": bool(glob.glob(os.path.expanduser("~/backups/colony/*.partial")))} if sets else None
recs = sorted(glob.glob(os.path.expanduser("~/mirrors/_receipts/*.json")), key=os.path.getmtime)
mirror = None
if recs:
    r = json.load(open(recs[-1]))
    mirror = {"age_h": round((now - os.path.getmtime(recs[-1])) / 3600, 1), "ok": r.get("ok"),
              "repos": len(r.get("repos", [])), "failures": r.get("failures", 0)}
cards = []
for f in sorted(glob.glob(os.path.join(home, "outbox", "*.md"))):
    head = next((l.strip("# \n") for l in open(f, encoding="utf-8", errors="replace") if l.startswith("#")), os.path.basename(f))
    cards.append({"file": os.path.basename(f), "title": head[:140], "age_d": round((now - os.path.getmtime(f)) / 86400, 1)})
channel = []
cf = os.path.join(home, "cockpit", "channel.jsonl")
if os.path.exists(cf):
    for line in open(cf, encoding="utf-8", errors="replace").read().splitlines()[-400:]:
        try: channel.append(json.loads(line))
        except ValueError: pass
print(json.dumps({"events": [e for e in events if not e.get("simulated")][-200:], "heartbeats": beats,
                  "backup": backup, "mirror": mirror, "steward_cards": cards, "channel": channel, "served_at": now}))
PY"""

LOCAL = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "KiloCore" / "chorus"


def claude_activity(limit: int = 60) -> list[dict]:
    """MSI Claude's own recent steps (written by hooks/claude_activity.py; tool + short label only)."""
    f = LOCAL / "claude_events.jsonl"
    if not f.exists():
        return []
    out = []
    for line in f.read_text(encoding="utf-8", errors="replace").splitlines()[-limit:]:
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


_spine = {"at": 0.0, "data": None}


def spine() -> dict | None:
    """Dev-Mentor's live spine (the colony's service registry) on this machine, cached 60 s:
    it probes ~18 services live and takes about 6 s (measured 2026-11-08)."""
    if time.time() - _spine["at"] < _spine.get("wait", 60):
        return _spine["data"]
    _spine["at"] = time.time()
    fresh = _spine_fetch()
    # back off when Dev-Mentor is struggling: a cockpit must not add load to the thing it watches
    _spine["wait"] = 60 if fresh else 300
    if fresh:
        _spine["data"] = fresh
    elif _spine["data"]:
        _spine["data"] = {**_spine["data"], "stale": True}
    return _spine["data"]


def _spine_fetch() -> dict | None:
    try:
        import urllib.request
        with urllib.request.urlopen("http://127.0.0.1:7337/api/spine/services", timeout=8) as r:
            d = json.loads(r.read().decode("utf-8", "replace"))
        return {"up": d.get("services_up"), "total": d.get("services_total"),
                "services": [{"name": s.get("name"), "tier": s.get("tier"), "up": s.get("up"), "ms": s.get("ms")}
                             for s in d.get("services", [])]}
    except (OSError, ValueError):
        return None

_doc = {"at": 0.0, "items": []}


def doctor_cached(data: dict) -> list[dict]:
    """Read-only diagnosis of failing checks (doctor.py), at most every 5 minutes."""
    if time.time() - _doc["at"] > 300:
        _doc["at"] = time.time()
        try:
            from doctor import diagnose
            _doc["items"] = diagnose(data)
        except Exception as e:  # noqa: BLE001 - a broken probe must not stop the feed
            _doc["items"] = [{"key": "doctor", "verdict": f"unknown: doctor failed ({e.__class__.__name__})", "evidence": []}]
    return _doc["items"]


PRS_EVERY = 300          # GitHub is asked at most every 5 minutes
_prs = {"at": 0.0, "items": []}


def waiting_prs() -> list[dict]:
    """Open, non-draft colony PRs with no review yet: the work waiting on a second actor (read-only gh)."""
    if time.time() - _prs["at"] < PRS_EVERY:
        return _prs["items"]
    r = subprocess.run(["gh", "search", "prs", "--owner", "GSV-Sublime-Optimization", "--state", "open",
                        "--draft=false", "--review", "none", "--limit", "30", "--json",
                        "repository,number,title,url,createdAt"],
                       capture_output=True, text=True, timeout=40, encoding="utf-8", errors="replace")
    if r.returncode == 0:
        items = []
        for p in json.loads(r.stdout or "[]"):
            repo = p["repository"]["name"]
            # every agent reviews through the shared account, so GitHub's reviewDecision never moves;
            # the colony's own record is a <!-- gsv-review: ... head=<sha> --> comment bound to the head
            v = subprocess.run(["gh", "pr", "view", str(p["number"]), "--repo", f"GSV-Sublime-Optimization/{repo}",
                                "--json", "headRefOid,comments"], capture_output=True, text=True, timeout=30,
                               encoding="utf-8", errors="replace")
            if v.returncode == 0:
                info = json.loads(v.stdout or "{}")
                head = info.get("headRefOid", "")
                if head and any(f"head={head}" in c.get("body", "") and "<!-- gsv-review:" in c.get("body", "")
                                for c in info.get("comments", [])):
                    continue
            items.append({"repo": repo, "number": p["number"], "title": p["title"][:110],
                          "url": p["url"], "created": p["createdAt"]})
        _prs["items"] = items
        _prs["at"] = time.time()
    return _prs["items"]


_recent = {"at": 0.0, "items": []}


def recent_prs() -> list[dict]:
    """Colony PRs updated in the last 3 h, attributed to an agent by branch prefix (read-only gh)."""
    if time.time() - _recent["at"] < PRS_EVERY:
        return _recent["items"]
    from shop import agent_of_branch
    since = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 3 * 3600))
    r = subprocess.run(["gh", "search", "prs", "--owner", "GSV-Sublime-Optimization", f"--updated=>{since}",
                        "--limit", "40", "--json", "repository,number,title,url,updatedAt,state"],
                       capture_output=True, text=True, timeout=40, encoding="utf-8", errors="replace")
    items = []
    if r.returncode == 0:
        repos = sorted({p["repository"]["name"] for p in json.loads(r.stdout or "[]")})
        for repo in repos:                       # one call per repo, not per PR
            v = subprocess.run(["gh", "pr", "list", "--repo", f"GSV-Sublime-Optimization/{repo}", "--state", "all",
                                "--search", f"updated:>{since}", "--limit", "20", "--json",
                                "number,headRefName,title,url,updatedAt,state"],
                               capture_output=True, text=True, timeout=30, encoding="utf-8", errors="replace")
            for p in json.loads(v.stdout or "[]") if v.returncode == 0 else []:
                who = agent_of_branch(p["headRefName"])
                if who:
                    items.append({"agent": who[0], "rig": who[1], "repo": repo, "number": p["number"],
                                  "title": p["title"][:90], "url": p["url"], "updated": p["updatedAt"], "state": p["state"]})
        _recent.update(at=time.time(), items=items)
    return _recent["items"]


def fetch() -> dict:
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "xanadu", REMOTE],
                       capture_output=True, text=True, timeout=40, encoding="utf-8", errors="replace")
    if r.returncode:
        raise RuntimeError(f"xanadu unreachable (ssh exit {r.returncode})")
    data = json.loads(r.stdout.strip().splitlines()[-1])
    try:
        data["prs_waiting"] = waiting_prs()
    except (subprocess.SubprocessError, ValueError, OSError):
        data["prs_waiting"] = _prs["items"]
    flush_acks()
    try:
        from work import work           # colony claims + checkouts holding unsaved work
        data["work"] = work()
    except Exception as e:              # noqa: BLE001 - a broken probe must not stop the feed
        data["work"] = {"error": str(e)[:200]}
    data["doctor"] = doctor_cached(data)
    try:
        data["prs_recent"] = recent_prs()
    except (subprocess.SubprocessError, ValueError, OSError):
        data["prs_recent"] = _recent["items"]
    from shop import orders, smiths
    data["orders"] = orders(data.get("channel", []))
    data["reroute"] = reroute_tick(data)
    import actions
    data["actions"] = actions.catalog()
    data["impact"] = impact(data)
    try:
        from knowledge import knowledge     # atlas, code graphs, vault, decisions, rival cockpits (cached 10 min)
        data["knowledge"] = knowledge()
    except Exception as e:  # noqa: BLE001
        data["knowledge"] = {"error": str(e)[:200]}
    data["usage"] = usage()
    data["smiths"] = smiths(data)
    data["claude_activity"] = claude_activity()
    data["spine"] = spine()
    # cache the shared channel locally so the Claude prompt hook can read it without a network call
    LOCAL.mkdir(parents=True, exist_ok=True)
    (LOCAL / "channel.cache.jsonl").write_text("\n".join(json.dumps(m) for m in data.get("channel", [])), encoding="utf-8")
    return data


REROUTE_PER_CYCLE = 3


def reroute_tick(data: dict) -> dict:
    """Each cycle: plan the one-time re-route of stale orders to seats that cannot act (reroute.py).
    Writes only with CHORUS_AUTO_REROUTE=1 (at most REROUTE_PER_CYCLE a cycle); otherwise the plan is
    shown in the feed and `chorus.py reroute --apply` writes it."""
    try:
        import reroute
        ledger = reroute.load_ledger()
        items = reroute.plan(data.get("channel", []), data, ledger=ledger)
        out = {"auto": os.environ.get("CHORUS_AUTO_REROUTE") == "1", "plan": reroute.describe(items), "applied": []}
        if out["auto"] and items:
            out["applied"] = reroute.apply([i for i in items if i.get("to")][:REROUTE_PER_CYCLE], _append, _gh_comment,
                                           "claude (msi seat)", ledger=ledger)
        return out
    except Exception as e:  # noqa: BLE001 - a broken re-route must not stop the feed
        return {"error": str(e)[:200]}


def flush_acks() -> None:
    """Post one read receipt for the messages the MSI Claude was shown (written by hooks/chorus_inbox.py)."""
    f = LOCAL / "acks.jsonl"
    if not f.exists() or not f.stat().st_size:
        return
    reads = sorted({json.loads(l)["at"] for l in f.read_text(encoding="utf-8").splitlines() if l.strip()})
    rec = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "from": "claude (msi seat)", "to": "all",
           "kind": "read", "reads": reads, "text": f"read {len(reads)} message(s)"}
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "xanadu",
                        "cat >> ~/steward/cockpit/channel.jsonl"], input=json.dumps(rec) + chr(10),
                       capture_output=True, text=True, timeout=30)
    if r.returncode == 0:
        f.unlink()


SPEAKERS = {"claude": "claude (msi seat)", "mind": "mind", "all": "all"}


# Who may speak through CHORUS. The page itself always speaks as Keath; an agent that posts
# through /say must name its own seat, so nothing an agent writes is ever signed as Keath.
# gpt-6, codex and muse are cloud seats: they may be addressed (and may sign their own lines if they
# ever post through CHORUS), but they do not read xanadu's channel, so send() mirrors every channel
# line to them onto GitHub (router.TARGETS[...]["mirror"]).
SEATS = {"keath": "keath (chorus)", "claude (msi seat)": "claude (msi seat)",
         "claude (i3 seat)": "claude (i3 seat)", "i3-mind": "i3-mind",
         "gpt-6": "gpt-6", "codex": "codex", "muse": "muse"}


def say(text: str, to: str, sender: str = "keath") -> dict:
    """Append a message to the shared cockpit channel on xanadu (the one write CHORUS makes)."""
    text = " ".join(str(text).split())[:600]
    if not text:
        raise ValueError("empty message")
    if sender not in SEATS:
        raise ValueError(f"unknown seat {sender!r}; use one of {sorted(SEATS)}")
    msg = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "from": SEATS[sender],
           "to": SPEAKERS.get(to, to if to in SEATS.values() else "claude (msi seat)"), "text": text, "via": "chorus"}
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "xanadu",
                        "mkdir -p ~/steward/cockpit && cat >> ~/steward/cockpit/channel.jsonl"],
                       input=json.dumps(msg) + "\n", capture_output=True, text=True, timeout=30)
    if r.returncode:
        raise RuntimeError(f"xanadu unreachable (ssh exit {r.returncode})")
    return msg


def impact(data: dict, limit: int = 20) -> list[dict]:
    """What the cockpit actually changed, newest first: actions run, orders finished, agent PRs merged."""
    out = []
    for m in data.get("channel", []):
        if m.get("kind") == "action":
            out.append({"at": m.get("at"), "kind": "action", "who": m.get("from"), "ok": m.get("ok"),
                        "what": f"{m.get('action')} {m.get('target')}", "detail": str(m.get("result", ""))[:160]})
        elif m.get("kind") == "order-status" and m.get("status") in ("done", "declined"):
            out.append({"at": m.get("at"), "kind": f"order {m.get('status')}", "who": m.get("from"), "ok": m.get("status") == "done",
                        "what": m.get("id"), "detail": str(m.get("note", ""))[:160], "link": m.get("link", "")})
    for p in data.get("prs_recent") or []:
        if p.get("state") == "MERGED":
            out.append({"at": p.get("updated"), "kind": "merged", "who": p.get("agent"), "ok": True,
                        "what": f"{p['repo']}#{p['number']}", "detail": p.get("title", ""), "link": p.get("url", "")})
    return sorted(out, key=lambda x: x.get("at") or "", reverse=True)[:limit]


def usage() -> dict:
    """How much agents used the cockpit in the last 24 h (MCP tool calls, CLI/hook reads)."""
    f = LOCAL / "mcp_calls.jsonl"
    cutoff = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 86400))
    calls = []
    if f.exists():
        for line in f.read_text(encoding="utf-8", errors="replace").splitlines()[-2000:]:
            try:
                c = json.loads(line)
            except ValueError:
                continue
            if c.get("at", "") >= cutoff:
                calls.append(c)
    by_tool: dict[str, int] = {}
    for c in calls:
        by_tool[c["tool"]] = by_tool.get(c["tool"], 0) + 1
    return {"mcp_calls_24h": len(calls), "by_tool": by_tool, "seats": sorted({c.get("seat", "?") for c in calls})}


def post_order(text: str, to: str, station: str, action: str = "", target: str = "", due: str = "",
               why: str = "", sender: str = "keath") -> dict:
    """Keath (or a seat) posts a work order: one line in the channel. An agent takes it and does the work.
    `due` is when it should start ("" now, "hourly", "after:#424", or an ISO time); `why` one sentence."""
    from shop import STATIONS
    text = " ".join(str(text).split())[:600]
    if not text:
        raise ValueError("empty order")
    if sender not in SEATS:
        raise ValueError(f"unknown seat {sender!r}")
    now = time.gmtime()
    msg = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", now), "from": SEATS[sender], "kind": "order",
           "id": "o-" + time.strftime("%m%d-%H%M%S", now), "to": to if to in SEATS.values() or to == "any" else "any",
           "station": station if station in STATIONS or station == "act" else "anvil", "text": text, "via": "chorus"}
    if due:
        msg["due"] = _clean(due, 40)
    if why:
        msg["why"] = _clean(why, 240)
    if station == "act":
        if sender != "keath":
            raise ValueError("action orders are only posted by Keath (his post is the confirm)")
        import actions
        actions._describe(action, target)            # refuse anything off the allowlist up front
        msg.update(action=action, target=target)
    _append(msg)
    return msg


def _clean(v, n: int) -> str:
    return " ".join(str(v or "").split())[:n]


def post_suggestion(text: str, node: str, sender: str = "keath", why: str = "", due: str = "") -> dict:
    """A suggestion to improve the cockpit, from Keath or any seat: becomes an order to the MSI seat
    (station "cockpit"), so it is taken, worked and closed with a link like any other order."""
    text = " ".join(str(text).split())[:500]
    if not text:
        raise ValueError("empty suggestion")
    if sender not in SEATS:
        raise ValueError(f"unknown seat {sender!r}")
    now = time.gmtime()
    msg = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", now), "from": SEATS[sender], "kind": "order",
           "id": "s-" + time.strftime("%m%d-%H%M%S", now), "to": "claude (msi seat)", "station": "cockpit",
           "text": f"SUGGEST{(' [' + node[:60] + ']') if node else ''}: {text}", "via": "chorus"}
    if why:
        msg["why"] = _clean(why, 240)
    if due:
        msg["due"] = _clean(due, 40)
    _append(msg)
    return msg


def _append(msg: dict) -> None:
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "xanadu",
                        "mkdir -p ~/steward/cockpit && cat >> ~/steward/cockpit/channel.jsonl"],
                       input=json.dumps(msg) + chr(10), capture_output=True, text=True, timeout=30)
    if r.returncode:
        raise RuntimeError(f"xanadu unreachable (ssh exit {r.returncode})")


# ------------------------------------------------------------------ the smart composer: /route and /send
LOCAL_TIMEOUT = 45          # a local model gets this long to answer; a cold load can take longer (then: honest error)
GH_URL = re.compile(r"^https://github\.com/GSV-Sublime-Optimization/[\w.-]+/(pull|issues)/\d+$")
REVIEW_QUEUE_URL = "https://github.com/GSV-Sublime-Optimization/dev/issues/431"
STUDIO_API = "http://127.0.0.1:7340/api/missions"
CHATDEV_QUEUE = "C:/dev/active/Dev-Mentor/tasks/queue.json"


def current_feed() -> dict:
    """The newest feed.json (the router's view of who is around); {} when there is none yet."""
    for _ in range(5):          # Windows denies reads while write_feed's os.replace swaps the file
        try:
            return json.loads((HERE / "feed.json").read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {}
        except (PermissionError, json.JSONDecodeError):
            time.sleep(0.15)
    return {}


def route_suggestion(body: dict) -> dict:
    """POST /route: the router's suggestion for a draft. Reads only; sends nothing."""
    import router
    node = body.get("node") if isinstance(body.get("node"), dict) else {}
    return router.route(str(body.get("text", "")), node, current_feed(), kind=body.get("kind") or None,
                        to=body.get("to") or None)


def _post_json(url: str, payload: dict, headers: dict, timeout: float) -> dict:
    import urllib.request
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), method="POST",
                                 headers={"Content-Type": "application/json", **headers})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def local_ask(target: dict, question: str, why: str = "") -> tuple[str | None, str | None]:
    """Ask a local model directly. -> (answer, None) or (None, the honest reason it did not answer)."""
    headers = {}
    key = os.environ.get("LITELLM_MASTER_KEY") or os.environ.get("LITELLM_API_KEY")
    if key and ":4000/" in target["url"]:
        headers["Authorization"] = f"Bearer {key}"
    payload = {"model": target["model"], "max_tokens": 400, "stream": False, "messages": [
        {"role": "system", "content": "You answer questions for the KiloCore colony cockpit. Plain words, at most 120 words. "
                                      "Say so when you do not know; never invent a measurement."},
        {"role": "user", "content": question + (f"\nContext: {why}" if why else "")}]}
    try:
        d = _post_json(target["url"], payload, headers, LOCAL_TIMEOUT)
        text = str(d["choices"][0]["message"]["content"] or "")
    except (OSError, ValueError, KeyError, IndexError, TypeError) as e:
        return None, f"{e.__class__.__name__}: {str(e)[:160]}"
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.S).strip()
    return (text[:1500], None) if text else (None, "the model returned an empty answer")


def send(body: dict, sender: str = "keath") -> dict:
    """POST /send: dispatch one composed message to the writer its WHERE names. Every send leaves a
    channel line (the ledger). Live targets get it now; prepared ones come back as what to paste."""
    import router
    if sender not in SEATS:
        raise ValueError(f"unknown seat {sender!r}; use one of {sorted(SEATS)}")
    kind, to = str(body.get("kind", "")), router.target_id(body.get("to")) or str(body.get("to", ""))
    if kind not in router.KINDS:
        raise ValueError(f"unknown kind {kind!r}; use one of {', '.join(router.KINDS)}")
    t = router.TARGETS.get(to)
    if not t:
        raise ValueError(f"unknown target {to!r}")
    where = str(body.get("where") or t["where"][0])
    if where not in t["where"]:
        raise ValueError(f"{t['label']} is not reached through {where!r} (only {', '.join(t['where'])})")
    text = _clean(body.get("text"), 600)
    if not text:
        raise ValueError("empty message")
    why, due, when = _clean(body.get("why"), 240), _clean(body.get("due"), 40), _clean(body.get("when"), 40) or "now"
    node = body.get("node") if isinstance(body.get("node"), dict) else {}
    if router.second_actor_conflict(kind, node, to):
        raise ValueError(f"{t['label']} is the PR author's own kind: a review must come from a different actor")
    if t["type"] == "seat" and not router.can_take(to, kind):
        raise ValueError(f"{t['label']} cannot execute {router.KIND_WORDS.get(kind, kind)} (it can only: "
                         f"{', '.join(router.CAN.get(to, ()))}); send it to a seat with hands")
    if t.get("mirror") and kind == "action-order":
        raise ValueError(f"{t['label']} cannot run cockpit actions (it is not on a colony rig); send an order instead")
    about = router.node_label(node) if node else ""
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    base = {"at": now, "from": SEATS[sender], "to": to, "intent": kind, "via": "chorus"}
    base.update({k: v for k, v in (("why", why), ("due", due), ("about", about[:80])) if v})

    if where == "channel":
        if kind in ("order", "action-order"):
            station = "act" if kind == "action-order" else (_clean(body.get("station"), 12) or router.station_for(kind, node))
            msg = post_order(text, to if to in SEATS.values() else "any", station, _clean(body.get("action"), 20),
                             _clean(body.get("target"), 200), due, why, sender)
        elif kind == "suggest" and to == "claude (msi seat)":
            msg = post_suggestion(text, about, sender, why, due)
        else:
            msg = {**base, "text": text}
            _append(msg)
        if not t.get("mirror"):
            return {"delivered": True, "message": msg, "summary": f"sent to {t['label']} on the channel"}
        # a cloud seat never reads the channel: the line above is the ledger, the mirror is the delivery
        url = _clean(node.get("url"), 200)
        mirror = _gh_comment(t, kind, sender, about, text, why, when, url if GH_URL.match(url) else REVIEW_QUEUE_URL,
                             {**base, "where": "github" if GH_URL.match(url) else "review-queue"}, ref=msg.get("id", ""))
        return {"delivered": mirror["delivered"], "message": msg, "mirror": mirror,
                "summary": f"on the channel (which {t['label']} does not read), and {mirror['summary']}"}

    if where == "local":
        answer, err = local_ask(t, text, why)
        line = {**base, "kind": "local-ask", "model": t["model"], "ok": err is None,
                "text": f"asked {t['label']}: {text[:300]}", "answer": (answer or f"no answer: {err}")[:600]}
        ledger = None
        try:
            _append(line)
        except (RuntimeError, OSError, subprocess.SubprocessError) as e:
            ledger = f"ledger not written: {e}"
        if err:
            raise RuntimeError(f"{t['label']} did not answer ({t['model']} at {t['url']}): {err}")
        return {"delivered": True, "answer": answer, "model": t["model"], "message": line, "ledger_error": ledger,
                "summary": f"{t['label']} answered"}

    if where in ("github", "review-queue"):
        url = REVIEW_QUEUE_URL if where == "review-queue" else _clean(node.get("url"), 200)
        if not GH_URL.match(url):
            raise ValueError("no colony GitHub PR or issue on this node; send it to the review queue instead")
        res = _gh_comment(t, kind, sender, about, text, why, when, url, {**base, "where": where})
        return {"delivered": res["delivered"], "prepared": res["prepared"], "message": res["line"], "summary": res["summary"]}

    if where == "studio":       # Studio missions wait for Keath's approve; CHORUS never posts around it
        prepared = {"method": "POST", "url": STUDIO_API, "note": "post it from Studio (or mission_post); it then waits for your approve",
                    "body": {"title": text[:80], "objective": text + (f"\nWhy: {why}" if why else ""), "acceptance": [],
                             "risk": "low", "posted_by": "chorus"}}
    else:                       # chatdev: a ready queue entry; the queue file is shared, so CHORUS does not edit it
        prepared = {"file": CHATDEV_QUEUE, "entry": {"title": text[:80], "description": text, "why": why,
                                                      "source": "chorus", "created_at": now}}
    line = {**base, "kind": "sent", "where": where, "delivered": False,
            "text": f"prepared for {t['label']} (Keath sends it): {text[:200]}"}
    _append(line)
    return {"delivered": False, "prepared": prepared, "message": line, "summary": f"prepared for {t['label']}"}


def _gh_comment(t: dict, kind: str, sender: str, about: str, text: str, why: str, when: str, url: str,
                base: dict, ref: str = "") -> dict:
    """Comment `text` for target `t` on a colony PR/issue: prepared as a `gh` command, run only when
    CHORUS_ALLOW_GH_COMMENT=1. Always leaves one ledger line on the channel."""
    import router
    comment = (f"**{router.KIND_WORDS.get(kind, kind)} for {t['label']}** (via CHORUS, from {SEATS[sender]})"
               f"{(' about ' + about) if about else ''}{(' - channel ' + ref) if ref else ''}\n\n{text}"
               + (f"\n\nWhy: {why}" if why else "")
               + (f"\nWhen: {when}" if when != "now" else "")).replace("@", "(at)")   # never ping anyone
    cmd = ["gh", "pr" if "/pull/" in url else "issue", "comment", url, "--body", comment]
    delivered, prepared = False, {"command": shlex.join(cmd), "body": comment, "url": url}
    if os.environ.get("CHORUS_ALLOW_GH_COMMENT") == "1":     # opt-in: the feeder may comment as the shared account
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=40, encoding="utf-8", errors="replace")
        if r.returncode:
            raise RuntimeError(f"gh comment failed: {(r.stderr or r.stdout).strip()[:200]}")
        delivered, prepared = True, None
    line = {**base, "kind": "sent", "where": base.get("where") or "github", "link": url, "delivered": delivered,
            "text": f"{'commented' if delivered else 'prepared a comment'} for {t['label']} on "
                    f"{url.split('github.com/')[-1]}: {text[:200]}"}
    if ref:
        line["mirror_of"] = ref
    _append(line)
    return {"delivered": delivered, "prepared": prepared, "line": line,
            "summary": f"commented on {url}" if delivered else
            "prepared: paste the command (the feeder does not comment on GitHub unless CHORUS_ALLOW_GH_COMMENT=1)"}


LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "[::1]"}


def post_allowed(headers) -> str | None:
    """Why a POST must be refused, or None. Any web page Keath has open can send a 'simple'
    cross-origin POST to 127.0.0.1 (text/plain, no preflight), and a DNS-rebinding page can even
    read the reply. So: the Host must be loopback, any Origin must be this same loopback origin,
    and the body must be declared JSON (which forces a CORS preflight this server never grants)."""
    host = (headers.get("Host") or "").strip().lower()
    hostname = host.rsplit(":", 1)[0] if not host.endswith("]") else host
    if hostname not in LOOPBACK_HOSTS:
        return "bad Host"
    origin = (headers.get("Origin") or "").strip().lower()
    if origin and origin not in (f"http://{host}",):
        return "cross-origin POST refused"
    if not (headers.get("Content-Type") or "").lower().startswith("application/json"):
        return "Content-Type must be application/json"
    return None


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802 - http.server naming
        # a DNS-rebinding page reaches us under its own hostname; refuse it so feed.json (fleet
        # topology, channel, work at risk) cannot be read from a foreign site
        host = (self.headers.get("Host") or "").strip().lower()
        if (host.rsplit(":", 1)[0] if not host.endswith("]") else host) not in LOOPBACK_HOSTS:
            self.send_error(403, "bad Host")
            return
        super().do_GET()

    def do_HEAD(self) -> None:  # noqa: N802
        self.do_GET()

    def do_POST(self) -> None:  # noqa: N802 - http.server naming
        if self.path not in ("/say", "/order", "/act", "/suggest", "/route", "/send"):
            self.send_error(404, "only /say, /order, /act, /suggest, /route and /send accept POST")
            return
        try:
            n = min(int(self.headers.get("Content-Length", 0)), 4096)
        except ValueError:
            n = 0
        raw = self.rfile.read(n)   # read before answering: refusing first makes Windows reset the socket
        why = post_allowed(self.headers)
        if why:
            self.send_error(403, why)
            return
        try:
            body = json.loads(raw or b"{}")
            if self.path == "/route":                       # a suggestion only: no side effects
                msg = route_suggestion(body)
            elif self.path == "/send":
                msg = send(body, body.get("from", "keath"))
            elif self.path == "/act":
                import actions
                if body.get("token"):                       # step 2: Keath confirmed
                    msg = actions.confirm(body["token"])
                    _append({"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "from": "keath (chorus)",
                             "kind": "action", "to": "all", "via": "chorus", **msg,
                             "text": f"{'did' if msg['ok'] else 'tried'} {msg['action']} {msg['target']}: {msg['result'][:200]}"})
                else:                                       # step 1: describe it, hand back a token
                    msg = actions.propose(body.get("action", ""), body.get("target", ""))
            elif self.path == "/suggest":
                msg = post_suggestion(body.get("text", ""), str(body.get("node", "")), body.get("from", "keath"))
            elif self.path == "/order":
                msg = post_order(body.get("text", ""), body.get("to", "any"), body.get("station", "anvil"),
                                 str(body.get("action", "")), str(body.get("target", "")),
                                 str(body.get("due", "")), str(body.get("why", "")))
            else:
                # the page sends no "from" (it is Keath at the keyboard); agents must send their own seat
                msg = say(body.get("text", ""), body.get("to", "claude"), body.get("from", "keath"))
            out, code = json.dumps({"ok": True, "message": msg}).encode(), 200
        except (ValueError, RuntimeError, subprocess.SubprocessError, OSError) as e:
            out, code = json.dumps({"ok": False, "error": str(e)}).encode(), 400
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, *args) -> None:  # keep the console quiet
        pass


# Terminal Depths' fleet mode (Dev-Mentor#291) reads the same feed from its mounted state dir.
TD_FEED = Path(os.environ.get("CHORUS_TD_FEED", "C:/dev/active/Dev-Mentor/state/fleet/feed.json"))


def write_feed(data: dict) -> None:
    blob = json.dumps(data)
    targets = [HERE / "feed.json"]
    if TD_FEED.parent.parent.exists():           # only when Dev-Mentor's state/ exists on this rig
        TD_FEED.parent.mkdir(exist_ok=True)
        targets.append(TD_FEED)
    for t in targets:
        tmp = t.with_suffix(".json.tmp")
        tmp.write_text(blob, encoding="utf-8")
        os.replace(tmp, t)


def loop(stop: threading.Event) -> None:
    while not stop.is_set():
        try:
            write_feed(fetch())
        except (RuntimeError, ValueError, subprocess.SubprocessError, OSError) as e:
            print(f"[chorus] feed not refreshed: {e}")   # the page keeps the last good feed
        stop.wait(15)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--port", type=int, default=PORT)
    a = ap.parse_args()
    if a.once:
        write_feed(fetch())
        print(f"[chorus] wrote {HERE / 'feed.json'}")
        return 0
    stop = threading.Event()
    threading.Thread(target=loop, args=(stop,), daemon=True).start()
    handler = functools.partial(Handler, directory=str(HERE))
    with http.server.ThreadingHTTPServer(("127.0.0.1", a.port), handler) as srv:
        print(f"[chorus] open http://127.0.0.1:{a.port}/   (Ctrl+C to stop)")
        try:
            srv.serve_forever()
        except KeyboardInterrupt:
            stop.set()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
