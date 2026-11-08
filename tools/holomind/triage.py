r"""triage: a read-only report on every open draft PR across the colony's repos (cockpit_feed.REPOS).

    python triage.py [--out C:\Users\Public\colony\mindview\draft-triage.md] [--stale-days 14]

For each draft: age, CI at its head, last activity, whether its head is already inside another open PR (superseded:
that PR carries every commit this one has), and whether its branch prefix belongs to an agent. Then:

  close-candidates      superseded, or stale (no activity for more than --stale-days)
  mark-ready-candidates CI green at the head and no WIP markers
  keep                  everything else

It only reads (one paginated GraphQL query per repo) and writes the markdown file. It never closes, marks ready,
comments on or changes anything: Keath decides closes; agents may mark their own ready.
"""
import argparse
import datetime as dt
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import cockpit_feed  # noqa: E402  (REPOS, AGENTS)
import gates  # noqa: E402  (default_runner)

OUT = pathlib.Path(r'C:\Users\Public\colony\mindview\draft-triage.md')
QUERY = """query($owner:String!,$name:String!,$cursor:String){repository(owner:$owner,name:$name){pullRequests(states:OPEN,first:50,after:$cursor,orderBy:{field:CREATED_AT,direction:ASC}){pageInfo{hasNextPage endCursor} nodes{number title url isDraft headRefName headRefOid baseRefName createdAt updatedAt labels(first:10){nodes{name}} commits(last:100){nodes{commit{oid}}} tip:commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}}}"""
WIP = re.compile(r'\bwip\b|work in progress|do not merge|don\'t merge|dnm\b|\bdraft\b|\bblocked\b|\bspike\b', re.I)
WIP_LABELS = {'wip', 'do-not-merge', 'do not merge', 'blocked', 'on-hold', 'hold'}


def fetch_open_prs(repo, runner=gates.default_runner):
    """Every open PR in one repo, with the oids of its last 100 commits and its head's CI rollup."""
    owner, name = repo.split('/', 1)
    prs, cursor = [], None
    for _ in range(40):
        argv = ['gh', 'api', 'graphql', '-F', f'owner={owner}', '-F', f'name={name}', '-f', f'query={QUERY}']
        if cursor:
            argv += ['-F', f'cursor={cursor}']
        rc, out, err = runner(argv)
        if rc != 0:
            raise RuntimeError(f'{repo}: {(err or out).strip()[-200:]}')
        page = json.loads(out)['data']['repository']['pullRequests']
        prs += page['nodes']
        if not page['pageInfo']['hasNextPage']:
            break
        cursor = page['pageInfo']['endCursor']
    return prs


def ci_of(pr):
    nodes = (pr.get('tip') or {}).get('nodes') or []
    roll = (nodes[0]['commit'].get('statusCheckRollup') if nodes else None) or {}
    return {'SUCCESS': 'pass', 'FAILURE': 'fail', 'ERROR': 'fail', 'PENDING': 'pending', 'EXPECTED': 'pending'}.get(roll.get('state') or '', 'none')


def classify(repo, prs, now, stale_days=14):
    """Pure: one repo's open PRs (drafts and not) -> a row per draft with its bucket and reasons."""
    commits = {p['number']: {n['commit']['oid'] for n in (p.get('commits') or {}).get('nodes', [])} for p in prs}
    rows = []
    for p in prs:
        if not p.get('isDraft'):
            continue
        head = p['headRefOid']
        # Superseded: another open PR carries this head and more on top of it, or is a ready duplicate of the same head.
        superseded_by = sorted(q['number'] for q in prs if q['number'] != p['number'] and (
            (q['headRefOid'] != head and head in commits[q['number']]) or (q['headRefOid'] == head and not q.get('isDraft'))))
        created = dt.datetime.fromisoformat(p['createdAt'].replace('Z', '+00:00'))
        updated = dt.datetime.fromisoformat(p['updatedAt'].replace('Z', '+00:00'))
        idle_d = (now - updated).total_seconds() / 86400
        labels = {n['name'].lower() for n in (p.get('labels') or {}).get('nodes', [])}
        wip = bool(WIP.search(p.get('title', ''))) or bool(labels & WIP_LABELS)
        agent, _ = cockpit_feed.agent_of(p.get('headRefName', ''))
        ci = ci_of(p)
        reasons = []
        # Keath (2026-11-08): never lose work on big, divergent projects. "Superseded" is only a close-candidate when a
        # superseding PR is READY (not a draft), so the work stays visible in a live review path. Inside a draft
        # umbrella it stays open (bucket keep), so closing the umbrella later can't silently hide a chain of work.
        live = [n for n in superseded_by if not next((q for q in prs if q['number'] == n), {}).get('isDraft', True)]
        if superseded_by and live:
            bucket = 'close'
            reasons.append('superseded: its head is inside ready PR ' + ', '.join(f'#{n}' for n in live) + ' (branch must be kept)')
        elif superseded_by:
            bucket = 'keep'
            reasons.append('contained in DRAFT umbrella ' + ', '.join(f'#{n}' for n in superseded_by) + ': keep open until the umbrella is ready or merged')
        elif idle_d > stale_days and repo.split('/')[-1].lower() == 'furyline':
            bucket = 'keep'
            reasons.append(f'idle {idle_d:.0f} days, but Furyline drafts are never closed for age alone: needs Keath or the author')
        elif idle_d > stale_days:
            bucket = 'close'
            reasons.append(f'stale: no activity for {idle_d:.0f} days')
        elif ci == 'pass' and not wip:
            bucket = 'ready'
            reasons.append('CI green at head, no WIP markers')
        else:
            bucket = 'keep'
            reasons.append(f'CI {ci}' + (', WIP markers' if wip else '') + f', active {idle_d:.0f} d ago')
        rows.append({'repo': repo, 'number': p['number'], 'title': p.get('title', ''), 'url': p.get('url', ''),
                     'branch': p.get('headRefName', ''), 'agent': agent or '', 'ci': ci, 'wip': wip,
                     'age_d': round((now - created).total_seconds() / 86400, 1), 'idle_d': round(idle_d, 1),
                     'superseded_by': superseded_by, 'bucket': bucket, 'reasons': reasons})
    return rows


