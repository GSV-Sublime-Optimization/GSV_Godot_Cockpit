r"""dispatch: the colony's work queue, scored for yield and matched to the agent best suited and free to do it.

Borrowed from Trueform Forge's generation queue: one authoritative queue with a visible snapshot (position,
status), drained by workers. Borrowed from Media-Sieve: plan, then preflight, then execute, then receipt.
The queue is the cockpit brief (xanadu:~/steward/cockpit/brief.json). Orders are the shared channel's
order lines, the same as HOLOMIND, CHORUS and cockpit.py use.

    python dispatch.py next --as "claude (i3 seat)"   # your single highest-yield move, and how to start it
    python dispatch.py queue                          # the whole queue, scored, with who fits each item
    python dispatch.py plan                           # one proposed assignment per free seat (dry run)
    python dispatch.py assign [--max 3] [--bridge]    # post those assignments as orders from "dispatcher"
    python dispatch.py reconcile                      # close orders GitHub shows done (reviews at head, gates now green)

Rules:
- Never assign a review to the PR's author.
- Never give a seat more than one open order.
- Keath's decisions only ever go to Keath.
- A seat is free when it has no taken or working order.
- Gates before judgement: a review is assigned only when the merge gate (gsv.py merge --dry-run, cached 15 min)
  says review is the sole thing missing. Otherwise the PR's mechanical prerequisite is ordered instead (gsv_ci verify
  on the seat that can run it, the provenance block from the author, mark ready), or it is held (stacked: merge the
  base PR first; mergeable: Keath's).
- --bridge: an order to a cloud seat (gpt-6, codex, muse) also gets ONE PR comment, since they never read the
  channel; `reconcile` closes it from GitHub. See bridge.py.
Scoring is deliberately simple and printed, so it can be argued with and tuned.
"""
import argparse
import datetime as dt
import json
import os
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import bridge  # noqa: E402  (GitHub bridge for the cloud seats)
import cockpit  # noqa: E402  (shares the xanadu transport and order fold)
import cockpit_feed  # noqa: E402  (REPOS)
import gates  # noqa: E402  (the merge gate before judgement)

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
BASE = {'rig': 60, 'merge': 70, 'fix': 55, 'review': 40, 'triage': 35, 'reply': 30, 'decision': 50}   # impact by kind


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
    if kind in ('decision', 'merge', 'triage'):
        return 0                                   # Keath's call (merges need his OK), never an agent's
    if kind == 'fix':
        return 5 if where == s['agent'].lower() else 0   # the author addresses review feedback
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


def pr_refs_in_hand(lines):
    """PRs a seat already holds an open order for, however it was posted (Keath's orders carry no ref, only text)."""
    held = set()
    for o in cockpit.fold_orders_all(lines):
        if o['status'] in ('posted', 'taken', 'working') and (o['by'] or o['to']) in SEATS:
            held.add(o.get('url') or '')
            held.update(m.lower() for m in re.findall(r'[\w.-]+#\d+', o.get('text', '')))
    held.discard('')
    return held


def candidates(b, lines):
    busy = busy_seats(lines)
    ordered = {o.get('ref') for o in cockpit.fold_orders_all(lines) if o['status'] not in ('declined',)}
    in_hand = pr_refs_in_hand(lines)
    out = []
    for item in b.get('actions', []):
        iid = item.get('id') or (item['kind'] + ':' + item.get('url', item['title'])[:120])
        if iid in ordered or item.get('decided'):
            continue
        pr = item.get('pr') or {}
        if pr and (item.get('url') in in_hand or f"{pr.get('repo')}#{pr.get('number')}".lower() in in_hand):
            continue                               # a seat already has this PR in hand
        human = blocked_on_human(item, b)
        if human:
            item = dict(item, kind='decision', title=item['title'] + f'  [needs Keath: {human}]')
        fits = sorted(((fit(s, item), s) for s in SEATS), reverse=True)
        fits = [(f, s) for f, s in fits if f > 0]
        out.append({'id': iid, 'item': item, 'yield': yield_of(item), 'fits': fits,
                    'free': [s for f, s in fits if s not in busy]})
    return sorted(out, key=lambda c: (-c['yield'], c['item'].get('title', ''))), busy


