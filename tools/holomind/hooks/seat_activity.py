#!/usr/bin/env python3
"""seat_activity.py: a Claude Code PostToolUse hook, so the cockpit shows an agent seat *working* in real time.

Adapted from CHORUS's hooks/claude_activity.py (PR #16, MSI Claude), with the same privacy rules. It records only:
- the tool name;
- a short label: a shell call's *description*, a file's name (not its path or contents), the first 40 characters
  of a search pattern, or an agent's description.
It never records command text, file contents or tool output.

One line per tool call goes to C:/Users/Public/colony/mindview/activity.jsonl (override with COCKPIT_ACTIVITY),
with mind = COCKPIT_SEAT (default "claude (i3 seat)"). HOLOMIND's feeder turns it into the seat's live ticker and
pulses, and publishes the last few lines in brief.json, so other cockpits see it too. The file rotates at 512 KB.
Any error exits 0 silently: a cockpit must never block the work it watches.
"""
import json
import os
import sys
import time
from pathlib import Path

OUT = Path(os.environ.get('COCKPIT_ACTIVITY', 'C:/Users/Public/colony/mindview/activity.jsonl'))
SEAT = os.environ.get('COCKPIT_SEAT', 'claude (i3 seat)')
MAX = 512 * 1024


def label(tool: str, ti: dict) -> str:
    if tool in ('Bash', 'PowerShell'):
        return (ti.get('description') or 'ran a command')[:90]
    for k in ('file_path', 'notebook_path'):
        if ti.get(k):
            return Path(str(ti[k])).name[:90]
    if tool in ('Grep', 'Glob'):
        return f"searched for {str(ti.get('pattern', ''))[:40]}"
    if tool == 'Agent':
        return f"delegated: {str(ti.get('description', ''))[:70]}"
    if tool == 'SendMessage':
        return f"messaged {str(ti.get('to', ''))[:24]}"
    if tool.startswith('mcp__'):
        return tool.split('__')[-1].replace('_', ' ')[:60]
    return tool


def main() -> None:
    try:
        ev = json.load(sys.stdin)
        tool = str(ev.get('tool_name', '?'))
        rec = {'at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'mind': SEAT, 'tool': tool,
               'label': label(tool, ev.get('tool_input') or {})}
        OUT.parent.mkdir(parents=True, exist_ok=True)
        if OUT.exists() and OUT.stat().st_size > MAX:
            OUT.replace(OUT.with_suffix('.old.jsonl'))
        with OUT.open('a', encoding='utf-8') as f:
            f.write(json.dumps(rec, ensure_ascii=False) + '\n')
    except Exception:  # the hook must never fail the tool call
        pass


if __name__ == '__main__':
    main()
