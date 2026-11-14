"""reroute.py: give an untaken work order ONE second chance, mechanically (no LLM).

An order that has sat "posted" for more than STALE_MIN minutes, addressed to a target that cannot be
reached on the channel or cannot execute that kind of order, is re-routed exactly once:

    1. a new order line to the router's best capable, reachable target, with `ref` = the original id;
    2. an order-status line on the original: {status: "rerouted", note: "to <seat>: <reason>"}
       (shop.orders() counts a re-routed original as closed);
    3. when the new target is a cloud seat (gpt-6, codex, muse), the order is mirrored to the PR/issue
       the way mindview_feed.send() does it (a prepared `gh` command unless CHORUS_ALLOW_GH_COMMENT=1).

What is left alone: a reachable target that can do the work (it is only slow), orders to "any",
orders that are themselves re-routes (no ping-pong), and any order already re-routed by anyone
(a child order whose `ref` names it, a "rerouted" status, or this rig's local ledger).
A review of a Claude-authored PR (or of a PR whose author is unknown) never goes to a Claude seat.

    plan(channel, feed, now)  -> [{id, from_to, to, kind, reason, text, ...}]   pure, writes nothing
    apply(plan, append, ...)  -> [{id, new_id, to, ok, error}]                   writes channel lines
Stdlib only.
"""
from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path

import router
from shop import orders

STALE_MIN = 15
SEEN_H = 3                       # a seat unseen this long counts as unreachable
SEAT = os.environ.get("CHORUS_SEAT", "claude (msi seat)")
LEDGER = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "KiloCore" / "chorus" / "rerouted.json"
PR_REF = re.compile(r"\b([\w.-]+)#(\d+)\b")


def _ts(s) -> float:
    return router._ts(s)


def _ref_of(m: dict, ids: set[str]) -> str:
    """The order this line re-routes: `ref` "reroute:<id>" (the seats' convention) or a bare order id.
    Other refs ("reply:...", "decision:...", a PR) are not re-routes."""
    ref = str(m.get("ref") or "")
    if ref.startswith("reroute:"):
        return ref[len("reroute:"):]
    return ref if ref in ids else ""


def already_rerouted(channel: list[dict], ledger: set[str] | None = None) -> set[str]:
    """Ids someone already re-routed: a child order names them in `ref`, a status says so, or our ledger."""
    done = set(ledger or ())
    ids = {m.get("id") for m in channel if m.get("kind") == "order"}
    for m in channel:
        if m.get("kind") == "order" and _ref_of(m, ids):
            done.add(_ref_of(m, ids))
        elif m.get("kind") == "order-status" and (m.get("status") == "rerouted"
                                                   or re.search(r"re-?routed", str(m.get("note", "")), re.I)):
            done.add(str(m.get("id")))
    return done


def kind_of(o: dict) -> str:
    """The kind of work an order line asks for (orders do not store it, so read station and words)."""
    if o.get("station") == "act":
        return "action-order"
    if o.get("station") == "cockpit":
        return "suggest"
    head = o.get("text", "")[:120]
    if o.get("station") == "pegs" or (re.search(r"\breview\b", head, re.I) and PR_REF.search(head)):
        return "review-request"
    return "order"


def pr_node(text: str, feed: dict) -> dict:
    """The PR an order is about, with its author's vendor when the feed knows it."""
    m = PR_REF.search(text or "")
    if not m:
        return {}
    repo, num = m.group(1), m.group(2)
    known = [p for p in (feed.get("prs_recent") or []) + (feed.get("prs_waiting") or [])
             if str(p.get("number")) == num and str(p.get("repo", "")).lower() == repo.lower()]
    p = next((x for x in known if x.get("agent")), known[0] if known else {})
    return {"kind": "pr", "repo": repo, "number": num, "agent": p.get("agent", ""), "title": p.get("title", ""),
            "url": p.get("url") or f"https://github.com/GSV-Sublime-Optimization/{repo}/pull/{num}"}


def reachability(to: str, feed: dict, now: float) -> tuple[bool, str]:
    """Can `to` hear an order on the channel right now? -> (reachable, why not)."""
    tid = router.target_id(to)
    if not tid:
        return False, f"{to} is not a known target"
    t = router.TARGETS[tid]
    if t.get("mirror") or t["type"] == "cloud":
        return False, f"{t['label']} does not read the channel"
    if t["type"] != "seat":
        return False, f"{t['label']} is not a seat that takes orders"
    seen = router.availability(feed, now).get(tid, {}).get("seen", 0.0)
    if now - seen > SEEN_H * 3600:
        return False, f"{t['label']} not seen in {SEEN_H} h"
    return True, ""


def _choose(kind: str, node: dict, text: str, feed: dict, now: float, exclude: str) -> tuple[str, str] | None:
    """The router's best target that can execute `kind` and can be reached (a cloud seat counts as
    reachable through its GitHub mirror). Never a Claude seat for a review of a Claude/unknown PR."""
    author = router.node_author(node)
    for c in router._candidates(kind, node, text, feed, []):
        tid = c["to"]
        if tid == exclude or tid in ("all",) or not router.can_take(tid, kind):
            continue
        vendor = router.TARGETS[tid]["vendor"]
        if kind == "review-request" and vendor == "claude" and author in ("claude", ""):
            continue                           # second-actor rule; unknown author is treated as Claude
        if router.TARGETS[tid].get("mirror"):
            if kind not in ("review-request", "order") or not node.get("url"):
                continue                       # a cloud seat is reached only through a PR/issue
            return tid, c["because"] or "independent actor via GitHub"
        ok, _ = reachability(tid, feed, now)
        if ok:
            return tid, c["because"] or "can take it"
    return None


