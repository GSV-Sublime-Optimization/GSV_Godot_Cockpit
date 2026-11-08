"""protocol.py: the colony's shared agent protocol, as CHORUS reads it (pure functions, no I/O).

The same protocol HOLOMIND (#15) speaks, re-implemented here so CHORUS never imports another entry:

- The channel is xanadu:~/steward/cockpit/channel.jsonl, one JSON object per line.
- Orders: {kind:'order', id, to, station, text, ref?, url?} then {kind:'order-status', id,
  status: taken|working|done|declined, note, link}. A repeated order line never resets an order
  (shop.orders folds them).
- Suggestions for the cockpit: {kind:'suggestion', from, text}.
- Read receipts, two shapes: a watermark {kind:'read', from, at} ("read everything up to at",
  never counting the reader's own lines) and a list {kind:'read', from, reads:[at, ...]}.
- A PR's review state comes from <!-- gsv-review: actor=.. verdict=.. head=<sha> --> comments.
  Every agent posts as the PR author's GitHub account, so reviewDecision never moves: a review
  counts only when its head is the PR's current head.
- A seat's "done" is a REPORT until reconciled with the owning record: a review order is
  verified when a gsv review exists at the PR's current head; a merge order once the PR closed.
"""
from __future__ import annotations

import re
import time
from datetime import datetime

GSV_REVIEW = re.compile(r"gsv-review:\s*actor=(\S+)\s+verdict=(\S+)\s+head=([0-9a-fA-F]{7,40})\b")
PR_URL = re.compile(r"github\.com/[\w.-]+/([\w.-]+)/pull/(\d+)")
PR_REF = re.compile(r"(?<![\w.-])([A-Za-z][\w.-]*)#(\d+)\b")
WAITING = ("needs-review", "stale-review")
SUGGESTION_DAYS = 7


def _ts(s) -> float:
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


# ---------------------------------------------------------------- reviews: the gsv-review head check
def gsv_reviews(pr: dict) -> list[dict]:
    """Every gsv-review marker on a PR, from issue comments and from review bodies."""
    bodies = [c.get("body") or "" for c in pr.get("comments") or []]
    bodies += [r.get("body") or "" for r in pr.get("reviews") or []]
    return [{"actor": m[0], "verdict": m[1].lower(), "head": m[2].lower()}
            for b in bodies for m in GSV_REVIEW.findall(b)]


def at_head(marker_head: str, head: str) -> bool:
    """A marker's head matches the PR's head: the full sha, or an unambiguous prefix (7+ chars)."""
    m, h = (marker_head or "").lower(), (head or "").lower()
    return bool(m and h) and (m == h or (len(m) >= 7 and h.startswith(m)))


def pr_stage(pr: dict) -> dict:
    """Where an open PR is, judged ONLY by gsv-review markers bound to its current head.
    reviewDecision is ignored on purpose: it never changes when agents share one account."""
    head = pr.get("headRefOid") or ""
    reviews = gsv_reviews(pr)
    on_head = [r for r in reviews if at_head(r["head"], head)]
    verdicts = {r["verdict"] for r in on_head}
    if pr.get("isDraft"):
        stage, why = "draft", "author still working"
    elif not head:
        stage, why = "unknown", "head not measured"
    elif "request-changes" in verdicts:
        stage, why = "changes", "a reviewer asked for changes at this head"
    elif "approve" in verdicts:
        stage, why = "approved", "approved at this head: Keath merges"
    elif on_head:
        stage, why = "reviewed", "reviewed at this head (" + ", ".join(sorted(verdicts)) + ")"
    elif reviews:
        stage, why = "stale-review", "reviewed only at an older head; the new commits need a look"
    else:
        stage, why = "needs-review", "no gsv review at any head yet"
    return {"stage": stage, "why": why, "head": head,
            "reviewers": sorted({r["actor"] for r in on_head}), "older_reviews": len(reviews) - len(on_head)}


