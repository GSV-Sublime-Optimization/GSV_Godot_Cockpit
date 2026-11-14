r"""gates: run the merge gate before anyone spends judgement on a PR.

An LLM review is the colony's most expensive step. A PR that is a draft, stacked, unverified or missing its
provenance block can't merge whatever a reviewer says, so it gets the mechanical prerequisite instead:

    pr fails        -> draft: "mark ready" (the author);  stacked on Y: "merge Y first" (Keath; held, never an agent's)
    gsv missing     -> "run gsv_ci verify on head X" (a seat that can: the MSI for dev (PowerShell 7), and Furyline (its scene smoke hangs on the i3))
    gsv red         -> the author fixes it
    provenance      -> "add the KILOCORE-PROVENANCE-V1 block" (the author's seat)
    only review     -> a reviewer
    everything ok   -> it's a merge: Keath's

The gate is `gsv.py merge <owner/repo#N> --dry-run --json` (C:\dev\active\dev\tools\gsv), cached 15 minutes per PR.
Every subprocess goes through an injectable `runner(argv) -> (rc, stdout, stderr)`, so tests never touch a network.
"""
import json
import os
import pathlib
import re
import subprocess
import sys
import time

GSV = os.environ.get('COLONY_GSV', r'C:\dev\active\dev\tools\gsv\gsv.py')
CACHE_S = 15 * 60
CLOUD_ACTORS = {'gpt-6': 'agent/chatgpt-gpt6', 'codex': 'agent/codex', 'muse': 'agent/muse'}
ACTOR_SEAT = {v: k for k, v in CLOUD_ACTORS.items()}
AGENT_SEAT = {'GPT-6': 'gpt-6', 'Codex': 'codex', 'Muse': 'muse',          # cockpit_feed.AGENTS name -> dispatch seat
              'Claude (i3 seat)': 'claude (i3 seat)', 'Claude CLI': 'claude (msi seat)'}
# gsv_ci.py needs PowerShell 7 for the dev repo, which the i3 lacks. Furyline's 'Godot scene smoke checks' hang on the i3 (measured 2026-11-08: static checks and the Godot test runner pass, the smoke step never finishes in 15 min), so the MSI verifies both.
VERIFY_SEAT = {'GSV-Sublime-Optimization/dev': 'claude (msi seat)', 'Furyline/Furyline': 'claude (msi seat)'}
VERIFY_DEFAULT = 'claude (msi seat)'
# Exactly gsv_review.MARKER: a review counts only when the comment STARTS with the marker.
MARKER = re.compile(r"\A\s*<!--\s*gsv-review:\s*actor=(?P<actor>[A-Za-z0-9._/-]+)\s+"
                    r"verdict=(?P<verdict>approve|request-changes|comment)\s+head=(?P<head>[0-9a-f]{40})\s*-->")


