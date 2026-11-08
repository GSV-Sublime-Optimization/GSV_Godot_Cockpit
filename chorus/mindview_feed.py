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
print(json.dumps({"events": [e for e in events if not e.get("simulated")][-200:], "heartbeats": beats,
                  "backup": backup, "mirror": mirror, "steward_cards": cards, "served_at": now}))
PY"""

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
    return data


def write_feed(data: dict) -> None:
    tmp = HERE / "feed.json.tmp"
    tmp.write_text(json.dumps(data), encoding="utf-8")
    os.replace(tmp, HERE / "feed.json")


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
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(HERE))
    with http.server.ThreadingHTTPServer(("127.0.0.1", a.port), handler) as srv:
        print(f"[chorus] open http://127.0.0.1:{a.port}/   (Ctrl+C to stop)")
        try:
            srv.serve_forever()
        except KeyboardInterrupt:
            stop.set()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
