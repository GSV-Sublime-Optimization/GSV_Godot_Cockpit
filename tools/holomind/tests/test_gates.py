"""Gates before judgement: the merge gate's dry run decides whether a PR gets a reviewer or a mechanical prerequisite."""
import gates
from fakes import HEAD_A, HEAD_B, FakeGitHub, gate_json, marker

DEV = 'GSV-Sublime-Optimization/dev'
FURY = 'Furyline/Furyline'


def pr(number=1, agent='Claude CLI'):
    return {'repo': 'dev', 'number': number, 'url': f'https://github.com/{DEV}/pull/{number}', 'agent': agent, 'head': HEAD_A[:10]}


def test_parse_gate_reads_the_json_before_the_verdict_line():
    g = gates.parse_gate(gate_json(HEAD_A, gsv=False))
    assert g['head'] == HEAD_A and g['ok'] is False
    assert g['checks']['gsv']['ok'] is False and g['checks']['provenance']['ok'] is True
    assert gates.parse_gate('gsv merge: boom') is None


def test_run_gate_is_cached_for_15_minutes():
    gh = FakeGitHub(gates={f'{DEV}#1': gate_json(HEAD_A)})
    cache = {}
    gates.run_gate(DEV, 1, runner=gh, cache=cache, now=1000)
    gates.run_gate(DEV, 1, runner=gh, cache=cache, now=1000 + 14 * 60)
    assert len(gh.calls) == 1
    gates.run_gate(DEV, 1, runner=gh, cache=cache, now=1000 + 16 * 60)
    assert len(gh.calls) == 2
    assert gh.calls[0][-3:] == [f'{DEV}#1', '--dry-run', '--json']


def test_gate_error_is_reported_not_guessed():
    g = gates.run_gate(DEV, 9, runner=FakeGitHub(), cache={}, now=0)
    r = gates.classify(g, pr(9), DEV)
    assert r['verdict'] == 'error' and not r['items']


def classify(out, p=None, repo=DEV, **kw):
    return gates.classify(gates.parse_gate(out), p or pr(), repo, **kw)


def test_only_review_missing_gets_a_reviewer():
    r = classify(gate_json(HEAD_A))
    assert r['verdict'] == 'review' and r['items'] == []


def test_all_green_is_a_merge_for_keath_not_a_review():
    assert classify(gate_json(HEAD_A, review=True))['verdict'] == 'mergeable'


def test_unverified_dev_pr_goes_to_the_msi_for_gsv_ci():
    r = classify(gate_json(HEAD_A, gsv=False))
    assert r['verdict'] == 'prereq'
    (it,) = r['items']
    assert it['gate'] == 'verify' and it['to'] == 'claude (msi seat)'
    assert HEAD_A[:12] in it['title'] and f'gsv_ci.py once --repo {DEV} --pr 1' in it['title']
    assert it['id'] == f'prereq:verify:{DEV}#1@{HEAD_A[:12]}'


def test_unverified_furyline_pr_goes_to_the_msi():  # its scene smoke hangs on the i3 (2026-11-08)
    p = dict(pr(), repo='Furyline')
    (it,) = classify(gate_json(HEAD_A, gsv=False), p, FURY)['items']
    assert it['to'] == 'claude (msi seat)'


def test_missing_provenance_goes_to_the_author_agent():
    r = classify(gate_json(HEAD_A, prov=False), pr(agent='GPT-6'))
    (it,) = r['items']
    assert it['gate'] == 'provenance' and it['to'] == 'gpt-6'


def test_unverified_and_no_provenance_gives_both_prerequisites_to_different_seats():
    r = classify(gate_json(HEAD_A, gsv=False, prov=False), pr(agent='Codex'))
    assert [(i['gate'], i['to']) for i in r['items']] == [('verify', 'claude (msi seat)'), ('provenance', 'codex')]


def test_unattributed_author_prerequisite_is_keaths():
    (it,) = classify(gate_json(HEAD_A, prov=False), pr(agent='unattributed'))['items']
    assert it['to'] == 'keath'


def test_draft_needs_mark_ready_from_its_author():
    (it,) = classify(gate_json(HEAD_A, pr=False), pr(agent='Muse'))['items']
    assert it['gate'] == 'ready' and it['to'] == 'muse'


def test_stacked_on_an_open_pr_is_held_merge_that_first():
    out = gate_json(HEAD_A, pr=False, pr_detail='PR is stacked on claude/base-x, not main: merging it would not land it')
    r = classify(out, find_pr_for_branch=lambda repo, branch: 424 if branch == 'claude/base-x' else None)
    assert r['verdict'] == 'hold' and 'merge #424 first' in r['reason'] and not r['items']


def test_stacked_on_a_branch_without_a_pr_needs_a_retarget():
    out = gate_json(HEAD_A, pr=False, pr_detail='PR is stacked on old/branch, not main: merging it would not land it')
    (it,) = classify(out, find_pr_for_branch=lambda repo, branch: None)['items']
    assert it['gate'] == 'retarget'


def test_red_gsv_goes_back_to_the_author():
    out = gate_json(HEAD_A, gsv=False, gsv_detail='gsv/verify is failure on aaaa: 3 tests failed')
    (it,) = classify(out, pr(agent='Codex'))['items']
    assert it['gate'] == 'gsv-red' and it['to'] == 'codex'


def test_pending_gsv_is_held():
    out = gate_json(HEAD_A, gsv=False, gsv_detail='gsv/verify is pending on aaaa: running')
    assert classify(out)['verdict'] == 'hold'


def test_standing_request_changes_is_not_a_review():
    out = gate_json(HEAD_A, review_detail='request-changes is standing at this head from agent/codex; fix and get a new verdict')
    assert classify(out)['verdict'] == 'hold'


def test_reviews_at_counts_only_anchored_markers_at_this_head_from_others():
    comments = [{'body': marker('agent/codex', 'approve', HEAD_A), 'url': 'u1', 'createdAt': '1'},
                {'body': marker('agent/codex', 'approve', HEAD_B), 'url': 'u2', 'createdAt': '2'},
                {'body': marker('agent/claude-code', 'approve', HEAD_A), 'url': 'u3', 'createdAt': '3'},
                {'body': 'quoting: ' + marker('agent/muse', 'approve', HEAD_A), 'url': 'u4', 'createdAt': '4'}]
    revs = gates.reviews_at(comments, HEAD_A, exclude_actor='agent/claude-code')
    assert [r['url'] for r in revs] == ['u1']
