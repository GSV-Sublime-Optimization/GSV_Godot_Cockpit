#!/usr/bin/env python3
"""claude_activity.py: Claude Code PostToolUse hook -> CHORUS's "MSI Claude" mind stream.

Appends one line per tool call to %LOCALAPPDATA%/KiloCore/chorus/claude_events.jsonl:
    {"at", "mind": "msi-claude", "tool", "label"}
PRIVACY: it records only the tool name and a short label: a Bash call's *description*,
a file's name (not its path or contents), a search pattern's first 40 chars, an agent's
description. It never records command text, file contents or tool output. It is local only,
never sent anywhere. The file rotates at 512 KB. Any error exits 0 silently: a cockpit must
never block the work it watches.
"""
import json
import os
import sys
import time
from pathlib import Path

OUT = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "KiloCore" / "chorus" / "claude_events.jsonl"
MAX = 512 * 1024


def label(tool: str, ti: dict) -> str:
    if tool in ("Bash", "PowerShell"):
        return (ti.get("description") or "ran a command")[:90]
    for k in ("file_path", "notebook_path"):
        if ti.get(k):
            return f"{Path(str(ti[k])).name}"[:90]
    if tool in ("Grep", "Glob"):
        return f"searched for {str(ti.get('pattern', ''))[:40]}"
    if tool == "Agent":
        return f"delegated: {str(ti.get('description', ''))[:70]}"
    if tool == "SendMessage":
        return f"messaged {str(ti.get('to', ''))[:20]}: {str(ti.get('summary', ''))[:60]}"
    if tool.startswith("mcp__"):
        return tool.split("__")[-1].replace("_", " ")[:60]
    return tool


def main() -> None:
    try:
        ev = json.load(sys.stdin)
        tool = str(ev.get("tool_name", "?"))
        rec = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "mind": "msi-claude",
               "tool": tool, "label": label(tool, ev.get("tool_input") or {})}
        OUT.parent.mkdir(parents=True, exist_ok=True)
        if OUT.exists() and OUT.stat().st_size > MAX:
            OUT.replace(OUT.with_suffix(".old.jsonl"))
        with OUT.open("a", encoding="utf-8") as f:
            f.write(json.dumps(rec) + "\n")
    except Exception:  # noqa: BLE001 - the hook must never fail the tool call
        pass


if __name__ == "__main__":
    main()
