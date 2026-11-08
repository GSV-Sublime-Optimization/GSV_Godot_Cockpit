"""review_ladder: stubbed gh, Ollama and lanes. No network, no model, no real PR is touched."""
import json

import pytest

import review_ladder as rl
from fakes import HEAD_A, gate_json

REPO = 'Furyline/Furyline'
DIFF = ('diff --git a/src/a.gd b/src/a.gd\n--- a/src/a.gd\n+++ b/src/a.gd\n@@ -1 +1 @@\n-x\n+y\n')
BILLING = 'The job was not started because recent account payments have failed or your spending limit needs to be increased.'


class Gh:
    def __init__(self, gate, runs=None, annotations=None, steps=None, comments=None):
        self.gate, self.runs, self.annotations, self.steps = gate, runs or [], annotations or {}, steps
        self.comments = comments if comments is not None else []
        self.calls, self.posted = [], []

    def __call__(self, argv, stdin=None, timeout=120):
        self.calls.append(list(argv))
        if len(argv) > 2 and argv[2] == 'merge':
            return 1, self.gate, ''
        if argv[:2] == ['gh', 'api']:
            p = argv[2]
            if 'check-runs?' in p:
                return 0, json.dumps({'check_runs': self.runs}), ''
            if p.endswith('/annotations'):
                return 0, self.annotations.get(int(p.split('/')[-2]), '[]'), ''
            if '/actions/jobs/' in p:
                return 0, json.dumps({'steps': self.steps if self.steps is not None else [{'n': 1}]}), ''
        if argv[:3] == ['gh', 'pr', 'diff']:
            return 0, DIFF, ''
        if argv[:3] == ['gh', 'pr', 'view']:
            return 0, json.dumps({'comments': [{'body': b} for b in self.comments]}), ''
        if argv[:3] == ['gh', 'pr', 'comment']:
            body = argv[argv.index('--body') + 1]
            self.posted.append(body)
            self.comments.append(body)
            return 0, 'https://github.com/x/y/pull/1#issuecomment-1\n', ''
        raise AssertionError(f'unexpected: {argv}')


@pytest.fixture(autouse=True)
def isolate(tmp_path, monkeypatch):
    monkeypatch.setattr(rl, 'REVIEW_DIR', tmp_path / 'reviews')
    monkeypatch.setattr(rl, 'USAGE_PY', str(tmp_path / 'no_usage.py'))


def never(*a, **k):
    raise AssertionError('a model/lane was called')


def ok_lane(text):
    return lambda repo, n, diff, runner: {'status': 'ok', 'text': text}


APPROVE = 'src/a.gd:1 - nothing\nCHECKED: src/a.gd\nVERDICT: APPROVE - fine'


def go(gh, do_post=False, **kw):
    kw.setdefault('ollama', lambda p: json.dumps({'findings': []}))
    kw.setdefault('gpu', lambda: (lambda: None))
    return rl.run(REPO, 1, do_post=do_post, runner=gh, **kw)


def test_gate_block_stops_before_any_model():
    gh = Gh(gate_json(HEAD_A, prov=False))
    rep = go(gh, ollama=never, lanes={'codex': never, 'copilot': never}, gpu=never)
    assert rep['verdict'] == 'blocked' and rep['stopped_at'] == 'mechanical'
    assert 'provenance' in rep['blocked_on']
    assert not any(c[:3] == ['gh', 'pr', 'diff'] for c in gh.calls)


def test_billing_blocked_check_is_infra_not_failure():
    gate = gate_json(HEAD_A, gsv=False, gsv_detail='gsv/verify is failure at x')
    gh = Gh(gate, runs=[{'id': 7, 'name': 'Godot scene smoke', 'conclusion': 'failure'}],
            annotations={7: json.dumps([{'message': BILLING}])})
    rep = go(gh, lanes={'codex': ok_lane(APPROVE), 'copilot': never})
    assert rep['mechanical']['infra_checks'] == ['Godot scene smoke']
    assert rep['mechanical']['proceed'] and rep['verdict'] == 'ready-for-human'


