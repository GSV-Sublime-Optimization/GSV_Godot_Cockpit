"""router.py: CHORUS's smart composer router. Text + the node it is about -> who, where, when, why.

    route(text, node=None, feed=None) -> {draft: {kind, text, station}, to, where, when, due, why,
                                          confidence, reasons, alternatives: [...], capability: [...]}

It never sends anything (no side effects): the feeder's POST /send does that, after Keath checks it.

KIND   ask | order | action-order | suggest | status | review-request | handoff, read from the words
       and the node (a failing check is work, a PR waiting for review is a review request, an idea
       about the cockpit is a suggestion, "what/why/how" is a question).
WHO    the TARGETS registry below, honest about reach: "live" targets get the message now (a seat
       on the channel, a local model over HTTP); "prepared" ones get a ready payload Keath (or a
       permitted lane) sends (GitHub comments, Studio missions, the ChatDev queue).
       Scored by ownership (who owns the rig/station), capability (the Steward atlas), availability
       (who was seen lately; the i3 Mind defers during playtests), cost (local models for
       summaries) and the second-actor rule (a Claude-authored PR is never reviewed by a Claude).
WHERE  channel (say/order), local (a model answers here), github (comment on the node's PR/issue),
       review-queue (dev#431), studio, chatdev.
WHEN   now, the next hourly cycle, after a dependency ("after #424 merges"), or at a time (due).
WHY    one plain sentence from the node: the doctor's verdict, the check's detail, the PR's wait.
Stdlib only.
"""
from __future__ import annotations

import glob
import re
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

KINDS = ("ask", "order", "action-order", "suggest", "status", "review-request", "handoff")
REVIEW_QUEUE = "https://github.com/GSV-Sublime-Optimization/dev/issues/431"
LITELLM = "http://127.0.0.1:4000/v1/chat/completions"

# reach: "live" = delivered now by the feeder; "prepared" = a ready payload/command, a human or a
# permitted lane sends it. vendor drives the second-actor rule.
TARGETS: dict[str, dict] = {
    "claude (msi seat)": {"label": "MSI Claude", "type": "seat", "rig": "msi", "vendor": "claude", "reach": "live",
                          "where": ["channel"], "owns": {"msi", "xanadu", "l9", "cockpit", "spine"},
                          "aliases": ["msi claude", "msi seat", "claude msi", "@msi"]},
    "claude (i3 seat)": {"label": "i3 Claude", "type": "seat", "rig": "i3", "vendor": "claude", "reach": "live",
                         "where": ["channel"], "owns": {"i3"}, "aliases": ["i3 claude", "i3 seat", "claude i3", "@i3"]},
    "i3-mind": {"label": "i3 Mind", "type": "seat", "rig": "i3", "vendor": "local", "reach": "live",
                "where": ["channel"], "owns": {"i3"}, "aliases": ["i3 mind", "engine room mind", "i3-mind"]},
    "local:msi": {"label": "MSI local model", "type": "local", "rig": "msi", "vendor": "local", "reach": "live",
                  "where": ["local"], "owns": set(), "url": LITELLM, "model": "ecosystem-qwen35",
                  "aliases": ["msi local", "local model", "local", "qwen"]},
    "local:i3": {"label": "i3 local model", "type": "local", "rig": "i3", "vendor": "local", "reach": "live",
                 "where": ["local"], "owns": set(), "url": LITELLM, "model": "ecosystem-desktop-qwen",
                 "aliases": ["i3 local", "i3 ollama"]},
    "local:l9": {"label": "L9 drone (local)", "type": "local", "rig": "l9", "vendor": "local", "reach": "live",
                 "where": ["local"], "owns": set(), "url": "http://127.0.0.1:11435/v1/chat/completions",
                 "model": "qwen3:4b-l9fast", "aliases": ["l9 local", "l9 drone", "l3 local", "l9 ollama", "drone"]},
    # Cloud seats: they hold a seat on the channel (so an order can name them) but do NOT read xanadu's
    # channel file. "mirror" = a channel line to them is also mirrored where they look (the node's PR, else
    # the review queue dev#431), prepared as a `gh` command unless CHORUS_ALLOW_GH_COMMENT=1.
    "gpt-6": {"label": "GPT-6", "type": "cloud", "rig": "cloud", "vendor": "openai", "reach": "prepared", "mirror": True,
              "where": ["github", "review-queue", "channel"], "owns": set(), "aliases": ["gpt-6", "gpt6", "gpt 6", "chatgpt"]},
    "codex": {"label": "Codex", "type": "cloud", "rig": "cloud", "vendor": "openai", "reach": "prepared", "mirror": True,
              "where": ["github", "review-queue", "channel"], "owns": set(), "aliases": ["codex", "i3 codex"]},
    "muse": {"label": "Muse", "type": "cloud", "rig": "cloud", "vendor": "muse", "reach": "prepared", "mirror": True,
             "where": ["github", "review-queue", "channel"], "owns": set(), "aliases": ["muse"]},
    "studio": {"label": "Studio mission", "type": "studio", "rig": "msi", "vendor": "studio", "reach": "prepared",
               "where": ["studio"], "owns": set(), "aliases": ["studio", "mission"]},
    "chatdev": {"label": "ChatDev queue", "type": "queue", "rig": "msi", "vendor": "chatdev", "reach": "prepared",
                "where": ["chatdev"], "owns": set(), "aliases": ["chatdev"]},
    "all": {"label": "everyone", "type": "all", "rig": "", "vendor": "all", "reach": "live",
            "where": ["channel"], "owns": set(), "aliases": ["everyone", "all agents", "all seats", "all minds", "@all"]},
}
SEAT_NAMES = {"claude (msi seat)": "MSI Claude", "claude (i3 seat)": "i3 Claude", "i3-mind": "i3 Mind"}
CLOUD_SEATS = ("gpt-6", "codex", "muse")              # seats that need a GitHub mirror to be reached
LEGACY_IDS = {"gpt6": "gpt-6"}                         # target ids older clients (MCP, pages) still send


