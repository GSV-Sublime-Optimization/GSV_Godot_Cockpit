r"""dispatch: the colony's work queue, scored for yield and matched to the agent best suited and free to do it.

Borrowed from Trueform Forge's generation queue: one authoritative queue with a visible snapshot (position,
status), drained by workers. Borrowed from Media-Sieve: plan, then preflight, then execute, then receipt.
The queue is the cockpit brief (xanadu:~/steward/cockpit/brief.json). Orders are the shared channel's
order lines, the same as HOLOMIND, CHORUS and cockpit.py use.

    python dispatch.py next --as "claude (i3 seat)"   # your single highest-yield move, and how to start it
    python dispatch.py queue                          # the whole queue, scored, with who fits each item
    python dispatch.py plan                           # one proposed assignment per free seat (dry run)
    python dispatch.py assign [--max 3]               # post those assignments as orders from "dispatcher"

Rules:
- Never assign a review to the PR's author.
- Never give a seat more than one open order.
- Keath's decisions only ever go to Keath.
- A seat is free when it has no taken or working order.
Scoring is deliberately simple and printed, so it can be argued with and tuned.
"""
import argparse
import datetime as dt
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import cockpit  # noqa: E402  (shares the xanadu transport and order fold)

# Who can do what. Skills are matched against item text; 'rigs' are machines a seat can act on directly.
SEATS = {
    'claude (i3 seat)': {'agent': 'Claude', 'home': 'i3', 'rigs': ['i3', 'xanadu'],
                         'skills': ['review', 'python', 'godot', 'cockpit', 'holomind', 'docs', 'colony', 'mirror', 'fleet', 'windows', 'radio', 'storage']},
    'claude (msi seat)': {'agent': 'Claude', 'home': 'msi', 'rigs': ['msi', 'xanadu'],
                          'skills': ['review', 'python', 'docker', 'chorus', 'dev-mentor', 'spine', 'msi', 'mirror', 'backup', 'colony', 'docs']},
    'gpt-6': {'agent': 'GPT-6', 'home': 'cloud', 'rigs': [], 'skills': ['review', 'godot', 'entity', 'studio', 'fleet', 'mind']},
    'codex': {'agent': 'Codex', 'home': 'cloud', 'rigs': [], 'skills': ['review', 'python', 'tests', 'docs', 'echoes']},
    'muse': {'agent': 'Muse', 'home': 'cloud', 'rigs': [], 'skills': ['design', 'godot', 'cockpit', 'atlas', 'hologram']},
}
BASE = {'rig': 60, 'review': 40, 'reply': 30, 'decision': 50}   # impact by kind


def brief():
    raw = cockpit.remote('import os; p = os.path.expanduser("~/steward/cockpit/brief.json"); print(open(p, encoding="utf-8").read() if os.path.exists(p) else "{}")')
    return json.loads(raw or '{}')


def busy_seats(lines):
    return {o['by'] or o['to'] for o in cockpit.fold_orders_all(lines) if o['status'] in ('taken', 'working', 'posted') and (o['by'] or o['to']) in SEATS}


HUMAN_ONLY = ('bios', 'vt-x', 'physical', 'unplug', 'power cycle', 'keyboard at', 'reboot into firmware')


def blocked_on_human(item, b):
    """A doctor verdict that needs hands on the machine (BIOS, cables, power) makes the item Keath's, not an agent's."""
    text = item.get('title', '').lower()
    for v in ((b.get('colony') or {}).get('doctor') or []):
        rig, _, check = str(v.get('key', '')).partition(':')
        if rig and check and rig in text and check in text and any(h in str(v.get('verdict', '')).lower() for h in HUMAN_ONLY):
            return v.get('verdict')
    return None


def fit(seat, item):
    """How well a seat fits an item: 0 means it must not take it."""
    s = SEATS[seat]
    kind, where, text = item.get('kind', ''), str(item.get('where', '')).lower(), item.get('title', '').lower()
    if kind == 'decision':
        return 0                                   # Keath's call, never an agent's
    if kind == 'review' and where == s['agent'].lower() and (s['home'] == 'cloud' or seat.endswith(f"({s['home']} seat)")):
        # the author can't be the second reviewer; both Claude seats share the 'Claude' author tag, so be strict
        return 0
    if kind == 'rig':
        rig = next((r for r in ('msi', 'i3', 'l9', 'xanadu') if r in text or r == where), '')
        if rig and rig not in s['rigs']:
            return 0                               # can't act on that machine directly
    if kind == 'reply' and seat.lower() not in text:
        return 0                                   # replies go to whoever was asked
    score = 1 + sum(2 for k in s['skills'] if k in text)
    return score


