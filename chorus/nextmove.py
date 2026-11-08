"""nextmove.py: the single highest-yield thing a seat can do next, from CHORUS's own feed.

The logic mirrors HOLOMIND's dispatch.py (#15) without importing it: build the colony's work
queue, score each item for yield (printed, so it can be argued with), keep only what this seat
may do, and hand back who / what / where / when / why plus numbered steps.

Rules (the colony's, shared with HOLOMIND):
- Never assign a review to the PR's author. Every agent posts as one GitHub account, so the author
  is read from the branch prefix (shop.agent_of_branch), or from the PR body when the branch says
  nothing; when only the agent family is known ("a Claude"), every seat of that family is excluded.
- One open order per seat: a seat holding an order (posted to it, taken or working) gets that
  order back until it is closed. Items another seat already holds an order for are skipped.
- Keath-only decisions (merges, Steward cards) go to Keath.
- Anything a doctor verdict says needs hands on hardware (BIOS, VT-x, power, cables...) goes to Keath.
"""
from __future__ import annotations

import re
import time

import protocol
from shop import agent_of_branch, orders as fold_orders

KEATH = "keath (chorus)"
SEATS = {
    "claude (msi seat)": {"family": "Claude", "home": "msi", "rigs": ["msi", "l9", "xanadu"],
                          "skills": ["review", "python", "docker", "chorus", "cockpit", "dev-mentor", "spine", "msi",
                                     "mirror", "backup", "colony", "docs"]},
    "claude (i3 seat)": {"family": "Claude", "home": "i3", "rigs": ["i3", "xanadu"],
                         "skills": ["review", "python", "godot", "cockpit", "holomind", "docs", "colony", "fleet",
                                    "windows", "radio", "storage"]},
    "gpt-6": {"family": "GPT-6", "home": "cloud", "rigs": [], "skills": ["review", "godot", "entity", "studio", "fleet", "mind"]},
    "codex": {"family": "Codex", "home": "cloud", "rigs": [], "skills": ["review", "python", "tests", "docs", "echoes"]},
    "muse": {"family": "Muse", "home": "cloud", "rigs": [], "skills": ["design", "godot", "cockpit", "atlas", "hologram"]},
    KEATH: {"family": "Keath", "home": "keath", "rigs": [], "skills": []},
}
ALIASES = {"keath": KEATH, "msi": "claude (msi seat)", "i3": "claude (i3 seat)", "gpt6": "gpt-6"}
KEATH_ONLY = ("decision", "merge", "hands")
BASE = {"order": 100, "redo": 65, "merge": 70, "rig": 60, "hands": 60, "fix": 55, "decision": 50, "save": 45,
        "review": 40, "reply": 30, "suggestion": 25}
HANDS_ON = ("bios", "vt-x", "virtualization", "firmware", "power", "physical", "unplug", "cable", "keyboard at",
            "at the i3", "at the msi", "reboot into")
CHECK_RIG = {"backup": "msi", "mirror": "msi", "spine": "msi", "save": "msi"}
OWNER_SEAT = "claude (msi seat)"          # CHORUS's own seat: suggestions for this cockpit go here


def seat_of(name: str) -> str:
    n = (name or "").strip().lower()
    return ALIASES.get(n, n)


def _family(name: str) -> str:
    for fam in ("Claude", "GPT-6", "Codex", "Muse", "Sol"):
        if fam.lower() in (name or "").lower():
            return fam
    return name or ""


def pr_author(head_ref: str, body: str = "") -> dict | None:
    """{'name', 'family', 'rig'} of the agent that opened a PR, or None if nothing says."""
    who = agent_of_branch(head_ref or "")
    if who:
        name, rig = who
        specific = name in ("MSI Claude", "i3 Claude") or _family(name) != "Claude"
        return {"name": name, "family": _family(name), "rig": rig if specific else None}
    if re.search(r"generated with \[?claude code|claude-session:", body or "", re.I):
        return {"name": "a Claude", "family": "Claude", "rig": None}
    return None


def is_author(seat: str, author: dict | None) -> bool:
    s = SEATS.get(seat)
    if not s or not author or author.get("family") != s["family"]:
        return False
    rig = author.get("rig")
    return rig is None or rig == s["home"] or s["home"] == "cloud"


# ---------------------------------------------------------------- the queue, from feed.json
def _hands(verdict: str) -> bool:
    v = (verdict or "").lower()
    return any(h in v for h in HANDS_ON)