def target_id(to) -> str | None:
    """A target id as sent by any client -> the registry id, or None when unknown."""
    to = LEGACY_IDS.get(str(to or ""), str(to or ""))
    return to if to in TARGETS else None


def second_actor_conflict(kind: str, node: dict | None, to: str) -> bool:
    """True when a review request would go to the PR author's own kind (a Claude reviewing a Claude)."""
    author = node_author(node or {})
    return kind == "review-request" and bool(author) and TARGETS.get(to, {}).get("vendor") == author

ASK = re.compile(r"^\s*(what|why|how|who|when|where|which|is|are|does|do|can|could|should|explain|tell me)\b|\?\s*$", re.I)
SUMMARY = re.compile(r"\b(summari[sz]e|summary|tl;?dr|digest|explain|in plain words|what does .* mean)\b", re.I)
ORDER = re.compile(r"^\s*(please\s+)?(fix|restart|run|bring|push|merge|update|add|remove|build|deploy|repair|enable|install|"
                   r"sort|commit|rebase|investigate|find out|check|look at|make|clean|move|finish|land)\b", re.I)
ACTION = re.compile(r"\b(restart|re-?run|run the|re-?measure|save to github|preserve|back ?up now)\b", re.I)
SUGGEST = re.compile(r"\b(suggest|idea|would be (nice|better)|should (show|be|look|say)|cockpit|this view|the view|"
                     r"improve|ui|button|chip|panel|layout)\b", re.I)
STATUS = re.compile(r"^\s*(status|update|fyi|heads up|done|progress)\b[:\s]", re.I)
REVIEW = re.compile(r"\breview\b", re.I)
HANDOFF = re.compile(r"\bhand ?(it )?off|handoff|take over|pick (this|it) up\b", re.I)
DIRECT = re.compile(r"^\s*(send|ask|tell|hand|give)\s+(this\s+)?(it\s+)?to\s+([^:,.]+?)\s*[:,.-]\s*", re.I)
AFTER = re.compile(r"\bafter\s+((?:[\w.-]+)?#\d+)(\s+(?:merges|lands|is merged))?", re.I)
AT = re.compile(r"\bat\s+(\d{1,2}):(\d{2})\b", re.I)
HOURLY = re.compile(r"\b(next (hourly )?cycle|next hour|hourly|in an hour)\b", re.I)


