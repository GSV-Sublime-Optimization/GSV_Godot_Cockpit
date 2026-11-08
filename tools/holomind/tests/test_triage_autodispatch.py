"""triage.py (read-only draft report) and autodispatch.py (one safe unattended pass). Fakes only."""
import datetime as dt
import json

import autodispatch
import triage
from fakes import HEAD_A, HEAD_B, HEAD_C, NOW, Channel, FakeGitHub, brief, gate_json, marker, order, review_item, status

DEV = 'GSV-Sublime-Optimization/dev'


def node(number, head, draft=True, branch='codex/x', updated_days=1, created_days=5, ci='SUCCESS', title='a change', commits=(), labels=()):
    return {'number': number, 'title': title, 'url': f'https://github.com/{DEV}/pull/{number}', 'isDraft': draft, 'headRefName': branch,
            'headRefOid': head, 'baseRefName': 'main',
            'createdAt': (NOW - dt.timedelta(days=created_days)).strftime('%Y-%m-%dT%H:%M:%SZ'),
            'updatedAt': (NOW - dt.timedelta(days=updated_days)).strftime('%Y-%m-%dT%H:%M:%SZ'),
            'labels': {'nodes': [{'name': x} for x in labels]},
            'commits': {'nodes': [{'commit': {'oid': o}} for o in list(commits) + [head]]},
            'tip': {'nodes': [{'commit': {'statusCheckRollup': {'state': ci} if ci else None}}]}}


def test_classify_buckets_drafts():
    prs = [node(1, HEAD_A, branch='codex/one'),                                   # head inside #3: superseded
           node(2, HEAD_B, branch='feature/two', updated_days=20),                # stale
           node(3, HEAD_C, draft=False, commits=[HEAD_A]),                        # not a draft: not in the report
           node(4, 'd' * 40, branch='gpt6/four', ci='SUCCESS'),                   # green, no WIP: ready
           node(5, 'e' * 40, title='WIP: half done', ci='SUCCESS'),               # WIP: keep
           node(6, 'f' * 40, ci='FAILURE'),                                       # red: keep
           node(7, '1' * 40, labels=['do-not-merge'], ci='SUCCESS')]              # WIP label: keep
    rows = {r['number']: r for r in triage.classify(DEV, prs, NOW)}
    assert set(rows) == {1, 2, 4, 5, 6, 7}
    assert rows[1]['bucket'] == 'close' and rows[1]['superseded_by'] == [3]
    assert rows[2]['bucket'] == 'close' and 'stale' in rows[2]['reasons'][0]
    assert rows[4]['bucket'] == 'ready' and rows[4]['agent'] == 'GPT-6'
    assert [rows[n]['bucket'] for n in (5, 6, 7)] == ['keep', 'keep', 'keep']
    assert rows[1]['agent'] == 'Codex' and rows[2]['agent'] == ''


def test_a_ready_duplicate_of_the_same_head_supersedes_a_draft():
    rows = triage.classify(DEV, [node(1, HEAD_A), node(2, HEAD_A, draft=False)], NOW)
    assert rows[0]['superseded_by'] == [2]


class GraphQL:
    def __init__(self, pages):
        self.pages, self.calls = pages, []

    def __call__(self, argv, stdin=None, timeout=120):
        self.calls.append(argv)
        assert argv[:3] == ['gh', 'api', 'graphql'], 'triage must only read'
        page = self.pages[len(self.calls) - 1]
        return 0, json.dumps({'data': {'repository': {'pullRequests': page}}}), ''


def test_fetch_paginates_and_run_writes_only_the_report(tmp_path):
    pages = [{'pageInfo': {'hasNextPage': True, 'endCursor': 'C1'}, 'nodes': [node(1, HEAD_A)]},
             {'pageInfo': {'hasNextPage': False, 'endCursor': 'C2'}, 'nodes': [node(2, HEAD_B, updated_days=30)]}]
    gq = GraphQL(pages)
    out = tmp_path / 'draft-triage.md'
    rows, errors = triage.run(['--out', str(out)], runner=gq, now=NOW, repos=[DEV], out=lambda s: None)
    assert len(gq.calls) == 2 and gq.calls[1][-1] == 'cursor=C1'
    assert errors == [] and len(rows) == 2
    text = out.read_text(encoding='utf-8')
    assert '2 open drafts' in text and '## Close-candidates (1)' in text and '## Mark-ready-candidates (1)' in text
    assert 'nothing was closed' in text