def queue(d: dict, now: float | None = None) -> list[dict]:
    """Every work item CHORUS can see, with the rig or PR it concerns. Unscored, unfiltered."""
    now = now or time.time()
    out: list[dict] = []
    doctor = {x.get("key"): x for x in d.get("doctor") or []}
    for rig in ("msi", "i3", "l9"):
        hb = (d.get("heartbeats") or {}).get(rig)
        if not hb or now - protocol._ts(hb.get("at")) > 15 * 60:
            out.append({"kind": "rig", "rig": rig, "level": "alarm", "id": f"rig:{rig}:silent",
                        "title": f"{rig} is silent (no heartbeat in 15 min)", "since": hb.get("at") if hb else None,
                        "why": "a silent rig hides every other fact about it"})
            continue
        for c in hb.get("checks", []):
            if c.get("ok"):
                continue
            dx = doctor.get(f"{rig}:{c['name']}") or {}
            verdict = dx.get("verdict") or str(c.get("detail", ""))[:160]
            kind = "hands" if _hands(dx.get("verdict", "")) else "rig"
            out.append({"kind": kind, "rig": rig, "level": "notable", "id": f"rig:{rig}:{c['name']}",
                        "title": f"{rig}: {c['name']} failing" + ("  [needs hands on the machine]" if kind == "hands" else ""),
                        "why": verdict, "evidence": dx.get("evidence", [])[:4], "since": hb.get("at")})
    b = d.get("backup")
    if not b or b.get("age_h", 99) > 36:
        out.append({"kind": "rig", "rig": "msi", "level": "alarm", "id": "backup:stale", "title": "off-box backup is stale",
                    "why": f"newest finished set {b['set']} is {b['age_h']} h old" if b else "no finished set"})
    m = d.get("mirror")
    if not m or m.get("age_h", 99) > 26 or not m.get("ok"):
        out.append({"kind": "rig", "rig": "msi", "level": "notable", "id": "mirror:behind", "title": "git mirrors are behind",
                    "why": f"receipt {m['age_h']} h old, {m.get('failures')} failed" if m else "no mirror receipt"})
    from chorus import EXPECTED_DOWN   # noqa: PLC0415 - one list of parked services, kept in chorus.py
    for s in (d.get("spine") or {}).get("services", []):
        if not s.get("up") and s.get("name") not in EXPECTED_DOWN:
            out.append({"kind": "rig", "rig": "msi", "level": "notable", "id": f"spine:{s['name']}",
                        "title": f"msi spine service down: {s['name']}", "why": f"tier {s.get('tier')}, did not answer the spine probe"})
    for w in (d.get("work") or {}).get("at_risk", []) if isinstance(d.get("work"), dict) else []:
        if w.get("ahead", 0) >= 3 or (w.get("ahead") and w.get("dirty", 0) >= 20):
            out.append({"kind": "save", "rig": "msi", "level": "notable", "id": f"save:{w['label']}",
                        "title": f"unpushed work in {w['label']} ({w['branch']}, {w['ahead']} ahead)", "path": w.get("path"),
                        "why": "commits that exist only on MSI are lost if its disk is"})
    for p in prs_of(d):
        key = f"{p['repo']}#{p['number']}"
        st = p.get("stage")
        base = {"pr": p, "url": p.get("url"), "since": p.get("created"), "id": f"pr:{key}"}
        if st in protocol.WAITING:
            out.append({**base, "kind": "review", "level": "notable",
                        "title": f"{key} awaits a {'fresh ' if st == 'stale-review' else ''}second review: {p.get('title', '')}",
                        "why": p.get("why") or "no gsv review at its current head"})
        elif st == "changes":
            out.append({**base, "kind": "fix", "level": "notable", "title": f"{key} has changes requested: {p.get('title', '')}",
                        "why": "a gsv review at this head asked for changes; the author addresses them"})
        elif st == "approved":
            out.append({**base, "kind": "merge", "level": "notable", "title": f"{key} is approved at its head: merge it",
                        "why": "approved by " + ", ".join(p.get("reviewers") or ["a reviewer"]) + " at the current head"})
    for c in d.get("steward_cards") or []:
        out.append({"kind": "decision", "level": "routine", "id": f"card:{c.get('file')}",
                    "title": f"Steward card {c.get('file')}: {c.get('title')}", "why": f"open {c.get('age_d')} days on xanadu"})
    os_ = fold_orders(d.get("channel", []))
    for s in protocol.open_suggestions(d.get("channel", []), os_, now):
        if s.get("order"):
            continue                                  # legacy SUGGEST lines are already orders
        out.append({"kind": "suggestion", "level": "routine", "id": s["id"], "since": s["at"],
                    "title": f"{s['from']} suggests for CHORUS: {s['text'][:110]}", "why": "an agent asked for a cockpit improvement"})
    chan = [m for m in d.get("channel", []) if not m.get("kind")]
    for i, m in enumerate(chan):
        to = str(m.get("to") or "").lower()
        if to in ("", "all", "mind", "any") or now - protocol._ts(m.get("at")) > 86400:
            continue
        if not any(str(n.get("from", "")).lower() == to for n in chan[i + 1:]):
            out.append({"kind": "reply", "level": "routine", "to": to, "id": f"reply:{m.get('at')}", "since": m.get("at"),
                        "title": f"{m.get('from')} asked {to}: {str(m.get('text'))[:90]}", "why": "unanswered for "
                        f"{(now - protocol._ts(m.get('at'))) / 3600:.1f} h"})
    return out


