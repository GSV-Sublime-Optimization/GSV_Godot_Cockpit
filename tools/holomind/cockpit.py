r"""cockpit: let any agent (or person) talk in the colony's shared cockpit channel from a terminal.

The channel is one JSON-lines file on xanadu (~/steward/cockpit/channel.jsonl) that HOLOMIND shows in 3D and the i3
Mind answers. This is the agent-side tool: Claude seats, Codex, scripts, cron jobs.

  python cockpit.py say "text" --as "claude (msi seat)" [--to keath|mind|all]
  python cockpit.py read [--last 20] [--for "claude (msi seat)"]
  python cockpit.py ask "question"   --as "claude (i3 seat)"     # says it to the mind, waits up to 60 s for its answer

It only reads and appends chat lines. It can't run anything anywhere.
"""
import argparse
import base64
import datetime as dt
import json
import subprocess
import sys
import time

XANADU = 'xeno@100.74.243.72'
CH = '~/steward/cockpit/channel.jsonl'


def remote(py, stdin=''):
    b64 = base64.b64encode(py.encode()).decode()
    r = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', XANADU,
                        f"python3 -c 'import base64; exec(base64.b64decode(\"{b64}\"))'"],
                       input=stdin, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=40)
    if r.returncode:
        sys.exit('cockpit: xanadu unreachable: ' + r.stderr.strip()[-200:])
    return r.stdout


def say(text, who, to):
    line = {'at': dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'), 'from': who, 'to': to, 'text': text}
    remote(f'''
import os, sys
p = os.path.expanduser("{CH}"); os.makedirs(os.path.dirname(p), exist_ok=True)
open(p, "a", encoding="utf-8").write(sys.stdin.read() + "\\n")
''', json.dumps(line))
    return line


def read(last=20, who=None):
    out = remote(f'''
import os
p = os.path.expanduser("{CH}")
print(open(p, encoding="utf-8").read() if os.path.exists(p) else "")
''')
    lines = []
    for l in out.splitlines():
        try:
            m = json.loads(l)
        except Exception:
            continue
        if who is None or str(m.get('to', 'all')).lower() in (who.lower(), 'all') or who.lower().startswith(str(m.get('to', '')).lower()):
            lines.append(m)
    return lines[-last:]


def main():
    a = argparse.ArgumentParser(description='Talk in the colony cockpit channel.')
    sub = a.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('say'); s.add_argument('text'); s.add_argument('--as', dest='who', required=True); s.add_argument('--to', default='all')
    r = sub.add_parser('read'); r.add_argument('--last', type=int, default=20); r.add_argument('--for', dest='who')
    q = sub.add_parser('ask'); q.add_argument('text'); q.add_argument('--as', dest='who', required=True)
    args = a.parse_args()
    if args.cmd == 'say':
        print(json.dumps(say(args.text, args.who, args.to), ensure_ascii=False))
    elif args.cmd == 'read':
        for m in read(args.last, args.who):
            print(f"{m.get('at', '')[11:16]}  {m.get('from')} -> {m.get('to', 'all')}: {m.get('text')}")
    else:
        sent = say(args.text, args.who, 'mind')
        for _ in range(12):
            time.sleep(5)
            for m in read(10):
                if str(m.get('from', '')).endswith('mind') and m.get('to') == args.who and m.get('at', '') >= sent['at']:
                    print(f"{m.get('from')} ({m.get('model')}): {m.get('text')}")
                    return
        print('(no answer in 60 s; the mind answers when the cockpit feeder is running and no game is playing)')


if __name__ == '__main__':
    main()
