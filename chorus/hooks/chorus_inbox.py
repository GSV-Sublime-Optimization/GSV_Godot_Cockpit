#!/usr/bin/env python3
"""chorus_inbox.py: Claude Code UserPromptSubmit hook. It hands cockpit messages to the MSI Claude.

CHORUS (and HOLOMIND) share one conversation: xanadu:~/steward/cockpit/channel.jsonl. The CHORUS
feeder caches it locally every 15 s (%LOCALAPPDATA%/KiloCore/chorus/channel.cache.jsonl). On
Keath's next prompt this hook prints the messages addressed to the MSI seat (or to "all") that
Claude hasn't seen yet. UserPromptSubmit stdout becomes context for Claude. It is local only
(no network) and any error exits 0 silently.
"""
import json
import os
from pathlib import Path

BASE = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "KiloCore" / "chorus"
CACHE, SEEN, ACKS = BASE / "channel.cache.jsonl", BASE / "channel.seen", BASE / "acks.jsonl"
ME = "claude (msi seat)"


def main() -> None:
    try:
        if not CACHE.exists():
            return
        msgs = [json.loads(l) for l in CACHE.read_text(encoding="utf-8").splitlines() if l.strip()]
        last = SEEN.read_text().strip() if SEEN.exists() else ""
        new = [m for m in msgs if m.get("at", "") > last and m.get("from") != ME
               and m.get("to") in (ME, "all", "claude")]
        if new:
            print("[CHORUS] New in the cockpit channel for the MSI seat (react to these):")
            for m in new[-8:]:
                print(f"  - {m.get('at', '')} {m.get('from', '?')} -> {m.get('to', '?')}: {str(m.get('text', ''))[:300]}")
            # read receipts: the CHORUS feeder posts these to the channel on its next cycle
            with ACKS.open("a", encoding="utf-8") as f:
                for m in new:
                    f.write(json.dumps({"at": m.get("at"), "from": m.get("from")}) + chr(10))
        if msgs:
            SEEN.write_text(max(m.get("at", "") for m in msgs))
    except Exception:  # noqa: BLE001
        pass


if __name__ == "__main__":
    main()