# ------------------------------------------------------------------ the node, read defensively
def _s(v, n: int = 200) -> str:
    return " ".join(str(v or "").split())[:n]


def node_rig(node: dict) -> str:
    rig = _s(node.get("rig"), 12).lower()
    if rig:
        return rig
    blob = " ".join(_s(node.get(k)) for k in ("id", "name", "title")).lower()
    for r in ("i3", "l9", "xanadu", "msi"):
        if re.search(rf"\b{r}\b", blob):
            return r
    return ""


def node_failing(node: dict) -> bool:
    if node.get("failing") or node.get("down"):
        return True
    return node.get("kind") in ("check", "need") and node.get("ok") is False


def node_author(node: dict) -> str:
    """Who wrote the PR on this node, as a vendor (claude/openai/muse) or ''."""
    a = _s(node.get("agent") or node.get("author") or node.get("branch"), 80).lower()
    if not a:
        return ""
    if "claude" in a:
        return "claude"
    if any(x in a for x in ("gpt", "codex", "chatgpt", "sol")):
        return "openai"
    if "muse" in a:
        return "muse"
    return ""


def node_label(node: dict) -> str:
    k = _s(node.get("kind"), 20)
    if k == "pr" and node.get("repo"):
        return f"{_s(node.get('repo'), 40)}#{_s(node.get('number'), 8)}"
    if k == "check" and node.get("check") and not node.get("name"):
        return f"{node_rig(node)} {_s(node.get('check'), 40)}".strip()
    return _s(node.get("name") or node.get("title") or node.get("id"), 80) or k


def why_of(node: dict | None) -> str:
    """One plain sentence from the node: the doctor's verdict first, then the check, the wait."""
    if not node:
        return ""
    label = node_label(node)
    verdict = _s(node.get("verdict"), 140)
    detail = _s(node.get("detail") or node.get("why"), 140)
    k = node.get("kind")
    if k == "pr":
        if node.get("waiting"):
            return f"{label} is waiting for a review" + (f" ({_s(node.get('age'), 20)})" if node.get("age") else "") + "."
        return f"{label} is {_s(node.get('state'), 12).lower() or 'open'}."
    if k == "svc" and node.get("down"):
        return f"the {label} service is down when it should be up."
    if k == "crystal":
        return f"{label} holds work that is not on GitHub ({detail or 'uncommitted or unpushed'})."
    if node_failing(node) or verdict:
        check = _s(node.get("check"), 40)
        what = f"{check} is failing on {node_rig(node)}" if check and node_rig(node) else f"{label} is failing" if node_failing(node) else label
        return f"{what}" + (f" (doctor: {verdict})" if verdict else f" ({detail})" if detail else "") + "."
    return f"{detail}." if detail else ""


# ------------------------------------------------------------------ feed-derived availability
def _ts(s) -> float:
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def availability(feed: dict | None, now: float | None = None) -> dict[str, dict]:
    """Per seat: when it was last seen and whether it said it is busy (the i3 Mind during playtests)."""
    now = now or time.time()
    out: dict[str, dict] = {}
    names = {v: k for k, v in SEAT_NAMES.items()}
    for s in (feed or {}).get("smiths") or []:
        seat = names.get(s.get("name"))
        if seat:
            out.setdefault(seat, {})["seen"] = _ts(s.get("at"))
    for m in (feed or {}).get("channel") or []:
        seat, t = m.get("from"), _ts(m.get("at"))
        if seat in SEAT_NAMES:
            cur = out.setdefault(seat, {})
            cur["seen"] = max(cur.get("seen", 0.0), t)
            if re.search(r"after the current playtest|busy", str(m.get("text", "")), re.I) and now - t < 30 * 60:
                cur["busy"] = "said it will answer after the current playtest"
    return out


