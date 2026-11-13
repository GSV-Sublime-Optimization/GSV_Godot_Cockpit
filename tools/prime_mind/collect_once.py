#!/usr/bin/env python3
"""One-shot, read-only Xanadu Mind archive fetch for ΞNuSyQ-Prime.

Only an existing *authenticated operator* SSH alias is used. No daemon,
remote write, process restart, token handling, synthetic observations,
or autonomous polling. A successful SSH snapshot is not fleet admission.

Besides Mind thoughts the tape carries the colony's *work*: order,
order-status and decision lines from the shared cockpit channel, and rig
status changes derived from consecutive heartbeats. Work lives in its own
`work` array, never in `events`: a work line is a report on the channel,
not a model thought and not an observer line.

--export-json prints the merged tape as JSON lines for any agent to grep.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Any

SCHEMA = "colony.mindview-feed/v0"
SSH_HOST = "xanadu"
MAX_RESPONSE_BYTES = 180_000   # the projected feed file (FeedContract admits 192 KiB)
MAX_REMOTE_BYTES = 480_000     # the one SSH response, before projection
MAX_CHANNEL_TAIL_BYTES = 262_144
MAX_CHANNEL_LINES = 400
MAX_HEARTBEAT_HISTORY = 200
MAX_WORK = 60                  # FeedContract.MAX_WORK
WORK_KINDS = ("order", "order-status", "decision", "rig-change")
CHANNEL_KINDS = ("order", "order-status", "decision")
ORDER_STATUSES = ("taken", "working", "done", "declined")
HEARTBEAT_RIGS = ("msi", "i3", "l9")
SILENT_AFTER_S = 900
REMOTE_SCRIPT = r'''
import datetime, glob, json, os, pathlib
root = pathlib.Path.home() / "steward"
data = {"events": [], "heartbeats": {}, "channel": []}
files = sorted((root / "events").glob("*.jsonl"))[-2:]
lines = []
for path in files:
    if not path.is_file() or path.stat().st_size > 400000:
        continue
    with path.open(encoding="utf-8") as stream:
        lines.extend(stream.readlines()[-80:])
for line in lines[-80:]:
    try:
        obj = json.loads(line)
        if isinstance(obj, dict):
            data["events"].append(obj)
    except (ValueError, TypeError):
        pass
for name in ("msi", "i3", "l9"):
    path = root / "heartbeats" / (name + ".json")
    if not path.is_file() or path.stat().st_size > 8192:
        continue
    try:
        data["heartbeats"][name] = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        pass
# Shared cockpit channel: only its tail, only work kinds (orders, receipts, decisions).
channel = root / "cockpit" / "channel.jsonl"
if channel.is_file():
    with channel.open("rb") as stream:
        size = stream.seek(0, 2)
        stream.seek(max(0, size - 262144))
        tail = stream.read().decode("utf-8", "replace").splitlines()
    if size > 262144:
        tail = tail[1:]
    for line in tail[-400:]:
        try:
            obj = json.loads(line)
        except (ValueError, TypeError):
            continue
        if isinstance(obj, dict) and obj.get("kind") in ("order", "order-status", "decision"):
            data["channel"].append(obj)
    data["channel"] = data["channel"][-120:]
print(json.dumps(data, separators=(",", ":")))
'''


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def elapsed(stamp: Any, now: dt.datetime) -> int | None:
    if not isinstance(stamp, str):
        return None
    try:
        observed = dt.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        if observed.tzinfo is None:
            return None
        return int((now - observed).total_seconds())
    except (TypeError, ValueError, OverflowError):
        return None


# ---------------------------------------------------------------- work kinds

_CONTROL = re.compile(r"[\x00-\x1f\x7f]")
_VERDICT = re.compile(r"^[a-z][a-z0-9_-]{0,31}$")


def norm_stamp(value: Any) -> str | None:
    """A timezone-aware ISO instant as 'YYYY-MM-DDTHH:MM:SSZ' (UTC), else None."""
    if not isinstance(value, str) or len(value) > 40:
        return None
    try:
        stamp = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if stamp.tzinfo is None:
        return None
    return stamp.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _ident(value: Any, limit: int = 64) -> str | None:
    if not isinstance(value, str):
        return None
    value = value.strip()
    if not value or len(value) > limit or _CONTROL.search(value):
        return None
    return value


def _text(value: Any, limit: int) -> str:
    if not isinstance(value, str):
        return ""
    return _CONTROL.sub(" ", value).strip()[:limit]


def safe_link(value: Any) -> str:
    """Only a plain https URL survives; anything else becomes 'no link'."""
    if not isinstance(value, str):
        return ""
    value = value.strip()
    if (not value.startswith("https://") or not 10 <= len(value) <= 300
            or any(ch.isspace() for ch in value) or _CONTROL.search(value)):
        return ""
    return value


def _work(kind: str, at: str, *, id: str, who: str, status: str, to: str = "",
          text: str = "", note: str = "", link: str = "", rig: str | None = None,
          prev_status: str = "") -> dict[str, Any]:
    return {"kind": kind, "at": at, "id": id, "from": who, "to": to, "status": status,
            "text": text, "note": note, "link": link, "rig": rig, "prev_status": prev_status}


def project_channel(lines: Any) -> list[dict[str, Any]]:
    """Order, order-status and decision lines from the shared channel.

    Plain messages, read receipts and suggestions are chat, not work, and are
    left out. A line missing its time, author, id or a known status is
    dropped, not repaired. An order-status borrows the addressee and text of
    its order's poster (as 'to') and text when that order is still in the
    window; nothing else is joined.
    """
    if not isinstance(lines, list):
        return []
    orders: dict[str, dict[str, Any]] = {}
    out: list[dict[str, Any]] = []
    for m in lines[-MAX_CHANNEL_LINES:]:
        if not isinstance(m, dict):
            continue
        kind = m.get("kind")
        at = norm_stamp(m.get("at"))
        who = _ident(m.get("from"))
        if kind not in CHANNEL_KINDS or at is None or who is None:
            continue
        if kind == "order":
            oid = _ident(m.get("id"))
            text = _text(m.get("text"), 280)
            if oid is None or not text:
                continue
            item = _work("order", at, id=oid, who=who, to=_ident(m.get("to")) or "",
                         status="posted", text=text, link=safe_link(m.get("url")))
            orders.setdefault(oid, item)
        elif kind == "order-status":
            oid = _ident(m.get("id"))
            status = m.get("status")
            if oid is None or status not in ORDER_STATUSES:
                continue
            order = orders.get(oid, {})
            # A receipt answers whoever posted the order.
            item = _work("order-status", at, id=oid, who=who, to=order.get("from", ""),
                         status=status, text=order.get("text", "")[:160],
                         note=_text(m.get("note"), 280), link=safe_link(m.get("link")))
        else:
            card = _ident(m.get("card"), 100)
            verdict = _ident(m.get("verdict"), 32)
            verdict = verdict.lower() if verdict else None
            if card is None or verdict is None or not _VERDICT.match(verdict):
                continue
            item = _work("decision", at, id=card, who=who, status=verdict,
                         note=_text(m.get("note"), 280))
        out.append(item)
    return out


def heartbeat_state(hb: Any, rig: str) -> dict[str, Any] | None:
    """One heartbeat reduced to what a change needs: when, green/red, failing checks."""
    if not isinstance(hb, dict) or hb.get("schema") != "colony.heartbeat/v1" or hb.get("rig") != rig:
        return None
    at = norm_stamp(hb.get("at"))
    if at is None or not isinstance(hb.get("green"), bool):
        return None
    failing: list[str] = []
    checks = hb.get("checks", [])
    if isinstance(checks, list):
        for c in checks[:20]:
            if isinstance(c, dict) and c.get("ok") is False and isinstance(c.get("name"), str):
                failing.append(c["name"][:80])
    return {"at": at, "status": "green" if hb["green"] else "red", "failing": sorted(set(failing))}


def _seen_state(value: Any) -> dict[str, Any] | None:
    """A state carried in a previous feed's heartbeat_last map."""
    if not isinstance(value, dict):
        return None
    at = norm_stamp(value.get("at"))
    failing = value.get("failing")
    if (at is None or value.get("status") not in ("green", "red") or not isinstance(failing, list)
            or len(failing) > 20 or not all(isinstance(f, str) and len(f) <= 80 for f in failing)):
        return None
    return {"at": at, "status": value["status"], "failing": sorted(set(failing))}


