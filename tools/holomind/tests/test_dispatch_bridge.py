"""dispatch.py assign with gates and the GitHub bridge, and dispatch.py reconcile. Fakes only."""
import json

import pytest

import bridge
import dispatch
from fakes import HEAD_A, HEAD_B, NOW, Channel, FakeGitHub, brief, gate_json, marker, order, review_item, status

DEV = 'GSV-Sublime-Optimization/dev'
MENTOR = 'GSV-Sublime-Optimization/Dev-Mentor'
LOCAL_BUSY = [order('o-x1', 'claude (i3 seat)', '2026-11-08T17:00:00Z', frm='keath'), status('o-x1', 'taken', 'claude (i3 seat)'),
              order('o-x2', 'claude (msi seat)', '2026-11-08T17:00:00Z', frm='keath'), status('o-x2', 'taken', 'claude (msi seat)')]


def run(argv, b, ch, gh, tmp_path, now=NOW):
    out = []
    res = dispatch.run(argv, brief_fn=lambda: b, lines_fn=ch.all, append_fn=ch.append, runner=gh,
                       state_path=tmp_path / 'dispatch.state.json', now=now, out=out.append)
    return res, out


def test_review_only_pr_gets_a_reviewer_and_unverified_pr_gets_its_prerequisite(tmp_path):
    b = brief(review_item('dev', 1, title='fix(python): tests'), review_item('dev', 2, title='fix(python): more tests'))
    gh = FakeGitHub(gates={f'{DEV}#1': gate_json(HEAD_A), f'{DEV}#2': gate_json(HEAD_B, gsv=False)})
    ch = Channel()
    posted, out = run(['assign', '--max', '3'], b, ch, gh, tmp_path)
    by_ref = {line['ref']: line for line in posted}
    review = by_ref['review:https://github.com/x/dev/pull/1']
    assert review['station'] == 'pegs' and review['head'] == HEAD_A and review['to'] == 'codex'
    prereq = by_ref[f'prereq:verify:{DEV}#2@{HEAD_B[:12]}']
    assert prereq['to'] == 'claude (msi seat)' and prereq['station'] == 'anvil'
    # PR 2 got no reviewer: its only order is the mechanical one.
    assert not any(line['ref'].startswith('review:') and line['number'] == 2 for line in posted)
    assert gh.writes() == []          # no --bridge: nothing posted to GitHub


def test_keath_only_items_never_go_to_agents(tmp_path):
    b = brief({'kind': 'merge', 'where': 'keath', 'title': 'dev#5 is approved: merge it', 'url': 'u5'},
              {'kind': 'decision', 'where': 'keath', 'title': 'xanadu card 01'},
              {'kind': 'triage', 'where': 'keath', 'title': '208 drafts'},
              {'kind': 'rig', 'where': 'i3', 'title': 'i3 is red: docker'})
    b['colony'] = {'doctor': [{'key': 'i3:docker', 'verdict': 'confirmed: VT-x is off in the BIOS'}]}
    posted, _ = run(['assign', '--max', '3', '--bridge'], b, Channel(), FakeGitHub(), tmp_path)
    assert posted == []


def test_one_open_order_per_seat(tmp_path):
    items = [review_item('dev', n, title='fix(python): tests') for n in range(1, 6)]
    gh = FakeGitHub(gates={f'{DEV}#{n}': gate_json(HEAD_A) for n in range(1, 6)})
    ch = Channel([order('o-old', 'codex', '2026-11-08T17:30:00Z'), status('o-old', 'taken', 'codex')])
    posted, _ = run(['assign', '--max', '9'], brief(*items), ch, gh, tmp_path)
    seats = [line['to'] for line in posted]
    assert len(seats) == len(set(seats)) and 'codex' not in seats


def test_bridge_posts_one_plain_comment_for_a_cloud_review(tmp_path):
    b = brief(review_item('dev', 7, agent='Claude CLI', title='fix(python): tests'))
    gh = FakeGitHub(gates={f'{DEV}#7': gate_json(HEAD_A)})
    ch = Channel(LOCAL_BUSY)
    posted, out = run(['assign', '--max', '3', '--bridge'], b, ch, gh, tmp_path)
    (line,) = posted
    assert line['to'] == 'codex'
    (c,) = gh.comments
    assert c['repo'] == DEV and c['number'] == 7
    body = c['body']
    assert '@' not in body                                   # no mentions
    assert 'gsv-review:' not in body                         # never a marker the feeder could count
    assert line['id'] in body and 'Codex' in body
    assert f'python tools/gsv/gsv.py review post {DEV}#7 --as agent/codex' in body and f'--head {HEAD_A}' in body
    assert 'closes automatically' in body
    state = json.loads((tmp_path / 'dispatch.state.json').read_text(encoding='utf-8'))
    assert state['bridged'][line['id']]['comment'] == c['url']
    assert state['bridged'][line['id']]['author_actor'] == 'agent/claude-code'


