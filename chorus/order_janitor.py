#!/usr/bin/env python3
"""order_janitor.py: close Forge orders whose PR has merged, closed, or moved.

Diagnosis: the Forge's shop.orders() fold only changes an order's status
when an agent writes an order-status line to the shared channel
(xanadu:~/steward/cockpit/channel.jsonl). Nothing ever closes an order
when its PR merges, closes unmerged, or moves to a new head, so stale
orders sit as [posted] forever and the shop report lists work that is
already done. This janitor is the missing closer.

It reads the FULL channel from xanadu (the feeder only reads the last 400
lines), folds the orders with shop.orders(), checks each posted order's PR
live with gh, and appends an order-status line (from "janitor") for the
ones whose PR is merged, closed unmerged, or has moved past the head the
order named.

It never writes to the feeder and never touches mindview_feed.py's
read-only-toward-xanadu contract; it is a separate, explicitly scheduled
job. It only ever closes `posted` orders, never taken/working/done/
declined ones, and never closes an order whose PR state could not be
determined (gh failure, unknown repo, no PR reference) -- those are
logged and skipped. Idempotent by construction: once an order is done it
is no longer posted, so a re-run skips it.

Usage:
    python chorus/order_janitor.py              # dry run (default): print, write nothing
    python chorus/order_janitor.py --apply      # append the order-status lines
"""
from __future__ import annotations

import argparse
import json
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from shop import orders as fold_orders  # noqa: E402

FROM = "janitor"

# Short repo names as they appear in order text, mapped to full org/repo.
REPO_MAP = {
    "dev": "GSV-Sublime-Optimization/dev",
    "echoes-of-elevation": "Echoes-Of-Elevation/echoes-of-elevation",
    "Furyline": "Furyline/Furyline",
    "GSV_Godot_Cockpit": "GSV-Sublime-Optimization/GSV_Godot_Cockpit",
    "KiloEthereal_Prime_Architect": "GSV-Sublime-Optimization/KiloEthereal_Prime_Architect",
    "Forge-Build": "Trueform-Forge/Forge-Build",
    "Dev-Mentor": "GSV-Sublime-Optimization/Dev-Mentor",
    "Kilo_Core": "GSV-Sublime-Optimization/Kilo_Core",
    "KiloCore-Plugins": "GSV-Sublime-Optimization/KiloCore-Plugins",
    "NuSyQ-Hub": "GSV-Sublime-Optimization/NuSyQ-Hub",
    "Module-Exchange": "GSV-Sublime-Optimization/Module-Exchange",
}

PR_URL_RE = re.compile(r"github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/(\d+)")
PR_FULL_RE = re.compile(r"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#(\d+)")
PR_SHORT_RE = re.compile(r"([A-Za-z0-9_.-]+)#(\d+)")
HEAD_RE = re.compile(r"head\s+([0-9a-f]{8,40})", re.I)


def pr_url(repo: str, number: int) -> str:
    return f"https://github.com/{repo}/pull/{number}"


def extract_pr(order: dict) -> tuple[str, int] | None:
    """The PR an order is about, from its link (GitHub PR URL) or its text.

    Link wins; then a full org/repo#n in the text; then a short repo#n
    mapped through REPO_MAP. Returns (full repo, number) or None when the
    order names no PR the janitor can resolve.
    """
    for source in (order.get("link") or "", order.get("text") or ""):
        m = PR_URL_RE.search(source)
        if m:
            return m.group(1), int(m.group(2))
    text = order.get("text") or ""
    m = PR_FULL_RE.search(text)
    if m:
        return m.group(1), int(m.group(2))
    for m in PR_SHORT_RE.finditer(text):
        repo = REPO_MAP.get(m.group(1))
        if repo:
            return repo, int(m.group(2))
    return None


def named_head(order: dict) -> str | None:
    """The head sha the order names (e.g. 'at head eba64e7f690c'), if any."""
    m = HEAD_RE.search(order.get("text") or "")
    return m.group(1).lower() if m else None


def decide(order: dict, state: str, head: str) -> tuple[str, str] | None:
    """(note, link) for closing this posted order, or None to leave it alone.

    state/head are the PR's live values from gh. Merged or closed wins
    over the head rule: a merged PR is done whatever head the order named.
    """
    ref = extract_pr(order)
    if ref is None:
        return None
    repo, number = ref
    link = order.get("link") or pr_url(repo, number)
    if state == "MERGED":
        return f"{repo}#{number} merged", link
    if state == "CLOSED":
        return f"{repo}#{number} closed unmerged", link
    if state != "OPEN":
        return None
    named = named_head(order)
    if named and head and not (head.lower().startswith(named) or named.startswith(head.lower())):
        return (f"PR moved to {head[:8]}; order's head is stale "
                f"-- re-post if the fix is still owed at the new head"), link
    return None


