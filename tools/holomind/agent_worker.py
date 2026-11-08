r"""agent_worker: plug any agent with a command line into the colony's work queue.

ChatDev, OpenClaw, Serena, a local Ollama model, a script: whatever can be run as a command can take orders.
The worker watches the shared order queue for its seat, takes an order, runs the agent's own command with the
order on stdin, and posts the result back as the order's receipt. HOLOMIND, CHORUS, cockpit.py and dispatch.py
all see it at once.

    python agent_worker.py --seat "chatdev (msi)" --run "python C:/dev/chatdev/run_order.py" [--any] [--kinds review,reply] [--once]

Contract with the agent's command:
- **Input:** stdin gets the order as JSON `{id, text, url, ref, station, from, to}`. Env carries COCKPIT_ORDER_ID,
  COCKPIT_ORDER_URL and COCKPIT_SEAT.
- **Output:** exit 0 means done; non-zero means declined. The last non-empty stdout line becomes the note, and
  the first http(s) URL in stdout becomes the receipt link.
- **Progress:** the worker posts "working" when it starts, so cockpits show the seat busy.

Safety:
- It runs only the command its owner configured, on the owner's machine.
- Order text never reaches a shell: it goes to stdin, and the command is split with shlex, not run through a shell.
- One order at a time. A 30-minute timeout per order by default.
- `--dry-run` takes nothing and shows what it would run.
"""
import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import time
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import cockpit  # noqa: E402

URL = re.compile(r'https?://\S+')


def wanted(o, seat, take_any, kinds):
    if o['status'] != 'posted':
        return False
    if o['to'].lower() != seat.lower() and not (take_any and o['to'] == 'any'):
        return False
    return not kinds or o.get('station') in kinds or any(k in o['text'].lower() for k in kinds)


def run_one(o, seat, cmd, timeout, dry):
    print(f"[{seat}] {'would take' if dry else 'taking'} {o['id']}: {o['text'][:100]}")
    if dry:
        print('   command:', cmd)
        return
    cockpit.append({'at': cockpit.now(), 'from': seat, 'kind': 'order-status', 'id': o['id'], 'status': 'taken', 'note': '', 'link': ''})
    cockpit.append({'at': cockpit.now(), 'from': seat, 'kind': 'order-status', 'id': o['id'], 'status': 'working', 'note': 'started', 'link': ''})
    payload = json.dumps({k: o.get(k) for k in ('id', 'text', 'url', 'ref', 'station', 'from', 'to')}, ensure_ascii=False)
    env = dict(os.environ, COCKPIT_ORDER_ID=o['id'], COCKPIT_ORDER_URL=o.get('url', ''), COCKPIT_SEAT=seat)
    try:
        r = subprocess.run(shlex.split(cmd, posix=(os.name != 'nt')), input=payload, capture_output=True, text=True,
                           encoding='utf-8', errors='replace', timeout=timeout, env=env, stdin=None)
        out = [l for l in r.stdout.splitlines() if l.strip()]
        note = (out[-1] if out else '')[:400] if r.returncode == 0 else f"exit {r.returncode}: {(r.stderr or r.stdout).strip()[-300:]}"
        link = next(iter(URL.findall(r.stdout)), '')
        status = 'done' if r.returncode == 0 else 'declined'
    except subprocess.TimeoutExpired:
        status, note, link = 'declined', f'timed out after {timeout} s', ''
    except OSError as exc:
        status, note, link = 'declined', f'could not run the agent command: {exc}', ''
    cockpit.append({'at': cockpit.now(), 'from': seat, 'kind': 'order-status', 'id': o['id'], 'status': status, 'note': note, 'link': link})
    print(f"   -> {status}: {note[:120]} {link}")


def main():
    a = argparse.ArgumentParser(description='Plug any command-line agent into the colony work queue.')
    a.add_argument('--seat', required=True, help='this agent\'s seat name as orders address it, e.g. "chatdev (msi)"')
    a.add_argument('--run', required=True, help='the agent command; gets the order JSON on stdin')
    a.add_argument('--any', action='store_true', help='also take orders addressed to "any"')
    a.add_argument('--kinds', default='', help='comma list of stations or words to accept (e.g. review,reply)')
    a.add_argument('--every', type=int, default=60, help='poll seconds')
    a.add_argument('--timeout', type=int, default=1800)
    a.add_argument('--once', action='store_true')
    a.add_argument('--dry-run', action='store_true')
    args = a.parse_args()
    kinds = [k.strip().lower() for k in args.kinds.split(',') if k.strip()]
    while True:
        orders = [o for o in cockpit.fold_orders_all(cockpit.all_lines()) if wanted(o, args.seat, args.any, kinds)]
        if orders:
            run_one(orders[0], args.seat, args.run, args.timeout, args.dry_run)
        elif args.once:
            print(f'[{args.seat}] no orders for this seat')
        if args.once:
            return
        time.sleep(args.every)


if __name__ == '__main__':
    main()