def test_an_unreadable_repo_is_named_not_hidden(tmp_path):
    def broken(argv, stdin=None, timeout=120):
        return 1, '', 'HTTP 404'
    rows, errors = triage.run(['--out', str(tmp_path / 't.md')], runner=broken, now=NOW, repos=[DEV], out=lambda s: None)
    assert rows == [] and 'HTTP 404' in errors[0]
    assert 'could not read' in (tmp_path / 't.md').read_text(encoding='utf-8')


# --- autodispatch -------------------------------------------------------------------------------------------------

def io(tmp_path, b, ch, gh, now=NOW):
    return dict(brief_fn=lambda: b, lines_fn=ch.all, append_fn=ch.append, runner=gh, state_path=tmp_path / 'dispatch.state.json', now=now)


def test_autodispatch_reconciles_then_assigns_and_is_safe_to_repeat(tmp_path):
    # A 7 h-old dispatcher order to gpt-6 that gpt-6 never saw; a review-ready PR; a local seat busy.
    b = brief(review_item('dev', 7, agent='Claude CLI', title='feat(studio): entity'),
              {'kind': 'decision', 'where': 'keath', 'title': 'xanadu card 01'})
    ch = Channel([order('o-stale', 'gpt-6', '2026-11-08T10:36:39Z', ref='review:gone'),
                  order('o-a', 'claude (i3 seat)', '2026-11-08T17:00:00Z', frm='keath'), status('o-a', 'taken', 'claude (i3 seat)'),
                  order('o-b', 'claude (msi seat)', '2026-11-08T17:00:00Z', frm='keath'), status('o-b', 'taken', 'claude (msi seat)')])
    gh = FakeGitHub(gates={f'{DEV}#7': gate_json(HEAD_A)})
    log = []
    r = autodispatch.run([], out=log.append, **io(tmp_path, b, ch, gh))
    assert [c['id'] for c in r['closed']] == ['o-stale']
    (posted,) = r['posted']
    assert posted['to'] == 'gpt-6' and len(gh.comments) == 1
    assert not any(line.get('to') == 'keath' or 'xanadu card' in line.get('text', '') for line in ch.lines if line.get('kind') == 'order')
    # Again: every seat that fits is busy, the order is bridged: nothing new anywhere.
    n_lines = len(ch.lines)
    r2 = autodispatch.run([], out=log.append, **io(tmp_path, b, ch, gh, now=NOW.replace(minute=30)))
    assert r2['closed'] == [] and r2['posted'] == [] and len(gh.comments) == 1 and len(ch.lines) == n_lines
    # The reviewer posts at the head; the next pass closes the order from GitHub.
    gh.prs[f'{DEV}#7'] = {'state': 'OPEN', 'headRefOid': HEAD_A, 'url': 'u', 'comments': [
        {'body': marker('agent/chatgpt-gpt6', 'approve', HEAD_A), 'url': 'https://github.com/x/pull/7#issuecomment-9', 'createdAt': 'z'}]}
    r3 = autodispatch.run([], out=log.append, **io(tmp_path, b, ch, gh, now=NOW.replace(hour=19)))
    (done,) = r3['closed']
    assert done['id'] == posted['id'] and done['status'] == 'done' and done['from'] == 'gpt-6'
    assert len(gh.comments) == 1


def test_autodispatch_dry_run_changes_nothing(tmp_path):
    b = brief(review_item('dev', 7, title='feat(studio): entity'))
    ch = Channel([order('o-stale', 'gpt-6', '2026-11-08T10:36:39Z')])
    gh = FakeGitHub(gates={f'{DEV}#7': gate_json(HEAD_A)})
    r = autodispatch.run(['--dry-run'], out=lambda s: None, **io(tmp_path, b, ch, gh))
    assert len(ch.lines) == 1 and gh.writes() == [] and r['plan']


def test_autodispatch_stops_when_github_refuses_the_comment(tmp_path):
    b = brief(review_item('dev', 7, title='feat(studio): entity'))
    ch = Channel([order('o-a', 'claude (i3 seat)', 'x', frm='k'), status('o-a', 'taken', 'claude (i3 seat)'),
                  order('o-b', 'claude (msi seat)', 'x', frm='k'), status('o-b', 'taken', 'claude (msi seat)')])
    gh = FakeGitHub(gates={f'{DEV}#7': gate_json(HEAD_A)}, refuse_comment=True)
    log = []
    r = autodispatch.run([], out=log.append, **io(tmp_path, b, ch, gh))
    assert 'refused' in r and any('STOPPED' in s for s in log)


def test_autodispatch_skips_while_another_pass_holds_the_lock(tmp_path):
    (tmp_path / 'dispatch.state.lock').write_text('123')
    r = autodispatch.run([], out=lambda s: None, **io(tmp_path, brief(), Channel(), FakeGitHub()))
    assert r == {'skipped': True}