def read_channel() -> list[dict]:
    """The FULL channel from xanadu (the feeder reads only the last 400 lines)."""
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "xanadu",
                        "cat ~/steward/cockpit/channel.jsonl"],
                       capture_output=True, text=True, timeout=60,
                       encoding="utf-8", errors="replace")
    if r.returncode:
        raise RuntimeError(f"xanadu unreachable (ssh exit {r.returncode})")
    out = []
    for line in r.stdout.splitlines():
        line = line.strip()
        if line:
            try:
                out.append(json.loads(line))
            except ValueError:
                pass
    return out


def gh_pr_state(repo: str, number: int) -> tuple[str, str] | None:
    """(state, headRefOid) for a PR, or None when gh cannot tell us."""
    r = subprocess.run(["gh", "pr", "view", str(number), "--repo", repo,
                        "--json", "state,headRefOid"],
                       capture_output=True, text=True, timeout=30,
                       encoding="utf-8", errors="replace")
    if r.returncode:
        return None
    try:
        info = json.loads(r.stdout or "{}")
    except ValueError:
        return None
    state, head = info.get("state"), info.get("headRefOid") or ""
    return (state, head) if state else None


def append_status(order_id: str, note: str, link: str) -> bool:
    """Append one order-status line to xanadu's channel (the flush_acks destination).

    The payload goes on the remote command line (printf with a quoted
    argument), NOT through stdin: piping stdin to ssh hangs from MSI
    python (the ssh child never sees EOF and the call times out -- measured
    2026-11-09), while the printf form returns immediately. Same file,
    same line shape as flush_acks writes.
    """
    rec = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "from": FROM, "to": "all",
           "kind": "order-status", "id": order_id, "status": "done", "note": note, "link": link}
    payload = shlex.quote(json.dumps(rec) + "\n")
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "xanadu",
                        f"printf '%s' {payload} >> ~/steward/cockpit/channel.jsonl"],
                       capture_output=True, text=True, timeout=30)
    return r.returncode == 0


def run(channel: list[dict], apply: bool, gh=gh_pr_state, append=append_status) -> dict:
    """Fold the channel, decide every posted order, close the stale ones.

    gh/append are injectable for tests. Returns a report dict.
    """
    posted = [o for o in fold_orders(channel) if o.get("status") == "posted"]
    report = {"posted": len(posted), "closed": [], "skipped": [], "errors": []}
    for order in posted:
        ref = extract_pr(order)
        if ref is None:
            report["skipped"].append({"id": order["id"], "reason": "no PR reference in link or text"})
            continue
        repo, number = ref
        live = gh(repo, number)
        if live is None:
            report["errors"].append({"id": order["id"], "repo": repo, "number": number,
                                     "reason": "gh could not determine PR state -- left alone"})
            continue
        state, head = live
        decision = decide(order, state, head)
        if decision is None:
            report["skipped"].append({"id": order["id"], "repo": repo, "number": number,
                                      "reason": f"PR {state} at {head[:8]} -- still valid"})
            continue
        note, link = decision
        if apply:
            if not append(order["id"], note, link):
                report["errors"].append({"id": order["id"], "reason": "failed to append order-status"})
                continue
        report["closed"].append({"id": order["id"], "repo": repo, "number": number,
                                 "state": state, "head": head[:8], "note": note, "link": link,
                                 "applied": apply})
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--apply", action="store_true",
                    help="append the order-status lines (default is a dry run)")
    ap.add_argument("--channel-file", help="read the channel from a local file instead of xanadu")
    args = ap.parse_args()
    try:
        if args.channel_file:
            channel = [json.loads(l) for l in Path(args.channel_file).read_text(encoding="utf-8").splitlines()
                       if l.strip()]
        else:
            channel = read_channel()
    except (OSError, RuntimeError, ValueError) as e:
        print(f"order_janitor: cannot read channel: {e}", file=sys.stderr)
        return 1
    report = run(channel, apply=args.apply)
    print(f"posted orders: {report['posted']}")
    for c in report["closed"]:
        print(f"  CLOSE {c['id']} {c['repo']}#{c['number']} ({c['state']} {c['head']}): {c['note']}"
              f"{'' if c['applied'] else ' [dry run]'}")
    for s in report["skipped"]:
        print(f"  skip  {s['id']}: {s['reason']}")
    for e in report["errors"]:
        print(f"  ERROR {e['id']}: {e['reason']}", file=sys.stderr)
    print(f"closed: {len(report['closed'])}, skipped: {len(report['skipped'])}, "
          f"errors: {len(report['errors'])}"
          f"{'' if args.apply else ' (dry run -- nothing written)'}")
    return 1 if report["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