def rig_changes(history: dict[str, list[dict[str, Any]]]) -> list[dict[str, Any]]:
    """Status changes between consecutive heartbeats of the same rig.

    Only a change between two observed heartbeats is reported. A long gap is
    stated in the note; it is never turned into an invented 'silent' event.
    """
    out: list[dict[str, Any]] = []
    for rig in HEARTBEAT_RIGS:
        states = {s["at"]: s for s in history.get(rig, []) if s}
        ordered = [states[k] for k in sorted(states)]
        for prev, cur in zip(ordered, ordered[1:]):
            if prev["status"] == cur["status"] and prev["failing"] == cur["failing"]:
                continue
            notes = []
            began = [f for f in cur["failing"] if f not in prev["failing"]]
            ended = [f for f in prev["failing"] if f not in cur["failing"]]
            if began:
                notes.append("now failing: " + ", ".join(began))
            if ended:
                notes.append("recovered: " + ", ".join(ended))
            gap = int((dt.datetime.fromisoformat(cur["at"].replace("Z", "+00:00"))
                       - dt.datetime.fromisoformat(prev["at"].replace("Z", "+00:00"))).total_seconds())
            if gap > SILENT_AFTER_S:
                notes.append(f"previous heartbeat {gap // 60} min earlier")
            out.append(_work("rig-change", cur["at"], id=rig, who="heartbeat",
                             status=cur["status"], prev_status=prev["status"], rig=rig,
                             text=f"{rig.upper()} {prev['status']} -> {cur['status']}",
                             note="; ".join(notes)[:280]))
    return out


