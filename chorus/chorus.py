#!/usr/bin/env python3
"""chorus.py: the CHORUS cockpit as text, for agents in a terminal (and for Keath on a phone).

    python chorus/chorus.py              # brief: what needs attention, the Minds, the channel, the spine
    python chorus/chorus.py orders [--all]    # work orders for this seat; then: take|working|done|decline <id> --note .. --link ..
    python chorus/chorus.py doctor       # measure the cause of each failing check (read-only)
    python chorus/chorus.py work         # who edits what; checkouts holding unsaved work
    python chorus/chorus.py rig i3       # one rig in detail: checks, disks, RAM, what the Minds said
    python chorus/chorus.py say "text" [--to all|claude (i3 seat)|i3-mind]   # speak as this seat
    python chorus/chorus.py next --as "claude (i3 seat)"   # your single highest-yield move, with steps
    python chorus/chorus.py suggest "text" --as SEAT [--node N]   # suggest a cockpit improvement
    python chorus/chorus.py --json       # the brief as JSON (for other tools)

It reads feed.json (written every 15 s by mindview_feed.py). If that is older than 2 minutes it
refreshes it once with `mindview_feed.py --once`. Read-only except `say`, `suggest` and order moves.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
FEED = HERE / "feed.json"
SEAT = os.environ.get("CHORUS_SEAT", "claude (msi seat)")
RIGS = ["msi", "i3", "l9", "xanadu"]
SILENT_MIN = 15
EXPECTED_DOWN = {"trueform-forge", "rimapi", "desktop-ollama"}
SEEN = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "KiloCore" / "chorus" / "cli.seen"


def seen_path(seat: str) -> Path:
    """Keep the existing MSI cursor; other seats get independent, path-safe cursors."""
    if seat == "claude (msi seat)":
        return SEEN
    digest = hashlib.sha256(seat.encode("utf-8")).hexdigest()[:20]
    return SEEN.with_name(f"cli.{digest}.seen")


def ts(s: str | None) -> float:
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def ago(t: float) -> str:
    m = (time.time() - t) / 60
    return "just now" if m < 1 else f"{m:.0f} min ago" if m < 90 else f"{m / 60:.1f} h ago"


def load() -> dict:
    if not FEED.exists() or time.time() - FEED.stat().st_mtime > 120:
        subprocess.run([sys.executable, str(HERE / "mindview_feed.py"), "--once"], capture_output=True, timeout=90)
    if not FEED.exists():
        sys.exit("No feed.json and xanadu could not be reached. Is the tailnet up?")
    for attempt in range(5):       # Windows denies reads while the feeder's os.replace swaps the file
        try:
            d = json.loads(FEED.read_text(encoding="utf-8"))
            break
        except (PermissionError, json.JSONDecodeError):
            if attempt == 4:
                raise
            time.sleep(0.2)
    d["_age_s"] = time.time() - FEED.stat().st_mtime
    return d


def needs(d: dict) -> list[dict]:
    out = []
    for rig in RIGS[:3]:
        hb = d.get("heartbeats", {}).get(rig)
        if not hb or time.time() - ts(hb.get("at")) > SILENT_MIN * 60:
            out.append({"level": "alarm", "what": f"{rig} is silent", "detail": f"last heartbeat {ago(ts(hb['at'])) if hb else 'never'}"})
            continue
        for c in hb.get("checks", []):
            if not c.get("ok"):
                dx = next((x for x in d.get("doctor") or [] if x.get("key") == f"{rig}:{c['name']}"), None)
                out.append({"level": "notable", "what": f"{rig}: {c['name']} failing",
                            "detail": dx["verdict"] if dx else str(c.get("detail", ""))[:120]})
    b = d.get("backup")
    if not b or b.get("age_h", 99) > 36:
        out.append({"level": "alarm", "what": "off-box backup stale", "detail": f"newest {b['set']} {b['age_h']} h" if b else "none"})
    m = d.get("mirror")
    if not m or m.get("age_h", 99) > 26 or not m.get("ok"):
        out.append({"level": "notable", "what": "git mirrors behind", "detail": f"{m['age_h']} h, {m['failures']} failed" if m else "no receipt"})
    sp = d.get("spine") or {}
    down = [s["name"] for s in sp.get("services", []) if not s.get("up") and s["name"] not in EXPECTED_DOWN]
    if down:
        out.append({"level": "notable", "what": f"spine {sp.get('up')}/{sp.get('total')} up", "detail": "down: " + ", ".join(down)})
    prs = d.get("prs_waiting") or []
    if prs:
        out.append({"level": "notable", "what": f"{len(prs)} PRs wait for a reviewer (no gsv review at their head)",
                    "detail": ", ".join(f"{p['repo']}#{p['number']}" for p in prs[:6])})
    risky = [w for w in (d.get("work") or {}).get("at_risk", []) if w["ahead"] >= 3 or (w["ahead"] and w["dirty"] >= 20)]
    for w in risky[:3]:
        out.append({"level": "notable", "what": f"unpushed work in {w['label']}",
                    "detail": f"{w['branch']} is {w['ahead']} commits ahead, {w['dirty']} files uncommitted, last commit {w['last_commit_h']} h ago"})
    cards = d.get("steward_cards") or []
    if cards:
        out.append({"level": "routine", "what": f"{len(cards)} Steward questions open", "detail": cards[0]["title"][:90]})
    rank = {"alarm": 0, "notable": 1, "routine": 2}
    return sorted(out, key=lambda n: rank[n["level"]])


def unseen(d: dict) -> list[dict]:
    cursor = seen_path(SEAT)
    last = cursor.read_text(encoding="utf-8").strip() if cursor.exists() else ""
    return [m for m in d.get("channel", []) if m.get("at", "") > last and m.get("from") != SEAT
            and m.get("kind") != "read" and str(m.get("text") or "").strip()]


def brief(d: dict, as_json: bool) -> None:
    ns, new = needs(d), unseen(d)
    minds = [e for e in d.get("events", []) if e.get("line")][-3:]
    if as_json:
        print(json.dumps({"feed_age_s": d.get("_age_s"), "needs": ns, "new_messages": new, "minds": minds, "spine": d.get("spine")}, indent=1))
        return
    mark = {"alarm": "!!", "notable": "! ", "routine": "  "}
    print(f"CHORUS brief  (feed {d['_age_s']:.0f} s old)")
    print("Needs:" if ns else "Needs: nothing. The fleet is in tune.")
    for n in ns:
        print(f" {mark[n['level']]} {n['what']}  - {n['detail']}")
    print("Minds:")
    for e in minds:
        print(f"    {e.get('mind')} [{e.get('level')}] {ago(ts(e.get('at')))}: {e.get('line')}")
    print(f"Channel: {len(new)} new" + (":" if new else ""))
    from protocol import read_by
    rb = read_by(d.get("channel", []))
    for m in new[-6:]:
        seen = sorted(rb.get(str(m.get("at")), set()) - {SEAT})
        print(f"    {m.get('from')} -> {m.get('to')}: {str(m.get('text'))[:200]}" + (f"  (read by {', '.join(seen)})" if seen else ""))
    if d.get("channel"):
        cursor = seen_path(SEAT)
        cursor.parent.mkdir(parents=True, exist_ok=True)
        cursor.write_text(max(m.get("at", "") for m in d["channel"]), encoding="utf-8")


def rig(d: dict, rid: str) -> None:
    hb = d.get("heartbeats", {}).get(rid)
    if not hb:
        sys.exit(f"No heartbeat from {rid}. Known: {', '.join(d.get('heartbeats', {}))}")
    print(f"{rid}: {'green' if hb.get('green') else 'NOT green'} · heartbeat {ago(ts(hb.get('at')))} · RAM free {hb.get('ram_avail_mb')} MB")
    for name, disk in (hb.get("disks") or {}).items():
        print(f"  disk {name}: {disk}")
    for c in hb.get("checks", []):
        print(f"  {'ok  ' if c.get('ok') else 'FAIL'} {c['name']:<16} {c.get('ms', '')} ms  {str(c.get('detail', ''))[:100]}")
    said = [e for e in d.get("events", []) if e.get("focus") == rid][-4:]
    if said:
        print("  The Minds said:")
        for e in said:
            print(f"    {ago(ts(e.get('at')))} {e.get('mind')}: {e.get('line')}  (reasons: {', '.join(e.get('reasons', [])) or 'none'})")


def work_view(d: dict) -> None:
    w = d.get("work") or {}
    print("Who is working on what (colony claims):")
    for c in w.get("claims", []):
        print(f"  {c['agent']}  {c['repo']}: {', '.join(c['files'][:6])}{' ...' if len(c['files']) > 6 else ''}  ({c['age_min']} min)")
    risk = w.get("at_risk", [])
    print(f"Work at risk: {len(risk)} checkouts, {sum(r['dirty'] for r in risk)} uncommitted files, "
          f"{sum(1 for r in risk if r['ahead'])} with unpushed commits")
    for r in risk[:12]:
        print(f"  {r['label']:<42} {r['branch'][:34]:<34} ahead {r['ahead']:>3} dirty {r['dirty']:>4} last {r['last_commit_h']} h")
    pr_view(d)


def pr_view(d: dict) -> None:
    """Open PRs by stage. Reviews count by the gsv-review head check only (never reviewDecision)."""
    from nextmove import prs_of
    prs = [p for p in prs_of(d) if p.get("stage") != "draft"]
    if d.get("prs_open") is None and not prs:
        print("Pull requests: not measured yet (the feeder asks GitHub every 5 min)")
        return
    order = ["changes", "needs-review", "stale-review", "approved", "reviewed", "unknown"]
    by = {s: [p for p in prs if p.get("stage") == s] for s in order}
    print("Pull requests (review = a gsv-review marker at the PR's CURRENT head): "
          + (", ".join(f"{len(v)} {k}" for k, v in by.items() if v) or "none open"))
    for s in order:
        for p in by[s][:8]:
            who = (p.get("author") or {}).get("name") or "unattributed"
            revs = f" by {', '.join(p['reviewers'])}" if p.get("reviewers") else ""
            print(f"  [{s:<12}] {p['repo']}#{p['number']:<5} {who:<12} {p.get('title', '')[:70]}{revs}")


def orders_view(d: dict, mine: bool) -> None:
    from shop import orders
    import protocol
    every = protocol.annotate_receipts(orders(d.get("channel", [])), protocol.open_pr_index(d.get("prs_open")))
    os_ = [o for o in every if not mine or o["to"] in (SEAT, "any")]
    open_ = [o for o in os_ if o["status"] not in ("done", "declined")]
    print(f"Work orders: {len(open_)} open" + (" for this seat" if mine else ""))
    for o in os_[-15:]:
        # a seat's "done" is a report until the owner record agrees: verified / reported / NOT confirmed
        st = f"done: {o['receipt']}" if o.get("receipt") else o["status"]
        print(f"  {o['id']}  [{st:<8}] {o['station']:<7} to {o['to']:<18} by {o['by'] or '-':<18} {o['text'][:90]}")
        if o["note"] or o["link"]:
            print(f"      {o['note'][:120]} {o['link']}")


def order_status(oid: str, status: str, note: str, link: str) -> None:
    if status not in ("taken", "working", "done", "declined"):
        sys.exit("status must be taken|working|done|declined")
    _post({"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "from": SEAT, "kind": "order-status",
           "id": oid, "status": status, "note": " ".join(note.split())[:400], "link": link})


def _post(msg: dict) -> None:
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "xanadu",
                        "mkdir -p ~/steward/cockpit && cat >> ~/steward/cockpit/channel.jsonl"],
                       input=json.dumps(msg) + chr(10), capture_output=True, text=True, timeout=30)
    print("sent" if r.returncode == 0 else f"not sent (ssh exit {r.returncode})")


def act_orders(d: dict) -> None:
    """Run action orders addressed to this seat: {kind: order, station: act, action, target}.
    Only orders Keath posted count (his posting is the confirm); the action must be on the
    allowlist in actions.py. Each run posts the {kind: action} receipt and closes the order."""
    import actions
    from shop import orders
    raw = {m.get("id"): m for m in d.get("channel", []) if m.get("kind") == "order"}
    todo = [o for o in orders(d.get("channel", [])) if o["status"] == "posted" and o["to"] in (SEAT, "any")
            and o["station"] == "act"]
    if not todo:
        print("no action orders")
        return
    for o in todo:
        m = raw.get(o["id"], {})
        if not str(m.get("from", "")).startswith("keath"):
            order_status(o["id"], "declined", "action orders are only run when Keath posts them", "")
            continue
        order_status(o["id"], "taken", f"running {m.get('action')} {m.get('target')}", "")
        try:
            tok = actions.propose(str(m.get("action", "")), str(m.get("target", "")))
            res = actions.confirm(tok["token"])
        except ValueError as e:
            order_status(o["id"], "declined", f"not run: {e}", "")
            continue
        _post({"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "from": SEAT, "kind": "action", "to": "all",
               "order": o["id"], **res, "text": f"{'did' if res['ok'] else 'tried'} {res['action']} {res['target']}: {res['result'][:200]}"})
        order_status(o["id"], "done" if res["ok"] else "declined",
                     f"{res['action']} {res['target']}: {'ok' if res['ok'] else 'failed'} in {res['ms']} ms - {res['result'][:200]}", "")


def suggestion_line(text: str, node: str = "", seat: str | None = None) -> dict:
    """The shared protocol's suggestion line, {kind: suggestion, from, text}. It stays open on the
    page and in `next` until someone posts an order whose ref is its id (suggestion:<at>)."""
    seat = (seat or SEAT).strip()
    text = " ".join(str(text).split())[:500]
    if not text:
        sys.exit("empty suggestion")
    if not seat or seat.lower().startswith("keath"):
        sys.exit("an agent never signs as Keath; use --as with your own seat (Keath suggests from the page)")
    msg = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "from": seat, "to": "claude (msi seat)",
           "kind": "suggestion", "text": text, "via": "chorus-cli"}
    if node:
        msg["node"] = node[:60]
    return msg


def suggest(text: str, node: str = "", seat: str | None = None) -> None:
    """Suggest an improvement to the cockpit itself, as a shared-protocol suggestion line."""
    _post(suggestion_line(text, node, seat))


def next_move(d: dict, seat: str, as_json: bool = False) -> None:
    """The single highest-yield item this seat can do (nextmove.py), with who/what/where/when/why and steps."""
    import nextmove
    plan = nextmove.plan_for(seat, d)
    if as_json:
        print(json.dumps(plan, indent=1, default=str))
    else:
        print(nextmove.render(seat, plan))


def say(text: str, to: str) -> None:
    text = " ".join(text.split())[:600]
    if not text:
        sys.exit("empty message")
    msg = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "from": SEAT, "to": to, "text": text}
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "xanadu",
                        "mkdir -p ~/steward/cockpit && cat >> ~/steward/cockpit/channel.jsonl"],
                       input=json.dumps(msg) + "\n", capture_output=True, text=True, timeout=30)
    print("sent" if r.returncode == 0 else f"not sent (ssh exit {r.returncode})")


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", nargs="?", default="brief", choices=["brief", "rig", "say", "suggest", "next", "work", "doctor", "act-orders", "orders", "take", "working", "done", "decline"])
    ap.add_argument("arg", nargs="?")
    ap.add_argument("--to", default="all")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--note", default="")
    ap.add_argument("--link", default="")
    ap.add_argument("--all", action="store_true", help="orders: show every seat's orders")
    ap.add_argument("--as", dest="seat", default=None, help="next/suggest: the seat to act as (default CHORUS_SEAT)")
    ap.add_argument("--node", default="", help="suggest: the node or view it concerns")
    a = ap.parse_args()
    if a.cmd == "say":
        say(a.arg or "", a.to)
    elif a.cmd == "suggest":
        suggest(a.arg or "", a.node or (a.to if a.to != "all" else ""), a.seat)
    elif a.cmd == "next":
        next_move(load(), a.seat or SEAT, a.json)
    elif a.cmd == "act-orders":
        act_orders(load())
    elif a.cmd == "orders":
        orders_view(load(), not a.all)
    elif a.cmd in ("take", "working", "done", "decline"):
        order_status(a.arg or sys.exit("give the order id"), {"take": "taken", "decline": "declined"}.get(a.cmd, a.cmd), a.note, a.link)
    elif a.cmd == "doctor":
        from doctor import diagnose
        for x in diagnose(load()):
            print(f"{x['key']}: {x['verdict']}")
            for e in x["evidence"]:
                print(f"    {e}")
    elif a.cmd == "work":
        work_view(load())
    elif a.cmd == "rig":
        rig(load(), (a.arg or "msi").lower())
    else:
        brief(load(), a.json)


if __name__ == "__main__":
    main()