def workflow(item):
    """The planned workflow for an item: who, what, where, when, why, and how (numbered steps), ready to execute."""
    kind, url, pr = item.get('kind'), item.get('url', ''), item.get('pr') or {}
    repo = gates.full_repo(pr.get('repo'), cockpit_feed.REPOS) if pr else ''
    owner = f"{repo}#{pr.get('number')}" if pr else '<owner/repo#N>'
    steps = {
        'review': [f"gh pr checkout {pr.get('number')} -R {repo} (or read the diff at {url})",
                   'run its tests and any gsv verify; red-control them against main where the PR adds tests',
                   f"write findings; verdict approve or request-changes, bound to head {pr.get('head', '<sha>')}",
                   f"python tools/gsv/gsv.py review post {owner} --as <your actor> --verdict <v> --head <full sha> --body-file <file>",
                   'python tools/holomind/cockpit.py status <order> done --as <seat> --link <review url>'],
        'fix': [f"read the requested changes on {url}", 'make the changes on the same branch, with a test for each',
                'push; the PR returns to needs-review automatically (review on an older head = stale)', 'post the receipt'],
        'merge': [f"confirm CI is {pr.get('ci')} and the approval is at head {pr.get('head')}",
                  f"python tools/gsv/gsv.py merge {owner} --dry-run, then without --dry-run (checks CI, provenance, a different-actor review)",
                  'Keath approves the merge in the Workbench'],
        'rig': ['measure: heartbeat checks + the doctor verdict', 'fix in your own lane (CHORUS /act allowlist for MSI containers)',
                'verify the check is green on the next heartbeat', 'post the receipt'],
        'triage': ['list drafts older than 3 days by repo and author', 'for each: finish (mark ready), hand off, or close with a note',
                   'Keath decides closes; agents can mark their own ready'],
        'reply': ['answer in the channel: python tools/holomind/cockpit.py say "..." --as <seat> --to <asker>'],
        'decision': ['Keath: Approve or Decline in the Workbench (or Ctrl+K); the owning seat executes and posts the receipt'],
    }.get(kind, ['see the item'])
    return {'who': item.get('where'), 'what': item.get('title'), 'where': url or item.get('where'),
            'when': f"open {pr.get('age_h')} h" if pr else 'now', 'why': pr.get('why') or kind, 'how': steps}


def how_to_start(item):
    kind, url = item.get('kind'), item.get('url', '')
    if kind == 'review':
        return f"read the diff and run its tests, then: python tools/gsv/gsv.py review post <owner/repo#N> --as agent/claude-code --verdict approve|request-changes --head <sha> --body-file <file>   ({url})"
    if kind == 'rig':
        return 'measure first (heartbeat checks, doctor), fix in your own lane, and post the receipt'
    if kind == 'reply':
        return 'answer in the channel: python cockpit.py say "..." --as <seat> --to <asker>'
    return 'see the item'


CLOUD = {s for s, v in SEATS.items() if v['home'] == 'cloud'}
STATE = pathlib.Path(os.environ.get('COLONY_DISPATCH_STATE', r'C:\Users\Public\colony\mindview\dispatch.state.json'))
MAX_GATES = 12          # merge-gate dry runs per pass (about 3 s each; cached 15 min)


def ordered_refs(lines):
    return {o.get('ref') for o in cockpit.fold_orders_all(lines) if o['status'] not in ('declined',)}


def make_router(runner, cache, repos):
    """route(item) -> gates.classify verdict for a review item, with the gate's full head and author actor."""
    find = gates.find_pr_for_branch_gh(runner)

    def route(item):
        pr = item['pr']
        repo = gates.full_repo(pr.get('repo'), repos)
        g = gates.run_gate(repo, pr.get('number'), runner=runner, cache=cache)
        r = gates.classify(g, pr, repo, author_agent=pr.get('agent'), find_pr_for_branch=find)
        return dict(r, head=g.get('head', ''), author_actor=g.get('author_actor'), repo=repo)
    return route