def work_problem(w: Any) -> str | None:
    """Python twin of FeedContract's work admission: None when admissible."""
    keys = {"kind", "at", "id", "from", "to", "status", "text", "note", "link", "rig", "prev_status"}
    if not isinstance(w, dict) or set(w) != keys:
        return "work_fields"
    if w["kind"] not in WORK_KINDS:
        return "work_kind"
    for field, limit in (("at", 40), ("id", 100), ("from", 64), ("to", 64), ("status", 32),
                         ("text", 280), ("note", 280), ("link", 300), ("prev_status", 16)):
        if not isinstance(w[field], str) or len(w[field]) > limit:
            return "work_" + field
    if norm_stamp(w["at"]) != w["at"] or not w["from"] or not w["id"]:
        return "work_identity"
    if w["link"] and safe_link(w["link"]) != w["link"]:
        return "work_link"
    if w["kind"] == "order" and w["status"] != "posted":
        return "work_status"
    if w["kind"] == "order-status" and w["status"] not in ORDER_STATUSES:
        return "work_status"
    if w["kind"] == "decision" and not _VERDICT.match(w["status"]):
        return "work_status"
    if w["kind"] == "rig-change":
        if (w["rig"] not in HEARTBEAT_RIGS or w["status"] not in ("green", "red")
                or w["prev_status"] not in ("green", "red")):
            return "work_rig"
    elif w["rig"] is not None or w["prev_status"]:
        return "work_rig"
    return None


def receipt_state(w: dict[str, Any]) -> str:
    """'linked' only when a done receipt carries a link, otherwise 'reported'.
    The link is shown, never fetched: 'linked' does not mean verified."""
    if w.get("kind") != "order-status" or w.get("status") != "done":
        return ""
    return "linked" if w.get("link") else "reported"