def default_runner(argv, stdin=None, timeout=120):
    try:
        r = subprocess.run(argv, input=stdin, capture_output=True, text=True, encoding='utf-8', errors='replace',
                           timeout=timeout, stdin=None if stdin is not None else subprocess.DEVNULL,
                           creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        return r.returncode, r.stdout, r.stderr
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 127, '', str(exc)


def full_repo(short, repos):
    """'dev' -> 'GSV-Sublime-Optimization/dev', using the feeder's REPOS list."""
    if '/' in str(short):
        return short
    return next((r for r in repos if r.split('/')[1].lower() == str(short).lower()), f'GSV-Sublime-Optimization/{short}')


def parse_gate(out):
    """The JSON object gsv merge --json prints before its VERDICT line."""
    start, end = out.find('{'), out.rfind('}')
    if start < 0 or end < 0:
        return None
    try:
        d = json.loads(out[start:end + 1])
    except ValueError:
        return None
    return {'ok': bool(d.get('ok')), 'head': d.get('head') or '', 'author_actor': d.get('author_actor'),
            'checks': {c['name']: {'ok': bool(c.get('ok')), 'detail': str(c.get('detail', ''))} for c in d.get('checks', [])}}


def run_gate(repo, number, runner=default_runner, cache=None, now=None, fresh=False):
    """The merge gate's dry run for one PR, cached CACHE_S seconds in `cache` (a dict persisted by the caller)."""
    now = time.time() if now is None else now
    key = f'{repo}#{number}'
    hit = (cache or {}).get(key)
    if hit and not fresh and now - hit.get('at', 0) < CACHE_S:
        return hit
    rc, out, err = runner([sys.executable, GSV, 'merge', key, '--dry-run', '--json'])
    g = parse_gate(out or '')
    if g is None:
        g = {'error': (err or out or f'rc={rc}').strip()[-240:]}
    g['at'] = now
    if cache is not None:
        cache[key] = g
    return g


def stacked_base(detail):
    m = re.search(r'stacked on (\S+), not', detail)
    return m.group(1) if m else ''


def classify(gate, pr, repo, author_agent=None, find_pr_for_branch=None):
    """What a review candidate really needs. Returns {'verdict': review|prereq|hold|mergeable|error, 'reason', 'items'}.
    `items` are prerequisite work items: {kind:'prereq', gate, to, id, title, url, pr, repo}."""
    if gate.get('error'):
        return {'verdict': 'error', 'reason': 'merge gate did not answer: ' + gate['error'][:160], 'items': []}
    if gate.get('ok'):
        return {'verdict': 'mergeable', 'reason': 'every gate passes: a merge for Keath, not a review', 'items': []}
    c = gate['checks']
    head = gate.get('head') or pr.get('head', '')
    number = pr.get('number')
    ref = f'{repo}#{number}'
    author_seat = AGENT_SEAT.get(author_agent or pr.get('agent') or '')
    base = {'url': pr.get('url', ''), 'pr': dict(pr, head=head), 'repo': repo, 'kind': 'prereq'}

    def item(gate_name, to, title):
        return dict(base, gate=gate_name, to=to or 'keath', where=to or 'keath', title=title,
                    id=f'prereq:{gate_name}:{ref}@{head[:12]}')

    pr_check = c.get('pr', {'ok': True})
    if not pr_check['ok']:
        d = pr_check['detail']
        if 'draft' in d:
            return {'verdict': 'prereq', 'reason': 'draft', 'items': [item('ready', author_seat, f'{ref}: mark ready (gh pr ready {number} -R {repo}) once it is finished')]}
        if 'stacked' in d:
            branch = stacked_base(d)
            y = find_pr_for_branch(repo, branch) if (find_pr_for_branch and branch) else None
            if y:
                return {'verdict': 'hold', 'reason': f'stacked on {repo}#{y}: merge #{y} first', 'items': []}
            return {'verdict': 'prereq', 'reason': f'stacked on {branch}, which has no open PR',
                    'items': [item('retarget', author_seat, f'{ref} is stacked on {branch}, which has no open PR: retarget it to the default branch (gh pr edit {number} -R {repo} --base <default>)')]}
        return {'verdict': 'hold', 'reason': d, 'items': []}
    items = []
    g = c.get('gsv', {'ok': True})
    if not g['ok']:
        d = g['detail']
        if d.startswith('no '):
            seat = VERIFY_SEAT.get(repo, VERIFY_DEFAULT)
            items.append(item('verify', seat, f'{ref}: run gsv_ci verify on head {head[:12]}: python tools/gsv/gsv_ci.py once --repo {repo} --pr {number}'))
        elif ' is failure ' in d or ' is error ' in d:
            items.append(item('gsv-red', author_seat, f'{ref}: gsv verify is red at {head[:12]}: fix it ({d[:100]})'))
        else:
            return {'verdict': 'hold', 'reason': 'gsv: ' + d[:140], 'items': []}
    p = c.get('provenance', {'ok': True})
    if not p['ok']:
        items.append(item('provenance', author_seat, f'{ref}: add the KILOCORE-PROVENANCE-V1 block to the PR description ({p["detail"][:80]})'))
    if items:
        return {'verdict': 'prereq', 'reason': ', '.join(i['gate'] for i in items), 'items': items}
    r = c.get('review', {'ok': True})
    if not r['ok'] and 'request-changes' in r['detail']:
        return {'verdict': 'hold', 'reason': 'changes requested at this head: the author fixes first', 'items': []}
    return {'verdict': 'review', 'reason': 'only review is missing', 'items': []}


def find_pr_for_branch_gh(runner=default_runner):
    def find(repo, branch):
        rc, out, _ = runner(['gh', 'pr', 'list', '-R', repo, '--head', branch, '--state', 'open', '--json', 'number'])
        try:
            prs = json.loads(out or '[]')
        except ValueError:
            return None
        return prs[0]['number'] if rc == 0 and prs else None
    return find


def reviews_at(comments, head, exclude_actor=None):
    """gsv review markers at exactly `head`, from anyone but `exclude_actor`, latest last."""
    out = []
    for cm in comments or []:
        m = MARKER.match(str(cm.get('body') or ''))
        if m and m['head'] == head and m['actor'] != exclude_actor:
            out.append({'actor': m['actor'], 'verdict': m['verdict'], 'url': cm.get('url', ''), 'at': cm.get('createdAt', '')})
    return sorted(out, key=lambda r: r['at'])


def load_state(path):
    try:
        return json.loads(pathlib.Path(path).read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {}


def save_state(path, state):
    p = pathlib.Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix('.tmp')
    tmp.write_text(json.dumps(state, indent=1, ensure_ascii=False), encoding='utf-8')
    tmp.replace(p)