# ------------------------------------------------------------------ the Steward atlas (capability match)
_atlas: dict = {"at": 0.0, "obj": None, "router": None}


def atlas_hint(text: str) -> list[dict]:
    """Top capability cards for the intent from the Steward atlas; [] when the plugin is absent."""
    if time.time() - _atlas["at"] > 600:
        _atlas["at"] = time.time()
        try:
            roots = sorted(glob.glob(str(Path.home() / ".claude/plugins/cache/gsv-sublime/gsv-steward/*/server")))
            if roots and roots[-1] not in sys.path:
                sys.path.insert(0, roots[-1])
            from steward import atlas, router  # type: ignore
            _atlas.update(obj=atlas.build(), router=router)
        except Exception:  # noqa: BLE001 - routing works without the atlas
            _atlas.update(obj=None, router=None)
    if not _atlas["obj"] or not text.strip():
        return []
    try:
        r = _atlas["router"].route(_atlas["obj"], text, limit=4)
    except Exception:  # noqa: BLE001
        return []
    return [{"id": c.get("id"), "summary": _s(c.get("summary"), 120)} for c in r.get("recommend", [])]


ATLAS_TO_TARGET = (("ollama|local inference|think_local|litellm", ("local:msi", "local:i3", "local:l9")),
                   ("codex", ("codex",)), ("chatdev", ("chatdev",)), ("studio|mission", ("studio",)),
                   ("remote-control|sendmessage|claude", ("claude (msi seat)", "claude (i3 seat)")),
                   ("review|pr-agent", CLOUD_SEATS))


# ------------------------------------------------------------------ inference
def explicit_target(text: str) -> tuple[str | None, str]:
    """"send to i3 claude: ..." / "@msi ..." -> (target id, text without the directive)."""
    low = text.lower()
    m = DIRECT.match(text)
    if m:
        wanted = m.group(4).lower().strip()
        for tid, t in TARGETS.items():
            if wanted in t["aliases"] or wanted == t["label"].lower() or wanted == tid:
                return tid, text[m.end():].strip()
    best = None
    for tid, t in TARGETS.items():
        for a in t["aliases"]:
            if len(a) < 5 and not a.startswith("@"):
                continue                       # short aliases ("local", "qwen") only count after "send to"
            if re.search(rf"(?<![\w@-]){re.escape(a)}(?![\w-])", low) and (best is None or len(a) > len(best[1])):
                best = (tid, a)
    return (best[0], text) if best else (None, text)


def infer_kind(text: str, node: dict | None) -> str:
    node = node or {}
    t = text.strip()
    if t:
        if STATUS.match(t):
            return "status"
        if HANDOFF.search(t):
            return "handoff"
        if REVIEW.search(t) and (node.get("kind") == "pr" or "#" in t):
            return "review-request"
        if node.get("action") and ACTION.search(t):
            return "action-order"
        if SUGGEST.search(t) and not ORDER.match(t):
            return "suggest"
        if ASK.search(t) or SUMMARY.search(t):
            return "ask"
        if ORDER.match(t):
            return "order"
    k = node.get("kind")
    if k == "pr":
        return "review-request" if node.get("waiting") or not node.get("state") else "ask"
    if node_failing(node) or k in ("crystal",) or (k == "svc" and node.get("down")):
        return "order"
    if k in ("know", "rival", "view"):
        return "suggest"
    if k == "order":
        return "status"
    return "ask" if (t or node) else "ask"


def parse_when(text: str, now: datetime | None = None) -> tuple[str, str]:
    """-> (when, due). due is "" (now), "hourly", "after:<ref>" or an ISO UTC time."""
    now = now or datetime.now().astimezone()
    m = AFTER.search(text)
    if m:
        return f"after {m.group(1)} merges", f"after:{m.group(1)}"
    m = AT.search(text)
    if m and int(m.group(1)) < 24 and int(m.group(2)) < 60:
        at = now.replace(hour=int(m.group(1)), minute=int(m.group(2)), second=0, microsecond=0)
        if at <= now:
            at += timedelta(days=1)
        return f"at {at.strftime('%H:%M')}", at.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if HOURLY.search(text):
        return "next hourly cycle", "hourly"
    return "now", ""