def _previous_work(previous: Any) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]]]:
    """Rig changes and last heartbeat states carried in the previous feed file.

    Live xanadu keeps one heartbeat file per rig, so the earlier of two
    consecutive heartbeats comes from the last collection. Anything malformed
    is ignored, not repaired.
    """
    if not isinstance(previous, dict) or previous.get("schema") != SCHEMA:
        return [], {}
    carried: list[dict[str, Any]] = []
    work = previous.get("work", [])
    if isinstance(work, list):
        for w in work[-MAX_WORK:]:
            if isinstance(w, dict) and w.get("kind") == "rig-change" and not work_problem(w):
                carried.append(dict(w))
    seen: dict[str, dict[str, Any]] = {}
    last = previous.get("heartbeat_last", {})
    if isinstance(last, dict):
        for rig in HEARTBEAT_RIGS:
            state = _seen_state(last.get(rig))
            if state:
                seen[rig] = state
    return carried, seen


# ---------------------------------------------------------------- projection

XANADU_SSH_NOTE = "SSH read of Xanadu archive succeeded; host health not independently qualified"
XANADU_LOCAL_NOTE = "Local archive copy; Xanadu host health not observed"


def project(remote: dict[str, Any], *, now: dt.datetime,
            xanadu_detail: str = XANADU_SSH_NOTE,
            previous: dict[str, Any] | None = None) -> dict[str, Any]:
    if not isinstance(remote, dict):
        raise ValueError("invalid_remote_source")
    events = remote.get("events", [])
    heartbeats = remote.get("heartbeats", {})
    if not isinstance(events, list) or not isinstance(heartbeats, dict):
        raise ValueError("invalid_remote_schema")
    bodies: dict[str, dict[str, Any]] = {}
    for rig in ("msi", "i3", "l9", "xanadu"):
        body = {
            "label": rig.upper(), "role": "observation node",
            "status": "unknown", "failing": [],
            "age_s": None, "detail": "No current authenticated heartbeat",
        }
        hb = heartbeats.get(rig)
        if rig == "xanadu":
            body["detail"] = xanadu_detail
        elif isinstance(hb, dict) and hb.get("schema") == "colony.heartbeat/v1" and hb.get("rig") == rig:
            age = elapsed(hb.get("at"), now)
            checks = hb.get("checks", [])
            failed = []
            if isinstance(checks, list):
                for c in checks[:20]:
                    if isinstance(c, dict) and c.get("ok") is False and isinstance(c.get("name"), str):
                        failed.append(c["name"][:80])
            body["age_s"] = max(0, age) if age is not None else None
            if age is None or age < -120 or age > 900:
                body["status"] = "silent"
            else:
                body["status"] = "green" if hb.get("green") is True else "red"
            body["failing"] = failed
            body["detail"] = "Heartbeat from Xanadu archive, not a runtime attachment"
        bodies[rig] = body
    cleaned = []
    for e in events[-80:]:
        if not isinstance(e, dict):
            continue
        if not all(isinstance(e.get(field), str) for field in ("at", "mind", "line", "level")):
            continue
        focus = e.get("focus")
        if focus is not None and focus not in bodies:
            focus = None
        reasons = e.get("reasons", [])
        if not isinstance(reasons, list):
            reasons = []
        model = e.get("model")
        if model is not None and not isinstance(model, str):
            model = None
        level = e["level"] if e["level"] in ("routine", "notable", "alarm", "calm") else "routine"
        cleaned.append({
            "at": e["at"][:40], "mind": e["mind"][:64], "model": model,
            "level": level, "line": e["line"][:600], "focus": focus,
            "reasons": [r[:320] for r in reasons[:8] if isinstance(r, str)],
            "simulated": e.get("simulated") is True,
        })
    # Work: channel lines plus rig changes between consecutive heartbeats.
    carried, seen = _previous_work(previous)
    history: dict[str, list[dict[str, Any]]] = {}
    raw_history = remote.get("heartbeat_history", {})
    for rig in HEARTBEAT_RIGS:
        states = [seen[rig]] if rig in seen else []
        if isinstance(raw_history, dict) and isinstance(raw_history.get(rig), list):
            states += [heartbeat_state(hb, rig) for hb in raw_history[rig][-MAX_HEARTBEAT_HISTORY:]]
        states.append(heartbeat_state(heartbeats.get(rig), rig))
        history[rig] = [s for s in states if s]
    work = carried + project_channel(remote.get("channel", []))
    known = {(w["kind"], w["id"], w["at"]) for w in work}
    for change in rig_changes(history):
        if (change["kind"], change["id"], change["at"]) not in known:
            work.append(change)
    work.sort(key=lambda w: w["at"])          # stable: channel order kept within one second
    last: dict[str, dict[str, Any]] = {}
    for rig, states in history.items():
        if states:
            newest = max(states, key=lambda s: s["at"])
            last[rig] = {"at": newest["at"], "status": newest["status"], "failing": newest["failing"]}
    feed = {
        "schema": SCHEMA,
        "at": now.isoformat(timespec="seconds").replace("+00:00", "Z"),
        "source_ok": True,
        "bodies": bodies, "events": cleaned,
        "work": work[-MAX_WORK:],
        "heartbeat_last": last,
        "attention": cleaned[-1].get("focus") if cleaned else None,
        "screen": "",
    }
    return fit_feed(feed)