def make_plan(cands, busy, ordered, route=None, limit=None, max_gates=MAX_GATES):
    """One order per free seat, best yield first. With `route`, every review goes through the merge gate first:
    only a PR whose sole missing gate is review gets a reviewer; the rest get their mechanical prerequisite."""
    taken, plan, held, gated = set(busy), [], [], 0
    for c in cands:
        if (limit and len(plan) >= limit) or len(taken) >= len(SEATS):
            break
        item = c['item']
        options = [c]
        if route and item.get('kind') == 'review' and item.get('pr'):
            if gated >= max_gates:
                held.append((c, 'gate budget for this pass spent'))
                continue
            gated += 1
            r = route(item)
            if r['verdict'] == 'review':
                options = [dict(c, item=dict(item, pr=dict(item['pr'], head=r['head']), repo=r['repo'],
                                             author_actor=r['author_actor'], gate='review-only'))]
            elif r['verdict'] == 'prereq':
                options = []
                for it in r['items']:
                    if it['id'] in ordered:
                        continue
                    if it['to'] not in SEATS:
                        held.append((dict(c, item=it), f"{it['gate']}: no seat can do it (author {item['pr'].get('agent')}): Keath's"))
                        continue
                    options.append({'id': it['id'], 'item': it, 'yield': c['yield'], 'fits': [(9, it['to'])],
                                    'free': [it['to']] if it['to'] not in busy else []})
                held.append((c, f"not a review yet: needs {r['reason']} first"))
            else:
                held.append((c, r['reason']))
                continue
        for o in options:
            if limit and len(plan) >= limit:
                break
            seat = next((s for s in o['free'] if s not in taken), None)
            if seat:
                taken.add(seat)
                plan.append((seat, o))
    return plan, held


def full_head(runner, repo, number, head):
    if len(head or '') == 40:
        return head
    rc, out, _ = runner(['gh', 'pr', 'view', str(number), '-R', repo, '--json', 'headRefOid'])
    try:
        return json.loads(out).get('headRefOid', head) if rc == 0 else head
    except ValueError:
        return head


def order_line(seat, c, now, i):
    it = c['item']
    pr = it.get('pr') or {}
    line = {'at': now.strftime('%Y-%m-%dT%H:%M:%SZ'), 'from': 'dispatcher', 'kind': 'order',
            'id': f"o-{now.strftime('%m%d-%H%M%S')}-d{i}", 'to': seat,
            'station': 'pegs' if it['kind'] == 'review' else 'anvil',
            'text': it['title'] + (f"  {it.get('url')}" if it.get('url') else ''), 'ref': c['id'],
            'url': it.get('url', ''), 'yield': c['yield'], 'via': 'dispatch'}
    if pr:
        line.update(repo=it.get('repo') or pr.get('repo'), number=pr.get('number'), head=pr.get('head', ''))
    if it.get('gate'):
        line['gate'] = it['gate']
    if it.get('author_actor'):
        line['author_actor'] = it['author_actor']
    return line


def bridge_kind(it):
    if it['kind'] == 'review':
        return 'review', ''
    if it['kind'] == 'prereq':
        return ('provenance' if it['gate'] == 'provenance' else 'fix'), it['gate']
    return 'fix', it['kind']