def pr_key(*texts) -> str | None:
    """'repo#N' from the first text that names a PR (a GitHub PR URL or repo#N)."""
    for t in texts:
        t = str(t or "")
        m = PR_URL.search(t) or PR_REF.search(t)
        if m:
            return f"{m.group(1)}#{m.group(2)}"
    return None


# ---------------------------------------------------------------- orders: reported vs verified
def order_kind(o: dict) -> str:
    ref, text, station = str(o.get("ref") or ""), str(o.get("text") or "").strip().lower(), str(o.get("station") or "")
    if ref.startswith("merge:") or station == "merge" or text.startswith("merge"):
        return "merge"
    if ref.startswith("review:") or "review" in station or station == "pegs" or text.startswith("review"):
        return "review"
    return "other"


def receipt(o: dict, open_prs: dict | None) -> str | None:
    """'verified', 'reported' or 'NOT confirmed' for a done order; None for any other status.
    open_prs maps 'repo#N' -> pr_stage-ish dict for every open PR; None when GitHub wasn't measured."""
    if o.get("status") != "done":
        return None
    kind = order_kind(o)
    key = pr_key(o.get("url"), o.get("ref"), o.get("text"), o.get("link"))
    if open_prs is None or kind == "other" or not key:
        return "reported"
    p = open_prs.get(key)
    if kind == "review":
        if p is None:
            return "reported"                      # closed (or never seen): its head can't be checked now
        return "verified" if p.get("reviewers") else "NOT confirmed"
    return "NOT confirmed" if p is not None else "verified"   # merge: verified once the PR is no longer open


def annotate_receipts(orders: list[dict], open_prs: dict | None) -> list[dict]:
    for o in orders:
        o["receipt"] = receipt(o, open_prs)
    return orders


def open_pr_index(prs: list[dict] | None) -> dict | None:
    if prs is None:
        return None
    return {f"{p['repo']}#{p['number']}": p for p in prs}


# ---------------------------------------------------------------- read receipts
def read_by(channel: list[dict]) -> dict[str, set]:
    """{message at: {seats that read it}} from both receipt shapes. A watermark never marks the
    reader's own lines as read by itself."""
    said = [m for m in channel if m.get("kind") != "read"]
    out: dict[str, set] = {}
    for r in channel:
        if r.get("kind") != "read":
            continue
        who = str(r.get("from") or "")
        if isinstance(r.get("reads"), list):
            ats = [str(a) for a in r["reads"]]
        else:
            mark = _ts(r.get("at"))
            ats = [str(m.get("at")) for m in said if m.get("from") != who and _ts(m.get("at")) <= mark]
        for at in ats:
            out.setdefault(at, set()).add(who)
    return out


# ---------------------------------------------------------------- suggestions
def suggestion_id(m: dict) -> str:
    return "suggestion:" + str(m.get("at"))           # the id HOLOMIND uses as an order's ref


def open_suggestions(channel: list[dict], orders: list[dict], now: float | None = None) -> list[dict]:
    """Suggestions nobody has turned into an order yet (last 7 days), newest first. Legacy CHORUS
    suggestions (orders whose text starts 'SUGGEST') count while their order is still open."""
    now = now or time.time()
    refs = {str(o.get("ref") or "") for o in orders}
    out = []
    for m in channel:
        if m.get("kind") != "suggestion" or not str(m.get("text") or "").strip():
            continue
        t = _ts(m.get("at"))
        if not t or now - t > SUGGESTION_DAYS * 86400 or suggestion_id(m) in refs:
            continue
        out.append({"id": suggestion_id(m), "at": m.get("at"), "from": m.get("from"),
                    "node": m.get("node", ""), "text": str(m.get("text"))[:500]})
    for o in orders:
        if str(o.get("text", "")).startswith("SUGGEST") and o.get("status") not in ("done", "declined"):
            out.append({"id": o["id"], "at": o.get("at"), "from": o.get("from"), "node": "",
                        "text": str(o["text"]).split(":", 1)[-1].strip()[:500], "order": o["id"]})
    return sorted(out, key=lambda s: str(s.get("at") or ""), reverse=True)