def _size(feed: dict[str, Any]) -> int:
    return len(json.dumps(feed, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))


def fit_feed(feed: dict[str, Any]) -> dict[str, Any]:
    """Drop the oldest work lines until the feed fits the byte budget.
    Thought events are never trimmed here; an oversized thought set still fails."""
    while feed["work"] and _size(feed) > MAX_RESPONSE_BYTES:
        feed["work"] = feed["work"][1:]
    return feed


def tape_lines(feed: dict[str, Any], *, since: str | None = None,
               until: str | None = None) -> list[dict[str, Any]]:
    """The Loom's tape as flat records, oldest first, for agents.

    lane is model | observer | simulated | work, the same split the scene
    draws. 't' is the UTC instant normalised for sorting and grepping.
    """
    rows: list[dict[str, Any]] = []
    for e in feed.get("events", []):
        lane = "observer" if e.get("model") is None or e.get("mind") == "observer" else "model"
        if e.get("simulated") is True:
            lane = "simulated"
        rows.append({"t": norm_stamp(e.get("at")) or str(e.get("at")), "lane": lane,
                     "kind": "thought", "mind": e.get("mind"), "model": e.get("model"),
                     "level": e.get("level"), "focus": e.get("focus"), "line": e.get("line"),
                     "reasons": e.get("reasons", [])})
    for w in feed.get("work", []):
        row: dict[str, Any] = {"t": w["at"], "lane": "work"}
        row.update({k: w[k] for k in ("kind", "id", "from", "to", "status", "text", "note",
                                      "link", "rig", "prev_status")})
        row["receipt"] = receipt_state(w)
        rows.append(row)
    rows.sort(key=lambda r: r["t"])
    return [r for r in rows
            if (since is None or r["t"] >= since) and (until is None or r["t"] <= until)]


def read_feed(path: Path) -> dict[str, Any]:
    """An already-collected feed file, admitted only if every work line passes."""
    if not path.is_file() or path.stat().st_size > MAX_RESPONSE_BYTES + 16_384:
        raise ValueError("feed_unreadable_or_oversized")
    feed = json.loads(path.read_text(encoding="utf-8"))
    if (not isinstance(feed, dict) or feed.get("schema") != SCHEMA
            or not isinstance(feed.get("events"), list) or not isinstance(feed.get("work", []), list)
            or len(feed.get("work", [])) > MAX_WORK):
        raise ValueError("feed_schema")
    for w in feed.get("work", []):
        problem = work_problem(w)
        if problem:
            raise ValueError(problem)
    return feed


# ---------------------------------------------------------------- local copies

def _tail_jsonl(path: Path, max_bytes: int, max_lines: int) -> list[dict[str, Any]]:
    """The last JSON-object lines of a file, reading at most max_bytes from its end."""
    with path.open("rb") as stream:
        size = stream.seek(0, 2)
        stream.seek(max(0, size - max_bytes))
        lines = stream.read().decode("utf-8", "replace").splitlines()
    if size > max_bytes:
        lines = lines[1:]        # the first line is probably cut
    out = []
    for line in lines[-max_lines:]:
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if isinstance(obj, dict):
            out.append(obj)
    return out