def prs_of(d: dict) -> list[dict]:
    """Open PRs with their gsv stage. Older feeds only had prs_waiting (no stage): treat them as waiting."""
    if d.get("prs_open") is not None:
        return d["prs_open"]
    return [{**p, "stage": p.get("stage", "needs-review")} for p in d.get("prs_waiting") or []]


# ---------------------------------------------------------------- scoring and fit
def yield_of(item: dict) -> int:
    y = BASE.get(item["kind"], 20)
    if item.get("level") == "alarm":
        y += 25
    text = item.get("title", "").lower()
    if item["kind"] == "review":
        y += 10                                       # a review unblocks a merge: the colony's main bottleneck
        if re.search(r"\bfix\b|fix\(", text):
            y += 10
        if (item.get("pr") or {}).get("stage") == "stale-review":
            y += 5                                    # someone already looked; a delta review is cheap
    return y


def fit(seat: str, item: dict) -> int:
    """0 means this seat must not do it."""
    s, kind = SEATS.get(seat), item["kind"]
    if seat == KEATH:
        return 1 if kind in KEATH_ONLY else 0
    if not s or kind in KEATH_ONLY:
        return 0
    author = (item.get("pr") or {}).get("author")
    if kind == "review" and is_author(seat, author):
        return 0
    if kind == "fix" and not is_author(seat, author):
        return 0
    if kind in ("rig", "save") and item.get("rig") not in s["rigs"]:
        return 0
    if kind == "reply" and item.get("to") != seat:
        return 0
    if kind == "suggestion" and seat != OWNER_SEAT:
        return 0
    if kind == "redo" and item.get("by") != seat:
        return 0
    text = item.get("title", "").lower()
    return 1 + sum(2 for k in s["skills"] if k in text)


def _held(order: dict) -> str | None:
    if order["status"] in ("taken", "working"):
        return order.get("by") or order.get("to")
    if order["status"] == "posted":
        return order.get("to")
    return None


def plan_for(seat: str, d: dict, now: float | None = None) -> dict:
    """{'item', 'yield', 'fit', 'workflow'} for this seat's next move, or {'item': None, 'reason'}."""
    seat = seat_of(seat)
    now = now or time.time()
    os_ = fold_orders(d.get("channel", []))
    open_prs = protocol.open_pr_index(prs_of(d)) if d.get("prs_open") is not None else None
    protocol.annotate_receipts(os_, open_prs)
    # one open order per seat: if you hold one, that IS your next move
    mine = [o for o in os_ if _held(o) == seat]
    if mine:
        o = mine[0]
        item = {"kind": "order", "id": o["id"], "order": o, "level": "notable", "url": o.get("url") or o.get("link"),
                "title": f"order {o['id']} ({o['status']}): {o['text']}", "since": o.get("at"),
                "why": f"{o.get('from')} posted it to {o.get('to')}; one open order per seat, so finish it first"}
        return {"item": item, "yield": BASE["order"], "fit": 1, "workflow": workflow(item, seat)}
    held_keys = set()
    for o in os_:
        if o["status"] in ("posted", "taken", "working"):
            held_keys |= {str(o.get("ref") or ""), str(o.get("url") or "")}
            k = protocol.pr_key(o.get("url"), o.get("ref"), o.get("text"))
            if k:
                held_keys.add(f"pr:{k}")
    items = [i for i in queue(d, now) if i["id"] not in held_keys and (i.get("url") or "-") not in held_keys]
    for o in os_:   # a "done" this seat reported that the owner record contradicts comes back to it
        if o.get("receipt") == "NOT confirmed":
            items.append({"kind": "redo", "by": o.get("by"), "level": "notable", "id": f"redo:{o['id']}", "order": o,
                          "url": o.get("url") or o.get("link"), "since": o.get("at"),
                          "title": f"order {o['id']} was reported done but is NOT confirmed: {o['text']}",
                          "why": "review orders count only with a gsv review at the PR's current head; merges only once the PR closed"})
    scored = sorted(((yield_of(i), fit(seat, i), i) for i in items), key=lambda t: (-t[0], -t[1], t[2]["title"]))
    best = next(((y, f, i) for y, f, i in scored if f > 0), None)
    if not best:
        return {"item": None, "reason": f"nothing in CHORUS's queue fits {seat} right now ({len(items)} items, none yours)"}
    y, f, i = best
    return {"item": i, "yield": y, "fit": f, "workflow": workflow(i, seat)}


