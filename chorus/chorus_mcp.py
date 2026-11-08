#!/usr/bin/env python3
"""chorus_mcp.py: the CHORUS cockpit as MCP tools, so every agent in the colony can use it natively.

Stdio MCP server (JSON-RPC 2.0, one message per line), standard library only. It wraps chorus.py:
    chorus_brief        what needs attention, the Minds, new channel messages, the spine
    chorus_rig          one rig in detail (checks, disks, RAM, what the Minds said)
    chorus_work         who edits what, and checkouts holding unsaved work
    chorus_doctor       measure the cause of each failing check (read-only probes)
    chorus_orders       work orders for this seat (or all)
    chorus_order_status take / working / done / decline an order, with a note and a link
    chorus_say          post to the shared cockpit channel as this seat

The seat comes from CHORUS_SEAT (default "claude (msi seat)"); an agent never speaks as Keath.
Register with Claude Code:
    claude mcp add chorus -e CHORUS_SEAT="claude (msi seat)" -- python <path>/chorus/chorus_mcp.py
"""
from __future__ import annotations

import contextlib
import io
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chorus  # noqa: E402

PROTOCOL = "2024-11-05"
TOOLS = [
    {"name": "chorus_brief", "description": "Colony brief: what needs attention (with measured causes), what the Minds said, new channel messages for this seat. Start here.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "chorus_rig", "description": "One rig in detail: heartbeat age, RAM, disks, every check, and what the Minds said about it.",
     "inputSchema": {"type": "object", "properties": {"rig": {"type": "string", "enum": ["msi", "i3", "l9"]}}, "required": ["rig"]}},
    {"name": "chorus_work", "description": "Who is editing what (colony claims), and checkouts holding uncommitted or unpushed work, riskiest first.",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "chorus_doctor", "description": "Run read-only probes that measure the cause of each failing check (VT-x, Docker engine, Dev-Mentor stalls, container restart policy...).",
     "inputSchema": {"type": "object", "properties": {}}},
    {"name": "chorus_orders", "description": "Work orders Keath (or a cockpit) posted. Default: open orders for this seat or 'any'.",
     "inputSchema": {"type": "object", "properties": {"all": {"type": "boolean", "description": "every seat's orders"}}}},
    {"name": "chorus_order_status", "description": "Move an order: take it, mark it working, done (say what changed, give a link), or decline (say why and what Keath must do).",
     "inputSchema": {"type": "object", "properties": {
         "id": {"type": "string"}, "status": {"type": "string", "enum": ["taken", "working", "done", "declined"]},
         "note": {"type": "string"}, "link": {"type": "string"}}, "required": ["id", "status"]}},
    {"name": "chorus_say", "description": "Post a message to the shared cockpit channel as this seat.",
     "inputSchema": {"type": "object", "properties": {
         "text": {"type": "string"}, "to": {"type": "string", "description": "a seat, e.g. 'claude (i3 seat)', 'keath (chorus)', or 'all'"}},
         "required": ["text"]}},
]


def _capture(fn, *args) -> str:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        try:
            fn(*args)
        except SystemExit as e:          # chorus.py exits with a message on bad input
            if e.code not in (None, 0):
                print(e.code)
    return buf.getvalue().strip() or "(no output)"


def call(name: str, a: dict) -> str:
    if name == "chorus_brief":
        return _capture(chorus.brief, chorus.load(), False)
    if name == "chorus_rig":
        return _capture(chorus.rig, chorus.load(), str(a.get("rig", "msi")).lower())
    if name == "chorus_work":
        return _capture(chorus.work_view, chorus.load())
    if name == "chorus_doctor":
        from doctor import diagnose
        out = [f"{x['key']}: {x['verdict']}\n    " + "\n    ".join(x["evidence"]) for x in diagnose(chorus.load())]
        return "\n".join(out) or "nothing failing that the doctor can measure"
    if name == "chorus_orders":
        return _capture(chorus.orders_view, chorus.load(), not a.get("all"))
    if name == "chorus_order_status":
        return _capture(chorus.order_status, a["id"], a["status"], a.get("note", ""), a.get("link", ""))
    if name == "chorus_say":
        return _capture(chorus.say, a["text"], a.get("to", "all"))
    raise KeyError(name)


def _log_call(tool: str) -> None:
    """Usage proof for the cockpit: which seat called which tool, when (never the arguments)."""
    try:
        import os, time
        f = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "KiloCore" / "chorus" / "mcp_calls.jsonl"
        f.parent.mkdir(parents=True, exist_ok=True)
        with f.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "tool": tool,
                                 "seat": chorus.SEAT}) + chr(10))
    except OSError:
        pass


def handle(msg: dict) -> dict | None:
    mid, method = msg.get("id"), msg.get("method")
    if method == "initialize":
        return {"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": msg.get("params", {}).get("protocolVersion", PROTOCOL),
            "capabilities": {"tools": {}}, "serverInfo": {"name": "chorus", "version": "0.1.0"},
            "instructions": "The colony cockpit. Call chorus_brief first; take orders with chorus_order_status."}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}}
    if method == "tools/call":
        p = msg.get("params", {})
        _log_call(p.get("name", "?"))
        try:
            text, err = call(p.get("name", ""), p.get("arguments") or {}), False
        except KeyError as e:
            text, err = f"unknown tool or missing argument: {e}", True
        except Exception as e:  # noqa: BLE001 - report, never crash the server
            text, err = f"{e.__class__.__name__}: {e}", True
        return {"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": text}], "isError": err}}
    if method == "ping":
        return {"jsonrpc": "2.0", "id": mid, "result": {}}
    if mid is None:          # notifications (e.g. notifications/initialized) need no reply
        return None
    return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"method not found: {method}"}}


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            reply = handle(json.loads(line))
        except ValueError:
            reply = {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}}
        if reply is not None:
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