def run(argv, brief_fn=None, lines_fn=None, append_fn=None, runner=None, state_path=None, now=None, out=print):
    """The CLI, with every side effect injectable (tests pass fakes; nothing here needs a network by itself)."""
    a = argparse.ArgumentParser(prog='dispatch.py', description='The colony work queue, scored and matched to the best free agent.')
    sub = a.add_subparsers(dest='cmd', required=True)
    n = sub.add_parser('next'); n.add_argument('--as', dest='who', required=True)
    sub.add_parser('queue')
    for name in ('plan', 'assign'):
        s = sub.add_parser(name)
        s.add_argument('--max', type=int, default=3)
        s.add_argument('--no-gates', action='store_true', help='skip the merge-gate check (old behaviour)')
        if name == 'assign':
            s.add_argument('--bridge', action='store_true', help='also post ONE PR comment for orders to cloud seats (gpt-6, codex, muse)')
    sub.add_parser('reconcile', help='close bridged orders from GitHub (reviews at head), satisfied prerequisites, expired cloud orders')
    args = a.parse_args(argv)
    brief_fn, lines_fn, append_fn = brief_fn or brief, lines_fn or cockpit.all_lines, append_fn or cockpit.append
    runner = runner or gates.default_runner
    state_path = state_path or STATE
    now = now or dt.datetime.now(dt.timezone.utc)
    state = gates.load_state(state_path)
    cache = state.setdefault('gate_cache', {})
    for k in [k for k, v in cache.items() if now.timestamp() - v.get('at', 0) > gates.CACHE_S]:
        del cache[k]
    repos = cockpit_feed.REPOS
    lines = lines_fn()
    try:
        if args.cmd == 'reconcile':
            def gate_fn(repo, num):
                return gates.run_gate(repo, num, runner=runner, cache=cache, now=now.timestamp())
            new = bridge.reconcile(lines, state, runner, now, cockpit.fold_orders_all, CLOUD, gate_fn=gate_fn, log=out)
            for line in new:
                append_fn(line)
            out(f'reconcile: {len(new)} order(s) closed')
            return new
        b = brief_fn()
        cands, busy = candidates(b, lines)
        if args.cmd == 'queue':
            out(f"COLONY QUEUE · {len(cands)} unassigned · busy seats: {', '.join(sorted(busy)) or 'none'}")
            for i, c in enumerate(cands):
                fits = ', '.join(f"{s}({f})" for f, s in c['fits'][:3]) or 'nobody but Keath'
                out(f"{i + 1:>2}. y={c['yield']:>3} [{c['item']['kind']:8}] {c['item']['title'][:90]}\n      fits: {fits}")
            return cands
        if args.cmd == 'next':
            mine = [c for c in cands if any(s == args.who for _, s in c['fits'])]
            if not mine:
                out('nothing in the queue fits you right now')
                return None
            c = mine[0]
            w = workflow(c['item'])
            out(f"NEXT for {args.who}: [{c['item']['kind']}] {c['item']['title']}\n  yield {c['yield']} · your fit {dict((s, f) for f, s in c['fits'])[args.who]}")
            out(f"  who: {w['who']} · where: {w['where']} · when: {w['when']} · why: {w['why']}")
            for i, step in enumerate(w['how'], 1):
                out(f"  {i}. {step}")
            if args.who in busy:
                out('  (you already have an open order: finish that first)')
            return c
        route = None if args.no_gates else make_router(runner, cache, repos)
        plan, held = make_plan(cands, busy, ordered_refs(lines), route=route, limit=args.max if args.cmd == 'assign' else None)
        for seat, c in plan:
            out(f"{seat:18} <- y={c['yield']} [{c['item']['kind']}] {c['item']['title'][:100]}")
        if not plan:
            out('no free seat fits any unassigned item')
        for c, why in held:
            out(f"  held: {c['item']['title'][:70]}  -- {why}")
        if args.cmd == 'plan':
            return plan
        posted = []
        for i, (seat, c) in enumerate(plan[:args.max]):
            line = order_line(seat, c, now, i)
            bridging = args.bridge and seat in CLOUD and line.get('number')
            if bridging:
                line['repo'] = gates.full_repo(line['repo'], repos)
                line['head'] = full_head(runner, line['repo'], line['number'], line.get('head', ''))
            append_fn(line)
            out(f"posted {line['id']} -> {seat}")
            posted.append(line)
            if bridging:
                kind, gate_name = bridge_kind(c['item'])
                try:
                    line['comment'] = bridge.bridge_order(state, line, seat, SEATS[seat]['agent'], kind, line['repo'], line['number'],
                                                          line['head'], runner, gate_name=gate_name, log=out)
                finally:
                    state.pop('_dirty', None)
                    gates.save_state(state_path, state)
        return posted
    finally:
        state.pop('_dirty', None)
        gates.save_state(state_path, state)


def main():
    run(sys.argv[1:])


if __name__ == '__main__':
    main()