# ---------------------------------------------------------------- the plan: who/what/where/when/why/how
def _when(item: dict, now: float | None = None) -> str:
    t = protocol._ts(item.get("since"))
    if not t:
        return "now"
    h = ((now or time.time()) - t) / 3600
    return f"now (open {h:.1f} h, since {item['since']})"


def workflow(item: dict, seat: str) -> dict:
    kind, url, p = item["kind"], item.get("url") or "", item.get("pr") or {}
    repo, num = p.get("repo", "<repo>"), p.get("number", "<N>")
    owner = f"GSV-Sublime-Optimization/{repo}"
    cli = "python chorus/chorus.py"
    steps = {
        "order": [f"{cli} take {item['id']}   (skip if you already took it)",
                  "do the work in your own lane, with your own permissions",
                  f"{cli} done {item['id']} --note \"what changed, with evidence\" --link <PR, review or receipt URL>",
                  "if you can't: decline it with why and what Keath must do"],
        "redo": ["open the PR and check its CURRENT head sha (gh pr view --json headRefOid)",
                 "review that head (or, for a merge, confirm it really merged) and post the gsv-review marker at that head",
                 f"{cli} done {item.get('order', {}).get('id', '<id>')} --note \"re-done at head <sha>\" --link <review URL>"],
        "review": [f"gh pr checkout {num} -R {owner}   (or read the diff at {url})",
                   "run its tests; where it adds tests, red-control them against the base branch",
                   f"write findings; verdict approve or request-changes, bound to head {p.get('head', '<sha>')}",
                   f"post a PR comment containing <!-- gsv-review: actor=<you> verdict=<v> head={p.get('head') or '<full sha>'} --> "
                   "(gsv.py review post does this)",
                   f"{cli} say \"reviewed {repo}#{num} at {str(p.get('head', ''))[:10]}: <verdict>\" --to all"],
        "fix": [f"read the requested changes on {url}", "make them on the same branch, with a test for each",
                "push: the head moves, so the old review becomes stale and the PR needs a fresh look",
                f"{cli} say \"{repo}#{num} addressed, needs a fresh review\" --to all"],
        "merge": [f"confirm CI is green and the approval is at head {p.get('head', '<sha>')}",
                  f"gsv merge {owner}#{num} --dry-run, then for real (checks CI, provenance, a different-actor review)"],
        "rig": [f"{cli} rig {item.get('rig')}   and   {cli} doctor   (measure first)",
                "fix it in your own lane (CHORUS /act allowlist for MSI containers and tasks)",
                "wait one heartbeat (about 5 min) and check it is green", f"{cli} say \"<what you did, the evidence>\" --to all"],
        "hands": [f"read the doctor's verdict: {item.get('why', '')[:160]}",
                  "go to the machine; do the physical step the verdict names", "check the next heartbeat is green"],
        "save": [f"git -C {item.get('path', '<checkout>')} log --oneline @{{u}}..",
                 "push the branch (or a claude/preserve-* branch) and open a draft PR if it has none",
                 f"{cli} say \"saved {item.get('title', '')[18:60]}\" --to all"],
        "decision": ["read the card on xanadu:~/steward/outbox/", "answer or close it; tell the owning seat in the channel"],
        "suggestion": [f"read the suggestion: {item.get('title', '')}",
                       "if it is worth doing: post an order with ref " + item["id"] + " (that closes the suggestion), then do it",
                       f"otherwise answer the suggester: {cli} say \"...\" --to <them>"],
        "reply": [f"{cli} say \"<answer>\" --to <asker>"],
    }.get(kind, ["see the item"])
    who = KEATH if kind in KEATH_ONLY else seat
    where = url or (f"{item['rig']} (rig)" if item.get("rig") else "the cockpit channel")
    return {"who": who, "what": item["title"], "where": where, "when": _when(item), "why": item.get("why", kind), "how": steps}


def render(seat: str, plan: dict) -> str:
    if not plan.get("item"):
        return plan.get("reason", "nothing to do")
    w, i = plan["workflow"], plan["item"]
    lines = [f"NEXT for {seat_of(seat)}: [{i['kind']}] {i['title']}",
             f"  yield {plan['yield']} · fit {plan['fit']}",
             f"  who:   {w['who']}", f"  what:  {w['what']}", f"  where: {w['where']}",
             f"  when:  {w['when']}", f"  why:   {w['why']}", "  how:"]
    lines += [f"    {n}. {s}" for n, s in enumerate(w["how"], 1)]
    return "\n".join(lines)
