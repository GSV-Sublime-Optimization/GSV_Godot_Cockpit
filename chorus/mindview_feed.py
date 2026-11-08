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
    for line in open(cf, encoding="utf-8", errors="replace").read().splitlines()[-60:]:
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
        _prs["items"] = [{"repo": p["repository"]["name"], "number": p["number"], "title": p["title"][:110],
                          "url": p["url"], "created": p["createdAt"]} for p in json.loads(r.stdout or "[]")]
        _prs["at"] = time.time()
    return _prs["items"]


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
    data["claude_activity"] = claude_activity()
    data["spine"] = spine()
    # cache the shared channel locally so the Claude prompt hook can read it without a network call
    LOCAL.mkdir(parents=True, exist_ok=True)
    (LOCAL / "channel.cache.jsonl").write_text("\n".join(json.dumps(m) for m in data.get("channel", [])), encoding="utf-8")
    return data


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
SEATS = {"keath": "keath (chorus)", "claude (msi seat)": "claude (msi seat)",
         "claude (i3 seat)": "claude (i3 seat)", "i3-mind": "i3-mind"}


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


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self) -> None:  # noqa: N802 - http.server naming
        if self.path != "/say":
            self.send_error(404, "only /say accepts POST")
            return
        try:
            n = min(int(self.headers.get("Content-Length", 0)), 4096)
            body = json.loads(self.rfile.read(n) or b"{}")
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