def load_ledger() -> set[str]:
    try:
        return set(json.loads(LEDGER.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        return set()


def save_ledger(ids: set[str]) -> None:
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    LEDGER.write_text(json.dumps(sorted(ids)), encoding="utf-8")


def plan(channel: list[dict], feed: dict | None = None, now: float | None = None,
         ledger: set[str] | None = None, only_to: str | None = None) -> list[dict]:
    """Which stale orders to re-route, and where. Pure: reads, writes nothing."""
    feed, now = feed or {}, now or time.time()
    raw = {m["id"]: m for m in channel if m.get("kind") == "order" and m.get("id")}
    gone = already_rerouted(channel, ledger)
    out = []
    for o in orders(channel):
        line = raw.get(o["id"], {})
        if o["status"] != "posted" or o["id"] in gone or _ref_of(line, set(raw)):
            continue
        if now - _ts(o["at"]) < STALE_MIN * 60 or o["to"] in ("any", "", None):
            continue
        if only_to and router.target_id(o["to"]) != router.target_id(only_to) and o["to"] != only_to:
            continue
        kind = kind_of(o)
        reach, why_not = reachability(o["to"], feed, now)
        able = router.can_take(o["to"], kind)
        if reach and able:
            continue                           # reachable and capable: only slow, leave it alone
        reason = why_not if not reach else f"{router.TARGETS[router.target_id(o['to'])]['label']} cannot execute a {kind}"
        node = pr_node(o["text"], feed) if kind in ("review-request", "order") else {}
        node = {**node, "title": node.get("title") or o["text"][:200]}
        pick = _choose(kind, node, o["text"], feed, now, router.target_id(o["to"]) or o["to"])
        mins = int((now - _ts(o["at"])) / 60)
        entry = {"id": o["id"], "from_to": o["to"], "kind": kind, "age_min": mins, "reason": reason,
                 "station": o["station"], "text": o["text"], "why": o.get("why", ""), "due": o.get("due", ""),
                 "node": node}
        if not pick:
            out.append({**entry, "to": None, "skip": "no capable, reachable target"})
            continue
        out.append({**entry, "to": pick[0], "because": pick[1]})
    return out


def apply(items: list[dict], append, gh_comment=None, sender: str = SEAT, now: float | None = None,
          ledger: set[str] | None = None, persist: bool = True) -> list[dict]:
    """Write each re-route: the new order (ref = original id), then the original's "rerouted" status,
    then the ledger. `append(msg)` writes one channel line; `gh_comment(t, kind, sender, about, text,
    why, when, url, base, ref)` mirrors to a cloud seat (mindview_feed._gh_comment)."""
    ledger = load_ledger() if ledger is None else ledger
    results = []
    for n, it in enumerate(i for i in items if i.get("to")):
        if it["id"] in ledger:
            continue
        t = router.TARGETS[it["to"]]
        stamp = time.gmtime(now or time.time())
        new_id = "o-" + time.strftime("%m%d-%H%M%S", stamp) + f"-rr{n}"
        at = time.strftime("%Y-%m-%dT%H:%M:%SZ", stamp)
        text = " ".join(f"Re-routed from {it['id']} ({it['reason']}): {it['text']}".split())[:600]
        station = "pegs" if it["kind"] == "review-request" else ("anvil" if it["station"] == "act" else it["station"])
        msg = {"at": at, "from": sender, "kind": "order", "id": new_id, "to": it["to"], "station": station,
               "text": text, "ref": it["id"], "via": "reroute"}
        if it.get("why"):
            msg["why"] = it["why"][:240]
        if it.get("due"):
            msg["due"] = it["due"][:40]
        try:
            append(msg)
            append({"at": at, "from": sender, "kind": "order-status", "id": it["id"], "status": "rerouted",
                    "note": f"to {it['to']}: {it['reason']}"[:400], "link": "", "via": "reroute", "ref": new_id})
            mirror = None
            if t.get("mirror") and gh_comment:
                url = it["node"].get("url", "")
                mirror = gh_comment(t, it["kind"], sender, router.node_label(it["node"]), text, it.get("why", ""), "now",
                                    url, {"at": at, "from": sender, "to": it["to"], "intent": it["kind"],
                                          "via": "reroute", "where": "github"}, ref=new_id)
            ledger.add(it["id"])
            results.append({"id": it["id"], "new_id": new_id, "to": it["to"], "ok": True,
                            "mirror": (mirror or {}).get("summary")})
        except (RuntimeError, OSError, ValueError) as e:
            results.append({"id": it["id"], "new_id": new_id, "to": it["to"], "ok": False, "error": str(e)[:200]})
    if persist and results:
        save_ledger(ledger)
    return results


def describe(items: list[dict]) -> list[str]:
    lines = []
    for it in items:
        head = f"{it['id']} ({it['age_min']} min, {it['kind']}, to {it['from_to']}: {it['reason']})"
        lines.append(f"{head} -> SKIP: {it['skip']}" if not it.get("to") else f"{head} -> {it['to']} ({it['because']})")
    return lines