def read_local_archive(root: Path) -> dict[str, Any]:
    """Read a local copy of the archive, e.g. the shared #14 fixture
    tests/fixtures/mindview-20261108/ (events.jsonl + heartbeat_<rig>.json)
    or a mirror of xanadu:~/steward (events/*.jsonl + heartbeats/<rig>.json).
    Work sources, when present: channel.jsonl or cockpit/channel.jsonl, and a
    heartbeat history per rig (heartbeats/<rig>.jsonl or
    heartbeat_history_<rig>.jsonl). Same limits as the remote script;
    nothing is written or executed."""
    files = sorted((root / "events").glob("*.jsonl"))[-2:] or sorted(root.glob("events*.jsonl"))
    lines: list[str] = []
    for path in files:
        if path.is_file() and path.stat().st_size <= 400_000:
            lines.extend(path.read_text(encoding="utf-8").splitlines()[-80:])
    events = []
    for line in lines[-80:]:
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if isinstance(obj, dict):
            events.append(obj)
    heartbeats: dict[str, Any] = {}
    for name in HEARTBEAT_RIGS:
        for path in (root / "heartbeats" / f"{name}.json", root / f"heartbeat_{name}.json"):
            if path.is_file() and path.stat().st_size <= 8192:
                try:
                    heartbeats[name] = json.loads(path.read_text(encoding="utf-8"))
                except ValueError:
                    pass
                break
    channel: list[dict[str, Any]] = []
    for path in (root / "channel.jsonl", root / "cockpit" / "channel.jsonl"):
        if path.is_file():
            channel = [obj for obj in _tail_jsonl(path, MAX_CHANNEL_TAIL_BYTES, MAX_CHANNEL_LINES)
                       if obj.get("kind") in CHANNEL_KINDS][-120:]
            break
    history: dict[str, list[dict[str, Any]]] = {}
    for name in HEARTBEAT_RIGS:
        for path in (root / "heartbeats" / f"{name}.jsonl", root / f"heartbeat_history_{name}.jsonl"):
            if path.is_file():
                history[name] = _tail_jsonl(path, 400_000, MAX_HEARTBEAT_HISTORY)
                break
    return {"events": events, "heartbeats": heartbeats, "channel": channel,
            "heartbeat_history": history}


def _parse_now(value: str) -> dt.datetime:
    stamp = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if stamp.tzinfo is None:
        raise ValueError("--now needs a timezone, e.g. 2026-11-08T06:47:00Z")
    return stamp


def _ssh_client() -> str:
    """Use the existing Git SSH configuration on Windows when available.

    The stock Windows OpenSSH binary may use different config/key behavior.
    This selects a binary, not a credential or a remote authority grant.
    """
    explicit = os.environ.get("GSV_MINDS_SSH_BIN", "")
    if explicit and Path(explicit).is_file():
        return explicit
    if os.name == "nt":
        candidate = Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git" / "usr" / "bin" / "ssh.exe"
        if candidate.is_file():
            return str(candidate)
    return "ssh"


def _write_atomic(output: Path, feed: dict[str, Any]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps(feed, ensure_ascii=False, separators=(",", ":"))
    if len(content.encode("utf-8")) > MAX_RESPONSE_BYTES:
        raise RuntimeError("projected_feed_oversized")
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=output.parent,
        prefix=".prime-mind-", suffix=".tmp", delete=False,
    ) as stream:
        tmp = Path(stream.name)
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    try:
        tmp.replace(output)
    finally:
        if tmp.exists():
            tmp.unlink()


def _previous(output: Path | None) -> dict[str, Any] | None:
    """The last feed this collector wrote, source of the earlier heartbeat."""
    if output is None:
        return None
    try:
        return read_feed(output)
    except (OSError, ValueError):
        return None


