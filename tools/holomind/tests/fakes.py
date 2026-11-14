"""Fakes for the dispatcher tests: a GitHub + gsv merge-gate runner and an in-memory channel. No network anywhere."""
import datetime as dt
import json

NOW = dt.datetime(2026, 11, 8, 18, 0, 0, tzinfo=dt.timezone.utc)
HEAD_A = 'a' * 40
HEAD_B = 'b' * 40
HEAD_C = 'c' * 40


def gate_json(head, author='agent/claude-code', pr=True, gsv=True, prov=True, review=False, pr_detail=None, gsv_detail=None, review_detail=None):
    checks = [
        {'name': 'pr', 'ok': pr, 'detail': pr_detail or ('open, ready, same-repo, base main' if pr else 'PR is a draft: mark it ready first (`gh pr ready`)')},
        {'name': 'gsv', 'ok': gsv, 'detail': gsv_detail or ('gsv/verify=success at x' if gsv else f'no gsv/check or gsv/verify status on {head[:12]}: the local runner has not verified this push')},
        {'name': 'provenance', 'ok': prov, 'detail': f'author actor {author}, principal KiloMusician' if prov else 'missing KILOCORE-PROVENANCE-V1 block'},
        {'name': 'review', 'ok': review, 'detail': review_detail or ('approved' if review else f'no approval from an actor other than {author} at this head')},
    ]
    body = json.dumps({'ok': all(c['ok'] for c in checks), 'head': head, 'author_actor': author if prov else None, 'checks': checks, 'warnings': []}, indent=2)
    return body + '\nVERDICT: ' + ('MERGEABLE' if all(c['ok'] for c in checks) else 'REFUSED') + ' (dry run)\n'


class FakeGitHub:
    """runner(argv) -> (rc, out, err). gates: {'owner/repo#N': gate stdout}. prs: {'owner/repo#N': pr view dict}."""

    def __init__(self, gates=None, prs=None, branch_prs=None, refuse_comment=False):
        self.gates = gates or {}
        self.prs = prs or {}
        self.branch_prs = branch_prs or {}
        self.refuse_comment = refuse_comment
        self.calls = []
        self.comments = []

    def __call__(self, argv, stdin=None, timeout=120):
        self.calls.append(list(argv))
        if len(argv) > 2 and argv[2] == 'merge':                     # python gsv.py merge <ref> --dry-run --json
            assert '--dry-run' in argv, 'the dispatcher must only ever dry-run the merge gate'
            out = self.gates.get(argv[3])
            return (1, out, '') if out else (2, '', 'gsv merge: no such PR')
        if argv[:3] == ['gh', 'pr', 'comment']:
            if self.refuse_comment:
                return 1, '', 'HTTP 403: Resource not accessible by integration'
            repo, n = argv[argv.index('-R') + 1], argv[3]
            body = argv[argv.index('--body') + 1]
            url = f'https://github.com/{repo}/pull/{n}#issuecomment-{1000 + len(self.comments)}'
            self.comments.append({'repo': repo, 'number': int(n), 'body': body, 'url': url})
            return 0, url + '\n', ''
        if argv[:3] == ['gh', 'pr', 'view']:
            key = f"{argv[argv.index('-R') + 1]}#{argv[3]}"
            if key not in self.prs:
                return 1, '', 'not found'
            return 0, json.dumps(self.prs[key]), ''
        if argv[:3] == ['gh', 'pr', 'list'] and '--head' in argv:
            key = (argv[argv.index('-R') + 1], argv[argv.index('--head') + 1])
            n = self.branch_prs.get(key)
            return 0, json.dumps([{'number': n}] if n else []), ''
        raise AssertionError(f'unexpected command: {argv}')

    def writes(self):
        return [c for c in self.calls if c[:3] in (['gh', 'pr', 'comment'], ['gh', 'pr', 'close'], ['gh', 'pr', 'ready'],
                                                   ['gh', 'pr', 'merge'], ['gh', 'pr', 'edit'])]


class Channel:
    def __init__(self, lines=None):
        self.lines = list(lines or [])

    def all(self):
        return list(self.lines)

    def append(self, line):
        self.lines.append(dict(line))
        return line


def review_item(repo, number, agent='Claude CLI', head=HEAD_A, ci='pass', title='a change'):
    p = {'repo': repo, 'number': number, 'title': title, 'url': f'https://github.com/x/{repo}/pull/{number}', 'agent': agent,
         'stage': 'needs-review', 'why': 'no second review yet', 'ci': ci, 'head': head[:10], 'reviewers': [], 'age_h': 5.0}
    return {'kind': 'review', 'where': agent, 'url': p['url'], 'pr': p,
            'title': f'{repo}#{number} awaits a second review (CI {ci}): {title}'}


def brief(*actions):
    return {'actions': list(actions), 'colony': {}}


def order(oid, to, at, ref='', frm='dispatcher', **kw):
    return dict({'at': at, 'from': frm, 'kind': 'order', 'id': oid, 'to': to, 'station': 'pegs', 'text': 't', 'ref': ref, 'url': ''}, **kw)


def status(oid, st, frm, at='2026-11-08T17:00:00Z'):
    return {'at': at, 'from': frm, 'kind': 'order-status', 'id': oid, 'status': st}


def marker(actor, verdict, head):
    return f'<!-- gsv-review: actor={actor} verdict={verdict} head={head} -->\n\n## Review\nlooks right'