def station_for(kind: str, node: dict) -> str:
    if kind == "action-order":
        return "act"
    if kind == "suggest":
        return "cockpit"
    if kind == "review-request" or node.get("kind") == "pr":
        return "pegs"
    if node_failing(node) or node.get("kind") in ("svc", "check", "rig"):
        return "quench"
    return _s(node.get("station"), 12) or "anvil"


def default_text(kind: str, node: dict) -> str:
    """The draft when Keath has typed nothing: the node's own suggested words, else a template."""
    label, why = node_label(node), why_of(node)
    if node.get("draft") and kind in ("order", "action-order"):
        return _s(node["draft"], 600)
    if kind == "review-request":
        return f"Please review {label}" + (f" ({_s(node.get('title'), 90)})" if node.get("title") else "") + " and post evidence."
    if kind == "order":
        return f"Fix {label}: {why} Post the receipt when done." if why else f"Look at {label} and report what needs doing."
    if kind == "action-order":
        return _s(node.get("action_label") or f"{node.get('action')} {node.get('target')}", 200)
    if kind == "suggest":
        return f"{label}: "
    if kind == "status":
        return f"Status on {label}: "
    if kind == "handoff":
        return f"Handing off {label}. Where it stands: {why} Next step: "
    return f"About {label}: {why} What should I do?" if node else ""


# ------------------------------------------------------------------ scoring
def _candidates(kind: str, node: dict, text: str, feed: dict | None, hint: list[dict]) -> list[dict]:
    rig, author = node_rig(node), node_author(node)
    avail = availability(feed)
    hint_blob = " ".join(f"{h.get('id')} {h.get('summary')}" for h in hint).lower()
    summary = bool(SUMMARY.search(text))
    out = []
    for tid, t in TARGETS.items():
        score, why = 0.0, []
        if kind in ("order", "action-order", "handoff"):
            if t["type"] != "seat" or tid == "i3-mind" and kind == "action-order":
                continue
            if rig and rig in t["owns"]:
                score += 5; why.append(f"owns {rig}")
            elif not rig and tid == "claude (msi seat)":
                score += 3; why.append("default workshop seat")
            if tid == "i3-mind":
                score -= 1.5          # the Mind thinks; the Claude seats change things
        elif kind == "review-request":
            if author and t["vendor"] == author:
                continue               # second-actor rule: never the author's own kind
            if t["type"] == "cloud":
                score += 4; why.append("independent reviewer")
                if tid == "gpt-6":
                    score += 0.5
            elif t["type"] == "seat" and tid != "i3-mind":
                score += 3 if author and author != "claude" else (1 if not author else 0)
                why.append("second actor" if author and author != "claude" else "a seat")
            else:
                continue
        elif kind == "suggest":
            if tid == "claude (msi seat)":
                score += 6; why.append("owns the cockpit")
            elif t["type"] == "seat":
                score += 1
            else:
                continue
        elif kind == "status":
            if tid == "all":
                score += 5; why.append("everyone should see it")
            elif t["type"] == "seat":
                score += 2 + (2 if rig and rig in t["owns"] else 0)
            else:
                continue
        else:  # ask
            if t["type"] == "local":
                score += 4 if summary else 1.5
                if summary:
                    why.append("summaries are cheapest on a local model")
                score += {"local:msi": 0.6, "local:i3": 0.2, "local:l9": 0.0}[tid]
            elif t["type"] == "seat":
                score += 3 + (2 if rig and rig in t["owns"] else 0)
                if rig and rig in t["owns"]:
                    why.append(f"owns {rig}")
                if tid == "i3-mind":
                    score -= 0.5
            elif t["type"] == "all" and re.search(r"\b(everyone|all of you|anyone)\b", text, re.I):
                score += 6
            else:
                continue
        # availability
        a = avail.get(tid, {})
        if a.get("busy"):
            score -= 3; why.append(a["busy"])
        if t["type"] == "seat" and feed and (time.time() - a.get("seen", 0)) > 3 * 3600:
            score -= 1; why.append("not seen in 3 h")
        # capability from the atlas
        for pat, tids in ATLAS_TO_TARGET:
            if tid in tids and hint_blob and re.search(pat, hint_blob):
                score += 0.75; why.append("atlas: capable lane"); break
        where = t["where"][0]
        if t["type"] == "cloud":
            where = "github" if node.get("url") else "review-queue"
        out.append({"to": tid, "label": t["label"], "where": where, "reach": t["reach"], "score": round(score, 2),
                    "because": ", ".join(why) or "can take it"})
    return sorted(out, key=lambda c: (-c["score"], c["to"]))