def test_real_failure_still_blocks():
    gate = gate_json(HEAD_A, gsv=False, gsv_detail='gsv/verify is failure at x')
    gh = Gh(gate, runs=[{'id': 8, 'name': 'tests', 'conclusion': 'failure'}], annotations={8: '[]'})
    rep = go(gh, ollama=never, lanes={'codex': never, 'copilot': never}, gpu=never)
    assert rep['verdict'] == 'blocked' and rep['mechanical']['infra_checks'] == []


def test_zero_step_job_is_infra():
    gate = gate_json(HEAD_A, gsv=False, gsv_detail='gsv/verify is failure at x')
    gh = Gh(gate, runs=[{'id': 9, 'name': 'smoke', 'conclusion': 'failure'}], steps=[])
    assert rl.mechanical(REPO, 1, gh)['infra_checks'] == ['smoke']


def test_hallucinated_file_dropped():
    raw = json.dumps({'findings': [
        {'file': 'src/a.gd', 'line': 1, 'severity': 'high', 'why': 'real'},
        {'file': 'src/ghost.gd', 'line': 3, 'severity': 'high', 'why': 'invented'}]})
    gh = Gh(gate_json(HEAD_A, review=False))
    rep = go(gh, ollama=lambda p: raw, lanes={'codex': ok_lane(APPROVE), 'copilot': never})
    assert [f['file'] for f in rep['local']['findings']] == ['src/a.gd']
    assert rep['local']['dropped'][0]['file'] == 'src/ghost.gd'
    assert rep['verdict'] == 'needs-claude' and any('real' in q for q in rep['questions'])
    assert not any('invented' in q for q in rep['questions'])


def test_unavailable_lanes_and_gpu_handled():
    def busy():
        raise rl.GpuBusy('GPU stayed busy')
    down = lambda repo, n, d, r: {'status': 'unavailable', 'reason': 'copilot doctor failed'}
    quota = lambda repo, n, d, r: {'status': 'unavailable', 'reason': 'quota: usage limit'}
    gh = Gh(gate_json(HEAD_A, review=False))
    rep = go(gh, gpu=busy, ollama=never, lanes={'codex': quota, 'copilot': down})
    assert 'skipped' in rep['local'] and not rep['local']['ran']
    assert rep['second']['lane'] is None and len(rep['second']['attempts']) == 2
    assert rep['verdict'] == 'needs-claude' and 'No independent second reviewer' in rep['questions'][0]


def test_author_family_excluded_from_second_opinion():
    gh = Gh(gate_json(HEAD_A, author='agent/codex', review=False))
    rep = go(gh, lanes={'codex': never, 'copilot': ok_lane(APPROVE)})
    assert rep['second']['lane'] == 'copilot'


def test_no_double_post_and_advisory_labelling():
    gh = Gh(gate_json(HEAD_A, review=False))
    lanes = {'codex': ok_lane(APPROVE), 'copilot': never}
    r1 = go(gh, do_post=True, lanes=lanes)
    r2 = go(gh, do_post=True, lanes=lanes)
    r3 = go(gh, do_post=True, lanes=lanes, force=True)   # re-run, but the marker already on the PR blocks a repost
    assert len(gh.posted) == 1 and r1['post']['posted'] and not r2['post']['posted'] and not r3['post']['posted']
    body = gh.posted[0]
    assert 'Advisory' in body and 'non-binding' in body and 'qwen2.5-coder:14b' in body and 'Codex' in body
    assert 'gsv-review:' not in body and 'verdict=approve' not in body


def test_dry_run_posts_nothing_and_report_saved():
    gh = Gh(gate_json(HEAD_A, review=False))
    rep = go(gh, lanes={'codex': ok_lane(APPROVE), 'copilot': never})
    assert gh.posted == [] and rep['verdict'] == 'ready-for-human'
    assert (rl.REVIEW_DIR / f'Furyline-1-{HEAD_A[:8]}.json').exists()
