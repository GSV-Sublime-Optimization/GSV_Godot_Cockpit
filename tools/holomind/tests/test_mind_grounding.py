"""What the i3 Mind may claim (mind.py) and how the worker applies it. Cases come from the 2026-11-08 channel."""
import mind
import mind_worker

T = '2099-01-01T00:00:00Z'
PIPELINE = [{'repo': 'Dev-Mentor', 'number': 293, 'title': 'fix(arcs)', 'stage': 'needs-review', 'ci': 'pass', 'reviewers': []}]
FEED = {'screen': 'rotation waiting', 'pipeline': PIPELINE, 'bodies': {}, 'colony': {'backup': None}, 'events': [], 'orders': []}


def test_rejects_the_false_merge_claim():
    out, problems = mind.check_reply('The Dev-Mentor PR #293 has been merged.', FEED, 'Dev-Mentor PR #293?')
    assert problems
    assert 'has been merged' not in out
    assert 'Dev-Mentor#293: OPEN (not merged)' in out


def test_merged_claim_for_unlisted_pr_is_unknown():
    out, problems = mind.check_reply('Kilo_Core#692 was merged.', FEED, 'is Kilo_Core#692 in?')
    assert problems and 'UNKNOWN' in out


def test_negated_claim_passes():
    ok = 'Dev-Mentor#293 is open and not merged [source: pipeline].'
    assert mind.check_reply(ok, FEED, '')[0] == ok


def test_rate_limit_gap_and_window():
    sent = mind.note_sent([], 0)
    assert not mind.may_send(sent, 10)
    for k in range(1, mind.WINDOW_MAX):
        sent = mind.note_sent(sent, k * mind.MIN_GAP_S)
    assert not mind.may_send(sent, mind.WINDOW_MAX * mind.MIN_GAP_S)
    assert mind.may_send(sent, mind.WINDOW_S + mind.WINDOW_MAX * mind.MIN_GAP_S)


def channel(monkeypatch, lines, fail_after=None):
    out = []

    def append(line):
        if fail_after is not None and len(out) >= fail_after:
            raise SystemExit('cockpit: xanadu unreachable')
        out.append(line)
        return line
    monkeypatch.setattr(mind_worker.cockpit, 'all_lines', lambda: lines)
    monkeypatch.setattr(mind_worker.cockpit, 'append', append)
    monkeypatch.setattr(mind_worker, 'feed', lambda: FEED)
    monkeypatch.setattr(mind_worker, 'gpu_busy', lambda: False)
    monkeypatch.setattr(mind_worker, 'tool_facts', lambda text, asker: [])
    monkeypatch.setattr(mind_worker, 'log', lambda text: None)
    return out


def q(text, sec=0):
    return {'at': T, 'from': f'keath{sec}', 'to': 'mind', 'text': text}


def test_worker_replaces_false_merge_before_posting(monkeypatch):
    out = channel(monkeypatch, [q('Dev-Mentor#293 state?')])
    monkeypatch.setattr(mind_worker, 'llm', lambda q, f: 'Dev-Mentor#293 has been merged.')
    assert mind_worker.step({}, clock=lambda: 1000.0) == 1
    assert 'OPEN (not merged)' in out[0]['text']


def test_worker_speaks_once_per_gap_and_answers_the_rest_later(monkeypatch):
    out = channel(monkeypatch, [q('one?', 1), q('two?', 2)])
    monkeypatch.setattr(mind_worker, 'llm', lambda q, f: 'An answer.')
    state = {}
    assert mind_worker.step(state, clock=lambda: 1000.0) == 1
    assert mind_worker.step(state, clock=lambda: 1001.0) == 0
    assert mind_worker.step(state, clock=lambda: 1000.0 + mind.MIN_GAP_S) == 1
    assert [m['to'] for m in out] == ['keath1', 'keath2']


def test_order_needing_hands_is_declined_and_issues_no_new_order(monkeypatch):
    order = {'at': T, 'from': 'keath', 'kind': 'order', 'id': 'o-1', 'to': 'i3-mind', 'text': 'restart mempalace on the MSI'}
    out = channel(monkeypatch, [order])
    assert mind_worker.step({}, clock=lambda: 1000.0) == 1
    assert [m.get('kind') for m in out] == ['order-status', None]
    assert out[0]['status'] == 'declined' and 'claude (msi seat)' in out[0]['note']


def test_failed_write_keeps_what_was_already_sent(monkeypatch):
    out = channel(monkeypatch, [q('one?', 1), q('two?', 2)], fail_after=1)
    monkeypatch.setattr(mind_worker, 'llm', lambda q, f: 'An answer.')
    monkeypatch.setattr(mind, 'may_send', lambda sent, t: True)
    state = {}
    try:
        mind_worker.step(state, clock=lambda: 1000.0)
    except SystemExit:
        pass
    assert len(out) == 1 and len(state['answered']) == 1