def collect(*, output: Path | None, timeout: float = 16.0) -> dict[str, Any]:
    """One SSH read, projected; written to output when one is given."""
    cmd = [_ssh_client(), "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
           "-o", "ConnectTimeout=6", SSH_HOST, "python3 -"]
    creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0
    result = subprocess.run(
        cmd, input=REMOTE_SCRIPT, capture_output=True, text=True,
        encoding="utf-8", timeout=timeout, check=False, creationflags=creationflags,
    )
    if result.returncode != 0 or len(result.stdout.encode("utf-8")) > MAX_REMOTE_BYTES:
        raise RuntimeError("authenticated_archive_fetch_unavailable")
    remote = json.loads(result.stdout)
    feed = project(remote, now=utc_now(), previous=_previous(output))
    if output is not None:
        _write_atomic(output, feed)
    return feed


def collect_once(*, output: Path, timeout: float = 16.0) -> dict[str, Any]:
    feed = collect(output=output, timeout=timeout)
    return {"output": str(output), "events": len(feed["events"]), "work": len(feed["work"]),
            "source_ok": feed["source_ok"],
            "note": "one authorized read; no remote changes"}


def _instant(value: str | None, flag: str) -> str | None:
    if value is None:
        return None
    stamp = norm_stamp(value)
    if stamp is None:
        raise ValueError(f"{flag} needs a timezone-aware instant, e.g. 2026-11-08T06:00:00Z")
    return stamp


def main(argv: list[str] | None = None) -> int:
    cli = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    cli.add_argument("--output", type=Path,
                     help="Local-only file for --feed in the Godot scene")
    cli.add_argument("--from-dir", type=Path,
                     help="Project a local archive copy (e.g. the shared #14 fixture) instead of SSH")
    cli.add_argument("--now", help="With --from-dir: the UTC instant to judge heartbeat age against")
    cli.add_argument("--export-json", action="store_true",
                     help="Print the tape (thoughts + work) as JSON lines on stdout, oldest first")
    cli.add_argument("--feed", type=Path,
                     help="With --export-json: export an already-collected feed file; no collection")
    cli.add_argument("--since", help="With --export-json: keep records at or after this instant")
    cli.add_argument("--until", help="With --export-json: keep records at or before this instant")
    args = cli.parse_args(argv)
    if args.output is None and not args.export_json:
        cli.error("--output is required unless --export-json is given")
    if args.feed is not None and (not args.export_json or args.from_dir is not None):
        cli.error("--feed only applies to --export-json, without --from-dir")
    try:
        since = _instant(args.since, "--since")
        until = _instant(args.until, "--until")
        if args.feed is not None:
            feed = read_feed(args.feed)
            status = {"source": str(args.feed), "events": len(feed["events"]),
                      "work": len(feed.get("work", [])), "note": "existing feed file; no collection"}
        elif args.from_dir is not None:
            now = _parse_now(args.now) if args.now else utc_now()
            feed = project(read_local_archive(args.from_dir), now=now,
                           xanadu_detail=XANADU_LOCAL_NOTE, previous=_previous(args.output))
            if args.output is not None:
                _write_atomic(args.output, feed)
            status = {"output": str(args.output), "events": len(feed["events"]),
                      "work": len(feed["work"]), "source": str(args.from_dir),
                      "note": "local copy; no SSH"}
        else:
            feed = collect(output=args.output)
            status = {"output": str(args.output), "events": len(feed["events"]),
                      "work": len(feed["work"]), "source_ok": feed["source_ok"],
                      "note": "one authorized read; no remote changes"}
    except (subprocess.TimeoutExpired, OSError, RuntimeError, ValueError) as error:
        print(json.dumps({"state": "unavailable", "reason": str(error)}), file=sys.stderr)
        return 2
    if args.export_json:
        # stdout carries only the tape, so it can be piped and grepped; status goes to stderr.
        for row in tape_lines(feed, since=since, until=until):
            sys.stdout.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
        print(json.dumps(status), file=sys.stderr)
    else:
        print(json.dumps(status))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