def route(text: str, node: dict | None = None, feed: dict | None = None, kind: str | None = None,
          to: str | None = None, use_atlas: bool = True) -> dict:
    """Suggest a send. Pure: reads text, node and feed, writes nothing."""
    node = node if isinstance(node, dict) else {}
    text = _s(text, 600)
    forced_to, body = explicit_target(text)
    to = target_id(to) or forced_to
    if kind not in KINDS:
        kind = infer_kind(body, node)
        if to == "all" and kind == "ask" and body and not ASK.search(body):
            kind = "status"                  # a line to everyone that asks nothing is news
    if kind == "action-order" and not node.get("action"):
        kind = "order"
    hint = atlas_hint(body or why_of(node)) if use_atlas else []
    cands = _candidates(kind, node, body, feed, hint)
    if to:
        pick = next((c for c in cands if c["to"] == to), None)
        if not pick:                       # Keath named someone the rules would not pick: honour it, say so
            t = TARGETS[to]
            where = ("github" if node.get("url") else "review-queue") if t["type"] == "cloud" else t["where"][0]
            pick = {"to": to, "label": t["label"], "where": where, "reach": t["reach"], "score": 0, "because": "you named it"}
            if second_actor_conflict(kind, node, to):
                pick["because"] = "you named it, but it is the author's own kind (second-actor rule)"
        else:
            pick = {**pick, "because": "you named it" + (f"; {pick['because']}" if pick["because"] else "")}
        cands = [pick] + [c for c in cands if c["to"] != to]
    if not cands:
        cands = [{"to": "claude (msi seat)", "label": "MSI Claude", "where": "channel", "reach": "live", "score": 0,
                  "because": "fallback"}]
    best = cands[0]
    when, due = parse_when(body)
    margin = best["score"] - (cands[1]["score"] if len(cands) > 1 else 0)
    confidence = 0.95 if to else round(max(0.3, min(0.9, 0.45 + margin / 10)), 2)
    draft_text = body if body else default_text(kind, node)
    if kind == "suggest" and not body:
        draft_text = default_text(kind, node)
    return {"draft": {"kind": kind, "text": draft_text, "station": station_for(kind, node)},
            "to": best["to"], "label": best["label"], "where": best["where"], "reach": best["reach"],
            "when": when, "due": due, "why": why_of(node) or ("you asked" if body else ""),
            "confidence": confidence, "reasons": best["because"],
            "alternatives": cands[1:5], "capability": hint[:3],
            "preview": preview(best["label"], kind, when, why_of(node), best["reach"], best["where"])}


KIND_WORDS = {"ask": "a question", "order": "an order", "action-order": "an action order", "suggest": "a suggestion",
              "status": "a status update", "review-request": "a review request", "handoff": "a hand-off"}
WHERE_WORDS = {"channel": "", "local": " (answers here)", "github": " (as a GitHub comment)",
               "review-queue": " (on the review queue, dev#431)", "studio": " (as a Studio mission)", "chatdev": " (to the ChatDev queue)"}


def preview(label: str, kind: str, when: str, why: str, reach: str = "live", where: str = "channel") -> str:
    s = f"Send to {label} as {KIND_WORDS.get(kind, kind)}{WHERE_WORDS.get(where, '')}, {when}"
    if why and why != "you asked":
        s += f", because {why.rstrip('.')}"
    if reach == "prepared":
        s += " (prepared: you send it)"
    return s + "."
