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
print(json.dumps({"events": [e for e in events if not e.get("simulated")][-200:], "heartbeats": beats, "served_at": time.time()}))
PY"""


def fetch() -> dict:
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "xanadu", REMOTE],
                       capture_output=True, text=True, timeout=40, encoding="utf-8", errors="replace")
    if r.returncode:
        raise RuntimeError(f"xanadu unreachable (ssh exit {r.returncode})")
    return json.loads(r.stdout.strip().splitlines()[-1])


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
