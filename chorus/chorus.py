#!/usr/bin/env python3
"""chorus.py: the CHORUS cockpit as text, for agents in a terminal (and for Keath on a phone).

    python chorus/chorus.py              # brief: what needs attention, the Minds, the channel, the spine
    python chorus/chorus.py orders [--all]    # work orders for this seat; then: take|working|done|decline <id> --note .. --link ..
    python chorus/chorus.py doctor       # measure the cause of each failing check (read-only)
    python chorus/chorus.py work         # who edits what; checkouts holding unsaved work
    python chorus/chorus.py rig i3       # one rig in detail: checks, disks, RAM, what the Minds said
    python chorus/chorus.py say "text" [--to all|claude (i3 seat)|i3-mind]   # speak as this seat
    python chorus/chorus.py route "text" [--node check:i3/docker]   # who/where/when/why the router suggests
    python chorus/chorus.py send "text" [--node ..] [--to ..] [--where ..] [--kind ..] [--when ..]   # route + send
    python chorus/chorus.py reroute [--dry-run|--apply] [--to i3-mind]   # stale orders to seats that can't act: one re-route
    python chorus/chorus.py --json       # the brief as JSON (for other tools)

It reads feed.json (written every 15 s by mindview_feed.py). If that is older than 2 minutes it
refreshes it once with `mindview_feed.py --once`. Read-only except `say`, `send` and order moves.
"""
from __future__ import annotations

import argparse
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
        out.append({"level": "notable", "what": f"{len(prs)} PRs wait for a reviewer",
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
    last = SEEN.read_text().strip() if SEEN.exists() else ""
    return [m for m in d.get("channel", []) if m.get("at", "") > last and m.get("from") != SEAT
            and m.get("kind") != "read" and str(m.get("text") or "").strip()]


def brief(d: dict, as_json: bool) -> None:
    ns, new = needs(d), unseen(d)
    minds = [e for e in d.get("events", []) if e.get("line")][-3:]
    if as_json:
        print(json.dumps({"needs": ns, "new_messages": new, "minds": minds, "spine": d.get("spine")}, indent=1))
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
    for m in new[-6:]:
        print(f"    {m.get('from')} -> {m.get('to')}: {str(m.get('text'))[:200]}")
    if d.get("channel"):
        SEEN.parent.mkdir(parents=True, exist_ok=True)
        SEEN.write_text(max(m.get("at", "") for m in d["channel"]))


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


CLOSED_SHOWN = 5


def orders_view(d: dict, mine: bool) -> None:
    """Every OPEN order first (posted/taken/working, oldest first), then at most the last 5 closed,
    so open work never scrolls off behind finished tickets."""
    from shop import CLOSED, orders
    os_ = [o for o in orders(d.get("channel", [])) if not mine or o["to"] in (SEAT, "any")]
    open_ = sorted((o for o in os_ if o["status"] not in CLOSED), key=lambda o: o["at"] or "")
    closed = sorted((o for o in os_ if o["status"] in CLOSED),
                    key=lambda o: (o["history"][-1].get("at") or "") if o["history"] else (o["at"] or ""))[-CLOSED_SHOWN:]
    print(f"Work orders: {len(open_)} open" + (" for this seat" if mine else ""))
    for o in open_ + closed:
        if o is (closed[0] if closed else None):
            print(f"  -- last {len(closed)} closed --")
        print(f"  {o['id']}  [{o['status']:<8}] {o['station']:<7} to {o['to']:<18} by {o['by'] or '-':<18} {o['text'][:90]}")
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


def suggest(text: str, node: str) -> None:
    """Suggest an improvement to the cockpit itself; it lands as an order for the MSI seat."""
    text = " ".join(text.split())[:500]
    if not text:
        sys.exit("empty suggestion")
    now = time.gmtime()
    _post({"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", now), "from": SEAT, "kind": "order",
           "id": "s-" + time.strftime("%m%d-%H%M%S", now), "to": "claude (msi seat)", "station": "cockpit",
           "text": f"SUGGEST{(' [' + node[:60] + ']') if node else ''}: {text}"})


def say(text: str, to: str) -> None:
    text = " ".join(text.split())[:600]
    if not text:
        sys.exit("empty message")
    msg = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "from": SEAT, "to": to, "text": text}
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "xanadu",
                        "mkdir -p ~/steward/cockpit && cat >> ~/steward/cockpit/channel.jsonl"],
                       input=json.dumps(msg) + "\n", capture_output=True, text=True, timeout=30)
    print("sent" if r.returncode == 0 else f"not sent (ssh exit {r.returncode})")