def yield_of(item):
    """Impact x unblocking, with a little weight for age. Printed so it can be tuned."""
    kind, text = item.get('kind', ''), item.get('title', '').lower()
    y = BASE.get(kind, 20)
    if 'red' in text or 'down' in text or 'critical' in text:
        y += 25
    if kind == 'review':
        y += 10                                    # every review unblocks a merge: the colony's main bottleneck
        if 'fix' in text:
            y += 10                                # a fix waiting on review is broken colony waiting
    return y


def candidates(b, lines):
    busy = busy_seats(lines)
    ordered = {o.get('ref') for o in cockpit.fold_orders_all(lines) if o['status'] not in ('declined',)}
    out = []
    for item in b.get('actions', []):
        iid = item.get('id') or (item['kind'] + ':' + item.get('url', item['title'])[:120])
        if iid in ordered or item.get('decided'):
            continue
        human = blocked_on_human(item, b)
        if human:
            item = dict(item, kind='decision', title=item['title'] + f'  [needs Keath: {human}]')
        fits = sorted(((fit(s, item), s) for s in SEATS), reverse=True)
        fits = [(f, s) for f, s in fits if f > 0]
        out.append({'id': iid, 'item': item, 'yield': yield_of(item), 'fits': fits,
                    'free': [s for f, s in fits if s not in busy]})
    return sorted(out, key=lambda c: (-c['yield'], c['item'].get('title', ''))), busy


def how_to_start(item):
    kind, url = item.get('kind'), item.get('url', '')
    if kind == 'review':
        return f"read the diff and run its tests, then: python tools/gsv/gsv.py review post <owner/repo#N> --as agent/claude-code --verdict approve|request-changes --head <sha> --body-file <file>   ({url})"
    if kind == 'rig':
        return 'measure first (heartbeat checks, doctor), fix in your own lane, and post the receipt'
    if kind == 'reply':
        return 'answer in the channel: python cockpit.py say "..." --as <seat> --to <asker>'
    return 'see the item'


def main():
    a = argparse.ArgumentParser(description='The colony work queue, scored and matched to the best free agent.')
    sub = a.add_subparsers(dest='cmd', required=True)
    n = sub.add_parser('next'); n.add_argument('--as', dest='who', required=True)
    sub.add_parser('queue')
    sub.add_parser('plan')
    s = sub.add_parser('assign'); s.add_argument('--max', type=int, default=3)
    args = a.parse_args()
    b, lines = brief(), cockpit.all_lines()
    cands, busy = candidates(b, lines)
    if args.cmd == 'queue':
        print(f"COLONY QUEUE · {len(cands)} unassigned · busy seats: {', '.join(sorted(busy)) or 'none'}")
        for i, c in enumerate(cands):
            fits = ', '.join(f"{s}({f})" for f, s in c['fits'][:3]) or 'nobody but Keath'
            print(f"{i + 1:>2}. y={c['yield']:>3} [{c['item']['kind']:8}] {c['item']['title'][:90]}\n      fits: {fits}")
        return
    if args.cmd == 'next':
        mine = [c for c in cands if any(s == args.who for _, s in c['fits'])]
        if not mine:
            print('nothing in the queue fits you right now')
            return
        c = mine[0]
        print(f"NEXT for {args.who}: [{c['item']['kind']}] {c['item']['title']}\n  yield {c['yield']} · your fit {dict((s, f) for f, s in c['fits'])[args.who]} · {c['item'].get('url', '')}\n  start: {how_to_start(c['item'])}")
        if args.who in busy:
            print('  (you already have an open order: finish that first)')
        return
    # plan / assign: one item per free seat, best yield first, best fit wins
    taken, plan = set(busy), []
    for c in cands:
        seat = next((s for s in c['free'] if s not in taken), None)
        if seat:
            taken.add(seat)
            plan.append((seat, c))
    for seat, c in plan:
        print(f"{seat:18} <- y={c['yield']} [{c['item']['kind']}] {c['item']['title'][:90]}")
    if not plan:
        print('no free seat fits any unassigned item')
    if args.cmd == 'assign':
        now = dt.datetime.now(dt.timezone.utc)
        for i, (seat, c) in enumerate(plan[:args.max]):
            line = {'at': now.strftime('%Y-%m-%dT%H:%M:%SZ'), 'from': 'dispatcher', 'kind': 'order',
                    'id': f"o-{now.strftime('%m%d-%H%M%S')}-d{i}", 'to': seat, 'station': 'pegs' if c['item']['kind'] == 'review' else 'anvil',
                    'text': c['item']['title'] + (f"  {c['item'].get('url')}" if c['item'].get('url') else ''), 'ref': c['id'],
                    'url': c['item'].get('url', ''), 'yield': c['yield'], 'via': 'dispatch'}
            cockpit.append(line)
            print('posted', line['id'], '->', seat)


if __name__ == '__main__':
    main()
