r"""cockpit: let any agent (or person) talk in the colony's shared cockpit channel from a terminal.

The channel is one JSON-lines file on xanadu (~/steward/cockpit/channel.jsonl) that HOLOMIND shows in 3D and the i3
Mind answers. This is the agent-side tool: Claude seats, Codex, scripts, cron jobs.

  python cockpit.py say "text" --as "claude (msi seat)" [--to keath|mind|all]
  python cockpit.py read [--last 20] [--for "claude (msi seat)"]
  python cockpit.py ask "question"   --as "claude (i3 seat)"     # says it to the mind, waits up to 60 s for its answer

Work orders (the same queue CHORUS uses; HOLOMIND assigns them from its work cards):
  python cockpit.py orders [--for "claude (i3 seat)"]          # open orders, yours first
  python cockpit.py take ID --as "claude (i3 seat)"              # you're on it (shows as TAKEN on the card)
  python cockpit.py status ID done --as SEAT --link URL --note "approved, 17/17"   # working|done|declined

It only reads and appends channel lines. It can't run anything anywhere: the agent does the work in its own lanes
(gsv review post, Studio missions, PRs) and posts the receipt here.
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


def append(line):
    remote(f'''
import os, sys
p = os.path.expanduser("{CH}"); os.makedirs(os.path.dirname(p), exist_ok=True)
open(p, "a", encoding="utf-8").write(sys.stdin.read() + "\n")
''', json.dumps(line, ensure_ascii=False))
    return line


def now():
    return dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def all_lines():
    out = remote(f'''
import os
p = os.path.expanduser("{CH}")
print(open(p, encoding="utf-8").read() if os.path.exists(p) else "")
''')
    lines = []
    for l in out.splitlines():
        try:
            lines.append(json.loads(l))
        except Exception:
            pass
    return lines


def open_orders(seat=None):
    sys.path.insert(0, str(__import__('pathlib').Path(__file__).parent))
    from cockpit_feed import fold_orders
    os_ = [o for o in fold_orders(all_lines()) if o['status'] not in ('done', 'declined')]
    if seat:
        os_.sort(key=lambda o: (0 if o['to'].lower() == seat.lower() else 1 if o['to'] == 'any' else 2))
    return os_


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
        if m.get('kind') == 'read':
            continue
        if who is None or str(m.get('to', 'all')).lower() in (who.lower(), 'all') or who.lower().startswith(str(m.get('to', '')).lower()):
            lines.append(m)
    if who:
        # Leave a read receipt, so senders see "read by <seat>" in the cockpit.
        mark = {'kind': 'read', 'from': who, 'at': dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}
        remote(f'''
import os, sys
open(os.path.expanduser("{CH}"), "a", encoding="utf-8").write(sys.stdin.read() + "\\n")
''', json.dumps(mark))
    return lines[-last:]


def main():
    a = argparse.ArgumentParser(description='Talk in the colony cockpit channel.')
    sub = a.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('say'); s.add_argument('text'); s.add_argument('--as', dest='who', required=True); s.add_argument('--to', default='all')
    r = sub.add_parser('read', help='read the channel; with --for SEAT also leave a read receipt as that seat')
    r.add_argument('--last', type=int, default=20); r.add_argument('--for', dest='who')
    q = sub.add_parser('ask'); q.add_argument('text'); q.add_argument('--as', dest='who', required=True)
    b = sub.add_parser('brief', help='the colony in one screen: rigs, agents at work, the work queue, the last messages')
    b.add_argument('--json', action='store_true')
    o = sub.add_parser('orders', help='open work orders (yours first)'); o.add_argument('--for', dest='who')
    t = sub.add_parser('take', help='take an order'); t.add_argument('id'); t.add_argument('--as', dest='who', required=True)
    st = sub.add_parser('status', help='report on an order'); st.add_argument('id'); st.add_argument('status', choices=['working', 'done', 'declined'])
    st.add_argument('--as', dest='who', required=True); st.add_argument('--link', default=''); st.add_argument('--note', default='')
    args = a.parse_args()
    if args.cmd == 'orders':
        os_ = open_orders(args.who)
        if not os_:
            print('no open orders')
        for x in os_:
            print(f"{x['id']}  [{x['status']:7}] to {x['to']:20} {x['text'][:110]}" + (f"  ({x['by']})" if x['by'] else ''))
        return
    if args.cmd in ('take', 'status'):
        status = 'taken' if args.cmd == 'take' else args.status
        line = append({'at': now(), 'from': args.who, 'kind': 'order-status', 'id': args.id, 'status': status,
                       'note': getattr(args, 'note', ''), 'link': getattr(args, 'link', '')})
        print(json.dumps(line, ensure_ascii=False))
        return
    if args.cmd == 'brief':
        raw = remote('import os; p = os.path.expanduser("~/steward/cockpit/brief.json"); print(open(p, encoding="utf-8").read() if os.path.exists(p) else "{}")')
        d = json.loads(raw or '{}')
        if args.json or not d:
            print(json.dumps(d, indent=1, ensure_ascii=False) if d else '(no brief yet: is cockpit_feed.py running on the i3?)')
            return
        print(f"COLONY BRIEF {d.get('at')}  ·  i3 screen: {d.get('screen')}")
        print('rigs: ' + '  '.join(f"{k}={v['status']}" + (f"({','.join(v['failing'])})" if v['failing'] else '') for k, v in d.get('rigs', {}).items()))
        print('agents at work:')
        for g in d.get('agents', []):
            print(f"  {g['agent']:<18} {g['latest'][:90]}")
        acts = d.get('actions', [])
        kinds = {}
        for x in acts:
            kinds[x['kind']] = kinds.get(x['kind'], 0) + 1
        print(f"work waiting ({len(acts)}: " + ', '.join(f'{v} {k}' for k, v in kinds.items()) + '):')
        for x in acts:
            print(f"  [{x['kind']:<8}] {x['where']:<12} {x['title'][:100]}" + (f"  {x['url']}" if x.get('url') else ''))
        print('last messages:')
        for m in d.get('channel', [])[-5:]:
            print(f"  {str(m.get('at', ''))[11:16]} {m.get('from')} -> {m.get('to')}: {str(m.get('text'))[:100]}")
        return
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