def test_bridge_never_posts_twice(tmp_path):
    b = brief(review_item('dev', 7, title='fix(python): tests'))
    gh = FakeGitHub(gates={f'{DEV}#7': gate_json(HEAD_A)})
    ch = Channel(LOCAL_BUSY)
    run(['assign', '--bridge'], b, ch, gh, tmp_path)
    run(['assign', '--bridge'], b, ch, gh, tmp_path)        # same seat now busy, same item now ordered
    assert len(gh.comments) == 1
    # Even under a new order id (the first withdrawn), the same PR, head and kind is not re-posted.
    oid = [m for m in ch.lines if m.get('kind') == 'order' and m['to'] == 'codex'][0]['id']
    ch.append(status(oid, 'declined', 'dispatcher'))
    posted, out = run(['assign', '--bridge'], b, ch, gh, tmp_path, now=NOW.replace(minute=30))
    assert posted and posted[0]['id'] != oid
    assert len(gh.comments) == 1 and any('reuses the comment' in o for o in out)


def test_bridge_refused_stops_and_records_nothing(tmp_path):
    b = brief(review_item('dev', 7, title='fix(python): tests'))
    gh = FakeGitHub(gates={f'{DEV}#7': gate_json(HEAD_A)}, refuse_comment=True)
    with pytest.raises(bridge.BridgeRefused):
        run(['assign', '--bridge'], b, Channel(LOCAL_BUSY), gh, tmp_path)
    state = json.loads((tmp_path / 'dispatch.state.json').read_text(encoding='utf-8'))
    assert state.get('bridged') == {}


def test_provenance_prereq_for_a_cloud_author_is_bridged_with_its_own_text(tmp_path):
    b = brief(review_item('dev', 8, agent='GPT-6', title='feat: studio'))
    gh = FakeGitHub(gates={f'{DEV}#8': gate_json(HEAD_A, prov=False)})
    posted, _ = run(['assign', '--bridge'], b, Channel(LOCAL_BUSY), gh, tmp_path)
    (line,) = posted
    assert line['to'] == 'gpt-6' and line['gate'] == 'provenance'
    (c,) = gh.comments
    assert 'KILOCORE-PROVENANCE-V1' in c['body'] and 'review post' not in c['body'] and '@' not in c['body']


def test_local_seat_orders_are_never_bridged(tmp_path):
    b = brief(review_item('dev', 2, title='x'))
    gh = FakeGitHub(gates={f'{DEV}#2': gate_json(HEAD_B, gsv=False)})
    posted, _ = run(['assign', '--bridge'], b, Channel(), gh, tmp_path)
    assert posted[0]['to'] == 'claude (msi seat)' and gh.comments == []


def bridged_state(tmp_path, oid, kind='review', head=HEAD_A, seat='codex', number=7):
    st = {'bridged': {oid: {'pr_key': 'k', 'seat': seat, 'kind': kind, 'gate': '', 'repo': DEV, 'number': number, 'head': head,
                            'author_actor': 'agent/claude-code', 'at': '2026-11-08T17:00:00Z', 'comment': 'c', 'state': 'posted'}}}
    (tmp_path / 'dispatch.state.json').write_text(json.dumps(st), encoding='utf-8')


def test_reconcile_closes_a_bridged_review_from_the_reviewing_seat(tmp_path):
    bridged_state(tmp_path, 'o-1')
    ch = Channel([order('o-1', 'codex', '2026-11-08T17:00:00Z', ref='review:u7')])
    gh = FakeGitHub(prs={f'{DEV}#7': {'state': 'OPEN', 'headRefOid': HEAD_A, 'url': 'u', 'comments': [
        {'body': marker('agent/codex', 'approve', HEAD_A), 'url': 'https://github.com/r/pull/7#issuecomment-5', 'createdAt': '2026-11-08T17:40:00Z'}]}})
    closed, _ = run(['reconcile'], brief(), ch, gh, tmp_path)
    (line,) = closed
    assert line['kind'] == 'order-status' and line['id'] == 'o-1' and line['status'] == 'done'
    assert line['from'] == 'codex' and line['link'].endswith('issuecomment-5')
    assert ch.lines[-1] == line
    assert gh.writes() == []