def render(rows, now, errors=(), stale_days=14):
    buckets = {'close': [], 'ready': [], 'keep': []}
    for r in rows:
        buckets[r['bucket']].append(r)
    agent_n = sum(1 for r in rows if r['agent'])
    out = [f"# Draft PR triage, {now.strftime('%Y-%m-%d %H:%M')} UTC", '',
           f"Read-only report by `tools/holomind/triage.py`: nothing was closed, marked ready or changed. "
           f"Keath decides closes; agents may mark their own drafts ready.", '',
           f"**{len(rows)} open drafts** across {len({r['repo'] for r in rows})} repos: "
           f"**{len(buckets['close'])} close-candidates** "
           f"({sum(1 for r in buckets['close'] if r['superseded_by'])} superseded, "
           f"{sum(1 for r in buckets['close'] if not r['superseded_by'])} stale over {stale_days} days), "
           f"**{len(buckets['ready'])} mark-ready-candidates**, **{len(buckets['keep'])} keep**. "
           f"{agent_n} are on an agent's branch prefix.", '']
    for e in errors:
        out.append(f"> could not read {e}")
    if errors:
        out.append('')
    titles = {'close': 'Close-candidates', 'ready': 'Mark-ready-candidates', 'keep': 'Keep'}
    for key in ('close', 'ready', 'keep'):
        out += [f"## {titles[key]} ({len(buckets[key])})", '']
        if not buckets[key]:
            out += ['(none)', '']
            continue
        for r in sorted(buckets[key], key=lambda r: (r['repo'], -r['idle_d'])):
            title = r['title'].replace('|', '/').replace('[', '(').replace(']', ')')[:90]
            who = r['agent'] or 'no agent prefix'
            out.append(f"- [{r['repo'].split('/')[1]}#{r['number']}]({r['url']}) {title}  \n"
                       f"  {who} · `{r['branch'][:60]}` · age {r['age_d']:.0f} d · idle {r['idle_d']:.0f} d · CI {r['ci']} · {'; '.join(r['reasons'])}")
        out.append('')
    return '\n'.join(out)


def run(argv=None, runner=gates.default_runner, now=None, repos=None, out=print):
    a = argparse.ArgumentParser(description='Read-only triage of every open draft PR in the colony repos.')
    a.add_argument('--out', default=str(OUT))
    a.add_argument('--stale-days', type=int, default=14)
    args = a.parse_args(argv)
    now = now or dt.datetime.now(dt.timezone.utc)
    rows, errors = [], []
    for repo in repos or cockpit_feed.REPOS:
        try:
            rows += classify(repo, fetch_open_prs(repo, runner), now, args.stale_days)
        except (RuntimeError, ValueError, KeyError, TypeError) as exc:
            errors.append(f'{repo}: {str(exc)[:160]}')
    text = render(rows, now, errors, args.stale_days)
    p = pathlib.Path(args.out)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text + '\n', encoding='utf-8')
    counts = {b: sum(1 for r in rows if r['bucket'] == b) for b in ('close', 'ready', 'keep')}
    out(f"draft triage: {len(rows)} drafts -> close {counts['close']}, ready {counts['ready']}, keep {counts['keep']}"
        + (f"; {len(errors)} repo(s) unreadable" if errors else '') + f"  ({p})")
    return rows, errors


if __name__ == '__main__':
    run()