def node_from_ref(d: dict, ref: str | None) -> dict | None:
    """--node: JSON, or a short ref read against the feed: rig:i3, check:i3/docker, pr:dev#429, svc:litellm."""
    if not ref:
        return None
    ref = ref.strip()
    if ref.startswith("{"):
        return json.loads(ref)
    kind, _, rest = ref.partition(":")
    if kind == "rig":
        hb = d.get("heartbeats", {}).get(rest) or {}
        bad = [c for c in hb.get("checks", []) if not c.get("ok")]
        return {"kind": "rig", "id": rest, "rig": rest, "failing": bool(bad),
                "detail": "; ".join(f"{c['name']} failing" for c in bad)}
    if kind == "check":
        rig_id, _, check = rest.partition("/")
        c = next((x for x in (d.get("heartbeats", {}).get(rig_id) or {}).get("checks", []) if x.get("name") == check), {})
        dx = next((x for x in d.get("doctor") or [] if x.get("key") == f"{rig_id}:{check}"), {})
        return {"kind": "check", "rig": rig_id, "check": check, "name": f"{rig_id} {check}", "ok": c.get("ok", False),
                "detail": str(c.get("detail", ""))[:140], "verdict": dx.get("verdict", "")}
    if kind == "pr":
        repo, _, num = rest.partition("#")
        waiting = next((p for p in d.get("prs_waiting") or [] if p["repo"] == repo and str(p["number"]) == num), None)
        recent = next((p for p in d.get("prs_recent") or [] if p["repo"] == repo and str(p["number"]) == num), None)
        p = waiting or recent or {}
        return {"kind": "pr", "repo": repo, "number": num, "title": p.get("title", ""), "waiting": bool(waiting),
                "agent": (recent or {}).get("agent", ""), "state": (recent or {}).get("state", ""),
                "url": p.get("url") or f"https://github.com/GSV-Sublime-Optimization/{repo}/pull/{num}"}
    if kind == "svc":
        s = next((x for x in (d.get("spine") or {}).get("services", []) if x.get("name") == rest), {})
        return {"kind": "svc", "name": rest, "down": s.get("up") is False and rest not in EXPECTED_DOWN}
    return {"kind": kind or "node", "name": rest or ref}


def route_cmd(d: dict, text: str, node_ref: str | None, as_json: bool) -> dict:
    import router
    r = router.route(text, node_from_ref(d, node_ref), d)
    if as_json:
        print(json.dumps(r, indent=1))
        return r
    print(r["preview"])
    print(f"  kind {r['draft']['kind']} · to {r['to']} · where {r['where']} ({r['reach']}) · when {r['when']}"
          f" · confidence {r['confidence']}")
    print(f"  draft: {r['draft']['text']}")
    if r["why"]:
        print(f"  why: {r['why']}")
    print(f"  because: {r['reasons']}")
    for a in r["alternatives"]:
        print(f"  or {a['label']} via {a['where']} ({a['reach']}, score {a['score']}): {a['because']}")
    for c in r["capability"]:
        print(f"  atlas: {c['id']}")
    return r


def send_cmd(d: dict, text: str, node_ref: str | None, to: str | None, where: str | None, kind: str | None,
             when: str | None, why: str | None) -> dict:
    """Route, apply the overrides, dispatch as this seat (never as Keath)."""
    import router
    import mindview_feed
    node = node_from_ref(d, node_ref)
    r = router.route(f"{text} {when}" if when else text, node, d, kind=kind, to=to)
    if when:
        r["when"], r["due"] = router.parse_when(when)
    body = {"kind": r["draft"]["kind"], "to": r["to"], "where": where or r["where"], "text": r["draft"]["text"],
            "why": why or r["why"], "due": r["due"], "when": r["when"], "node": node or {}, "station": r["draft"]["station"]}
    res = mindview_feed.send(body, SEAT)
    print(res.get("summary", "sent"))
    if res.get("answer"):
        print(res["answer"])
    if res.get("prepared"):
        print(json.dumps(res["prepared"], indent=1))
    return res


def reroute_cmd(d: dict, do_apply: bool, only_to: str | None = None) -> list[dict]:
    """Stale orders whose target cannot be reached or cannot execute them get ONE re-route (reroute.py)."""
    import reroute
    import mindview_feed
    ledger = reroute.load_ledger()
    items = reroute.plan(d.get("channel", []), d, ledger=ledger, only_to=only_to)
    print(f"reroute {'APPLY' if do_apply else 'dry run'}: {len(items)} stale order(s) to re-route"
          + (f" (only those to {only_to})" if only_to else ""))
    for line in reroute.describe(items):
        print("  " + line)
    if not do_apply:
        return items
    res = reroute.apply(items, mindview_feed._append, mindview_feed._gh_comment, SEAT, ledger=ledger)
    for r in res:
        print(f"  {r['id']} -> {r['new_id']} to {r['to']}: {'ok' if r['ok'] else 'FAILED ' + r.get('error', '')}"
              + (f"; {r['mirror']}" if r.get("mirror") else ""))
    return res


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", nargs="?", default="brief", choices=["brief", "rig", "say", "suggest", "work", "doctor", "act-orders", "orders", "take", "working", "done", "decline", "route", "send", "reroute"])
    ap.add_argument("arg", nargs="?")
    ap.add_argument("--to", default=None)
    ap.add_argument("--node", default=None, help="route/send: JSON or rig:i3, check:i3/docker, pr:dev#429, svc:litellm")
    ap.add_argument("--where", default=None)
    ap.add_argument("--kind", default=None)
    ap.add_argument("--when", default=None)
    ap.add_argument("--why", default=None)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--note", default="")
    ap.add_argument("--link", default="")
    ap.add_argument("--all", action="store_true", help="orders: show every seat's orders")
    ap.add_argument("--dry-run", action="store_true", help="reroute: show what it would do (the default)")
    ap.add_argument("--apply", action="store_true", help="reroute: write the re-routes to the channel")
    a = ap.parse_args()
    if a.cmd == "say":
        say(a.arg or "", a.to or "all")
    elif a.cmd == "suggest":
        suggest(a.arg or "", a.to or "")
    elif a.cmd == "route":
        route_cmd(load(), a.arg or "", a.node, a.json)
    elif a.cmd == "send":
        try:
            send_cmd(load(), a.arg or "", a.node, a.to, a.where, a.kind, a.when, a.why)
        except (ValueError, RuntimeError) as e:
            sys.exit(f"not sent: {e}")
    elif a.cmd == "reroute":
        reroute_cmd(load(), a.apply and not a.dry_run, a.to)
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