@pytest.mark.parametrize('comment', [
    marker('agent/codex', 'approve', HEAD_B),                    # an older head
    marker('agent/claude-code', 'approve', HEAD_A),              # the author themself
    'see ' + marker('agent/codex', 'approve', HEAD_A),           # quoted, not a review
])
def test_reconcile_ignores_reviews_that_do_not_count(tmp_path, comment):
    bridged_state(tmp_path, 'o-1')
    ch = Channel([order('o-1', 'codex', '2026-11-08T17:00:00Z')])
    gh = FakeGitHub(prs={f'{DEV}#7': {'state': 'OPEN', 'headRefOid': HEAD_A, 'url': 'u', 'comments': [{'body': comment, 'url': 'x', 'createdAt': '1'}]}})
    closed, _ = run(['reconcile'], brief(), ch, gh, tmp_path)
    assert closed == []


def test_reconcile_declines_a_bridged_order_whose_pr_closed(tmp_path):
    bridged_state(tmp_path, 'o-1')
    ch = Channel([order('o-1', 'codex', '2026-11-08T17:00:00Z')])
    gh = FakeGitHub(prs={f'{DEV}#7': {'state': 'MERGED', 'headRefOid': HEAD_A, 'url': 'u', 'comments': []}})
    (line,), _ = run(['reconcile'], brief(), ch, gh, tmp_path)
    assert line['status'] == 'declined' and line['from'] == 'dispatcher'


def test_reconcile_closes_a_bridged_fix_when_the_head_moves(tmp_path):
    bridged_state(tmp_path, 'o-1', kind='fix')
    ch = Channel([order('o-1', 'codex', '2026-11-08T17:00:00Z')])
    gh = FakeGitHub(prs={f'{DEV}#7': {'state': 'OPEN', 'headRefOid': HEAD_B, 'url': 'u', 'comments': []}})
    (line,), _ = run(['reconcile'], brief(), ch, gh, tmp_path)
    assert line['status'] == 'done' and line['from'] == 'codex'


def test_reconcile_closes_a_channel_prereq_once_the_gate_passes(tmp_path):
    ref = f'prereq:verify:{DEV}#2@{HEAD_B[:12]}'
    ch = Channel([order('o-2', 'claude (msi seat)', '2026-11-08T17:00:00Z', ref=ref)])
    gh = FakeGitHub(gates={f'{DEV}#2': gate_json(HEAD_B)})
    (line,), _ = run(['reconcile'], brief(), ch, gh, tmp_path)
    assert line['id'] == 'o-2' and line['status'] == 'done' and 'verify satisfied' in line['note']


def test_reconcile_withdraws_cloud_orders_nobody_could_see(tmp_path):
    ch = Channel([order('o-old', 'gpt-6', '2026-11-08T10:36:39Z'),          # 7.4 h, untaken, unbridged: withdrawn
                  order('o-new', 'muse', '2026-11-08T15:00:00Z'),           # 3 h: kept
                  order('o-tkn', 'codex', '2026-11-08T08:00:00Z'), status('o-tkn', 'taken', 'codex'),
                  order('o-loc', 'claude (msi seat)', '2026-11-08T08:00:00Z'),
                  order('o-kth', 'muse', '2026-11-08T08:00:00Z', frm='keath')])
    closed, _ = run(['reconcile'], brief(), ch, FakeGitHub(), tmp_path)
    assert [(c['id'], c['status']) for c in closed] == [('o-old', 'declined')]
    # The withdrawn item is back in the queue, and the seat is free for it.
    _, busy = dispatch.candidates(brief(), ch.all())
    assert 'gpt-6' not in busy


def test_a_pr_a_seat_already_holds_is_not_assigned_again(tmp_path):
    # Keath's orders carry no ref, only text naming the PR; the dispatcher must still see the PR is in hand.
    b = brief(review_item('dev', 7, title='fix(python): tests'), review_item('dev', 8, title='fix(python): tests'))
    ch = Channel([order('o-k', 'claude (msi seat)', '2026-11-08T18:15:58Z', frm='keath (chorus)', text='Review dev#7 ("x"): run it')])
    gh = FakeGitHub(gates={f'{DEV}#7': gate_json(HEAD_A), f'{DEV}#8': gate_json(HEAD_A)})
    posted, _ = run(['assign', '--max', '3'], b, ch, gh, tmp_path)
    assert [line['number'] for line in posted] == [8]
    # An order to something that is not a seat (i3-mind is a chat model) does not hold the PR.
    ch2 = Channel([order('o-m', 'i3-mind', '2026-11-08T18:15:58Z', frm='keath (chorus)', text='Review dev#7')])
    posted2, _ = run(['assign', '--max', '1'], brief(review_item('dev', 7, title='fix(python): tests')), ch2, gh, tmp_path / 'b')
    assert [line['number'] for line in posted2] == [7]
