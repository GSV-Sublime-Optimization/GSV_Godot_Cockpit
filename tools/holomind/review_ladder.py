r"""review_ladder: cheap layers first, Claude cloud review last.

    python review_ladder.py <owner/repo> <pr> [--post] [--json] [--force]

Stages, stopping at the first that yields a decision:
  1. mechanical   gates.py (draft, stacked, no verify, no provenance...). Blocked -> report and stop, no model is called.
                  A check whose job never started (billing/spending-limit annotation, or 0 steps) is infrastructure,
                  not a failure.
  2. local        qwen2.5-coder:14b on Ollama over the capped diff, behind a GPU claim. Advisory: findings citing files
                  not in the diff are dropped. Skipped (and said so) when the GPU is busy or Ollama is down.
  3. second       Codex (read-only sandbox) or Copilot, whichever has capacity, never the PR author's family.
  4. verdict      `needs-claude` (with the exact unresolved questions) or `ready-for-human`; JSON report saved under
                  C:\Users\Public\colony\mindview\reviews\<repo>-<pr>-<sha8>.json.

--post adds ONE advisory comment (idempotent per head sha). It is never a gsv-review verdict, approval or merge.
Every subprocess/model call is injectable (`runner`, `ollama`, `lanes`), so tests touch no network.
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import gates  # noqa: E402

REVIEW_DIR = pathlib.Path(os.environ.get('REVIEW_LADDER_DIR', r'C:\Users\Public\colony\mindview\reviews'))
COLONY_DIR = os.environ.get('COLONY_DIR', r'C:\Users\Public\colony')
OLLAMA_HOST = os.environ.get('OLLAMA_HOST', '100.102.251.35:11434')
LOCAL_MODEL = 'qwen2.5-coder:14b'
DIFF_CAP = 60_000
NUM_CTX = 24_576
USAGE_PY = os.environ.get('COLONY_USAGE', r'C:\dev\worktrees\dev-gameattract\tools\colony\usage.py')
COPILOT_PY = os.environ.get('COLONY_COPILOT_REVIEW', r'C:\dev\worktrees\dev-gameattract\tools\colony\lanes\copilot_review.py')
BILLING_PHRASE = 'recent account payments have failed or your spending limit'
QUOTA_RE = re.compile(r'usage limit|rate.?limit|quota|\b429\b|upgrade to|try again (at|in)|not logged in|login required', re.I)
SEVERITIES = ('high', 'medium', 'low')
MARKER = '<!-- review-ladder:advisory head={head} -->'
FAMILIES = {'claude': 'claude', 'codex': 'codex', 'gpt': 'codex', 'chatgpt': 'codex', 'openai': 'codex', 'copilot': 'copilot'}


def family(actor):
    a = str(actor or '').lower()
    return next((v for k, v in FAMILIES.items() if k in a), None)


def runner_default(argv, stdin=None, timeout=120):
    return gates.default_runner(argv, stdin=stdin, timeout=timeout)


# ---------------------------------------------------------------- stage 1
def infra_failures(repo, head, runner):
    """(infra, real): names of failing check runs whose job never started vs. ones that genuinely failed."""
    rc, out, _ = runner(['gh', 'api', f'repos/{repo}/commits/{head}/check-runs?per_page=100'])
    try:
        runs = json.loads(out or '{}').get('check_runs', [])
    except ValueError:
        return [], []
    infra, real = [], []
    for r in runs:
        if r.get('conclusion') not in ('failure', 'timed_out', 'startup_failure', 'action_required'):
            continue
        rc, ann, _ = runner(['gh', 'api', f"repos/{repo}/check-runs/{r['id']}/annotations"])
        never_started = BILLING_PHRASE in (ann or '')
        if not never_started:
            rc, job, _ = runner(['gh', 'api', f"repos/{repo}/actions/jobs/{r['id']}"])
            try:
                never_started = rc == 0 and json.loads(job).get('steps') == []
            except ValueError:
                pass
        (infra if never_started else real).append(r.get('name', '?'))
    return infra, real


def mechanical(repo, number, runner):
    g = gates.run_gate(repo, number, runner=runner, fresh=True)
    pr = {'number': number, 'url': f'https://github.com/{repo}/pull/{number}', 'head': g.get('head', '')}
    cl = gates.classify(g, pr, repo)
    res = {'stage': 'mechanical', 'gate_verdict': cl['verdict'], 'reason': cl['reason'], 'head': g.get('head', ''),
           'author_actor': g.get('author_actor'), 'infra_checks': [], 'items': [i['title'] for i in cl['items']]}
    gsv = (g.get('checks') or {}).get('gsv')
    if cl['verdict'] in ('prereq', 'hold') and gsv and not gsv['ok'] and (' is failure ' in gsv['detail'] or ' is error ' in gsv['detail'] or cl['verdict'] == 'hold'):
        infra, real = infra_failures(repo, g.get('head', ''), runner)
        if infra and not real:   # nothing ran: an infrastructure outage, not a verdict on the code
            g2 = json.loads(json.dumps(g))
            g2['checks']['gsv'] = {'ok': True, 'detail': 'infra: ' + ', '.join(infra)}
            cl = gates.classify(g2, pr, repo)
            res.update(gate_verdict=cl['verdict'], reason=cl['reason'], infra_checks=infra, items=[i['title'] for i in cl['items']])
            res['note'] = 'failing checks never started (billing/spending limit or 0 steps): infrastructure, not code failure'
    res['proceed'] = res['gate_verdict'] == 'review'
    return res


# ---------------------------------------------------------------- diff + local model
def diff_files(diff):
    files = {m for pair in re.findall(r'^diff --git a/(.+?) b/(.+)$', diff, re.M) for m in pair}
    files |= set(re.findall(r'^\+\+\+ b/(.+)$', diff, re.M))
    return files


def get_diff(repo, number, runner):
    rc, out, err = runner(['gh', 'pr', 'diff', str(number), '-R', repo], timeout=180)
    if rc != 0:
        return None, False, (err or 'gh pr diff failed').strip()[:200]
    return out[:DIFF_CAP], len(out) > DIFF_CAP, ''


FINDINGS_SCHEMA = {'type': 'object', 'required': ['findings'], 'properties': {'findings': {'type': 'array', 'items': {
    'type': 'object', 'required': ['file', 'line', 'severity', 'why'],
    'properties': {'file': {'type': 'string'}, 'line': {'type': 'integer'},
                   'severity': {'type': 'string', 'enum': list(SEVERITIES)}, 'why': {'type': 'string'}}}}}}


def local_prompt(diff, truncated):
    note = '\n(The diff was truncated; do not speculate about the missing part.)' if truncated else ''
    return ('You are a careful code reviewer. Review this pull request diff for real bugs, regressions and unsafe changes only. '
            'Cite only files that appear in the diff and the line in the new file. Return JSON {"findings":[{"file","line","severity":"high|medium|low","why"}]}. '
            'Return {"findings":[]} if you see nothing concrete.' + note + '\n\n' + diff)


def ollama_default(prompt):
    body = json.dumps({'model': LOCAL_MODEL, 'stream': False, 'think': False, 'keep_alive': 0, 'format': FINDINGS_SCHEMA,
                       'options': {'num_ctx': NUM_CTX, 'temperature': 0.1},
                       'messages': [{'role': 'user', 'content': prompt}]}).encode()
    req = urllib.request.Request(f'http://{OLLAMA_HOST}/api/chat', data=body, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.loads(r.read())['message']['content']


def validate_findings(raw, files):
    """-> (kept, dropped). Advisory output: anything malformed, or citing a file not in the diff, is dropped."""
    try:
        data = json.loads(raw)
        items = data.get('findings', []) if isinstance(data, dict) else data
    except (ValueError, TypeError, AttributeError):
        return [], [{'why': 'unparseable model output'}]
    kept, dropped = [], []
    for f in items if isinstance(items, list) else []:
        if not isinstance(f, dict):
            continue
        path = str(f.get('file', '')).replace('\\', '/').lstrip('./') if f.get('file') else ''
        sev = str(f.get('severity', '')).lower()
        if path not in files or sev not in SEVERITIES or not str(f.get('why', '')).strip():
            dropped.append({'file': f.get('file'), 'why': 'file not in diff' if path not in files else 'malformed'})
            continue
        try:
            line = int(f.get('line'))
        except (TypeError, ValueError):
            line = 0
        kept.append({'file': path, 'line': line, 'severity': sev, 'why': str(f['why']).strip()[:400]})
    return kept, dropped


class GpuBusy(Exception):
    pass


def gpu_default():
    """Context-ish pair (acquire, release) from gpu_claim.py; raises GpuBusy / ImportError when unavailable."""
    sys.path.insert(0, COLONY_DIR)
    try:
        import gpu_claim  # noqa: E402
    finally:
        if COLONY_DIR in sys.path:
            sys.path.remove(COLONY_DIR)
    if not gpu_claim.wait_gpu_free(timeout=120):
        raise GpuBusy('GPU stayed busy')
    handle = gpu_claim.claim('review_ladder', 'local first-pass review', 900)
    if handle is False:
        raise GpuBusy('GPU claim refused')

    def release():
        for obj, name in ((handle, 'release'), (handle, 'close'), (gpu_claim, 'release')):
            fn = getattr(obj, name, None)
            if callable(fn):
                try:
                    fn() if obj is handle else fn('review_ladder')
                except Exception:
                    pass
                return
    return release


def local_stage(diff, truncated, files, ollama=ollama_default, gpu=gpu_default):
    res = {'stage': 'local', 'model': LOCAL_MODEL, 'ran': False, 'truncated': truncated, 'findings': [], 'dropped': []}
    try:
        release = gpu()
    except ImportError:
        res['skipped'] = 'gpu_claim.py not present: local stage skipped'
        return res
    except Exception as exc:
        res['skipped'] = f'GPU unavailable ({exc}): local stage skipped'
        return res
    try:
        raw = ollama(local_prompt(diff, truncated))
        res['ran'] = True
        res['findings'], res['dropped'] = validate_findings(raw, files)
    except Exception as exc:
        res['skipped'] = f'Ollama call failed ({type(exc).__name__}: {str(exc)[:120]}): local stage skipped'
    finally:
        try:
            release and release()
        except Exception:
            pass
    return res


# ---------------------------------------------------------------- stage 3 lanes
REVIEW_PROMPT = ('You are an independent, read-only code reviewer. Below is the diff of pull request #{pr} of {repo}. '
                 'Report concrete findings as `path:line - problem - why it matters`, most severe first, citing only files in the diff. Do not pad. '
                 'Finish with exactly two lines:\nCHECKED: <files you read>\nVERDICT: <APPROVE | REQUEST_CHANGES | COMMENT> - <one sentence>\n\nDIFF:\n{diff}')


def parse_second(text, files):
    """-> (verdict, findings[{file,line,why}]) from a path:line - problem review; findings citing files outside the diff are dropped."""
    v = re.search(r'^\s*\**VERDICT\**[ \t]*:[ \t]*\**[ \t]*([A-Za-z_]+)', text, re.M | re.I)
    if not v:
        return None, []
    out = []
    for m in re.finditer(r'^\s*[-*]?\s*`?([\w./\\-]+?):(\d+)`?\s*[-:\u2013\u2014]\s*(.+)$', text, re.M):
        path = m.group(1).replace('\\', '/')
        if path in files:
            out.append({'file': path, 'line': int(m.group(2)), 'why': m.group(3).strip()[:400]})
    return v.group(1).upper(), out


def codex_lane(repo, number, diff, runner):
    exe = shutil.which('codex')
    if not exe:
        return {'status': 'unavailable', 'reason': 'codex not installed'}
    tmp = tempfile.mkdtemp(prefix='ladder-codex-')
    outf = os.path.join(tmp, 'last.txt')
    try:
        rc, out, err = runner([exe, 'exec', '-s', 'read-only', '--skip-git-repo-check', '--ephemeral', '-C', tmp, '-o', outf, '-'],
                              stdin=REVIEW_PROMPT.format(pr=number, repo=repo, diff=diff), timeout=900)
        text = ''
        if os.path.exists(outf):
            text = pathlib.Path(outf).read_text(encoding='utf-8', errors='replace')
        text = text or out
        if rc != 0 or not text.strip():
            msg = (err or out or f'rc={rc}')[-200:]
            return {'status': 'unavailable', 'reason': ('quota/login: ' if QUOTA_RE.search(msg) else 'exec failed: ') + msg.strip()}
        return {'status': 'ok', 'text': text}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def copilot_lane(repo, number, diff, runner):
    py = sys.executable
    if not os.path.exists(COPILOT_PY):
        return {'status': 'unavailable', 'reason': 'copilot_review.py not found'}
    rc, out, err = runner([py, COPILOT_PY, 'doctor'], timeout=60)
    if rc != 0:
        return {'status': 'unavailable', 'reason': 'copilot doctor failed (CLI not installed or not logged in)'}
    d = tempfile.mkdtemp(prefix='ladder-copilot-')
    try:
        rc, out, err = runner([py, COPILOT_PY, 'review', '--repo', repo, '--pr', str(number), '--out-dir', d], timeout=1000)
        files = list(pathlib.Path(d).glob('*.md'))
        if rc != 0 or not files:
            msg = (err or out or f'rc={rc}')[-200:]
            return {'status': 'unavailable', 'reason': ('quota: ' if QUOTA_RE.search(msg) else 'review failed: ') + msg.strip()}
        return {'status': 'ok', 'text': files[0].read_text(encoding='utf-8', errors='replace')}
    finally:
        shutil.rmtree(d, ignore_errors=True)


LANE_FUNCS = {'codex': codex_lane, 'copilot': copilot_lane}


def lane_order(author_fam, runner):
    """Lanes to try, best first, excluding the author's family. Uses usage.py route; UNKNOWN still gets a live attempt."""
    cands = [l for l in ('codex', 'copilot') if l != author_fam]
    verdicts = {}
    if os.path.exists(USAGE_PY):
        argv = [sys.executable, USAGE_PY, 'route', '--role', 'review', '--json']
        if author_fam in ('claude', 'codex', 'copilot'):
            argv += ['--author', author_fam]
        rc, out, _ = runner(argv, timeout=60)
        try:
            verdicts = {v['lane']: v['verdict'] for v in json.loads(out).get('lanes', [])}
        except (ValueError, TypeError, KeyError):
            pass
    return [(l, verdicts.get(l, 'UNKNOWN')) for l in cands if verdicts.get(l) != 'NO'], [l for l in cands if verdicts.get(l) == 'NO']


def second_stage(repo, number, diff, files, author_actor, runner, lanes=None):
    lanes = lanes or LANE_FUNCS
    fam = family(author_actor)
    # Claude PRs (the colony default) are never reviewed by Claude; an unknown author is treated as claude.
    fam_eff = fam or 'claude'
    order, no_cap = lane_order(fam_eff, runner)
    res = {'stage': 'second', 'author_family': fam_eff, 'attempts': [], 'lane': None, 'verdict': None, 'findings': []}
    for l in no_cap:
        res['attempts'].append({'lane': l, 'status': 'unavailable', 'reason': 'usage.py route reports no capacity'})
    for lane, cap in order:
        r = lanes[lane](repo, number, diff, runner)
        att = {'lane': lane, 'status': r['status'], 'capacity': cap}
        if r['status'] != 'ok':
            att['reason'] = r.get('reason', '')
            res['attempts'].append(att)
            continue
        verdict, found = parse_second(r['text'], files)
        if verdict is None:
            att.update(status='unavailable', reason='output had no VERDICT line: not treated as a review')
            res['attempts'].append(att)
            continue
        res['attempts'].append(att)
        res.update(lane=lane, verdict=verdict, findings=found, text=r['text'][:4000])
        break
    return res


# ---------------------------------------------------------------- verdict, report, post
def decide(mech, local, second):
    """-> (verdict, unresolved questions)."""
    if mech.get('gate_verdict') == 'mergeable':
        return 'ready-for-human', []
    qs = []
    if second is None or second.get('lane') is None:
        qs.append('No independent second reviewer was available (' + '; '.join(f"{a['lane']}: {a.get('reason', a['status'])}" for a in (second or {}).get('attempts', [])) + '): full review needed.')
    else:
        if second['verdict'] in ('REQUEST_CHANGES',) and not second['findings']:
            qs.append(f"{second['lane']} requested changes without a citable finding: see its verdict text.")
        if second['verdict'] != 'APPROVE':   # an approving reviewer's nits are notes, not blockers
            qs += [f"{f['file']}:{f['line']} - {f['why']} (raised by {second['lane']})" for f in second['findings']]
    for f in (local or {}).get('findings', []):
        if f['severity'] == 'high':
            qs.append(f"{f['file']}:{f['line']} - {f['why']} (local {LOCAL_MODEL}, high, unconfirmed)")
    return ('needs-claude' if qs else 'ready-for-human'), qs


def report_path(repo, number, head):
    return REVIEW_DIR / f"{repo.split('/')[-1]}-{number}-{head[:8]}.json"


def comment_body(rep):
    models = [rep['local']['model']] if rep.get('local', {}).get('ran') else []
    sec = rep.get('second') or {}
    names = {'codex': 'Codex (codex exec, read-only)', 'copilot': 'GitHub Copilot CLI'}
    lines = [MARKER.format(head=rep['head']),
             f"**Advisory pre-review (review ladder, non-binding)** for head `{rep['head'][:12]}`. "
             "This is not a gsv review, an approval, or a merge decision.", '',
             f"Verdict: **{rep['verdict']}**", '']
    if models:
        lines.append(f"- Local first pass: {', '.join(models)} (advisory)")
    elif rep.get('local', {}).get('skipped'):
        lines.append(f"- Local first pass: skipped ({rep['local']['skipped']})")
    if sec.get('lane'):
        lines.append(f"- Second opinion: {names[sec['lane']]}, verdict {sec['verdict']}")
    else:
        lines.append('- Second opinion: none available')
    if rep['questions']:
        lines += ['', 'Unresolved questions for a cloud reviewer:'] + [f'{i}. {q}' for i, q in enumerate(rep['questions'], 1)]
    return '\n'.join(lines) + '\n'


def already_posted(repo, number, head, runner):
    rc, out, _ = runner(['gh', 'pr', 'view', str(number), '-R', repo, '--json', 'comments'])
    try:
        return any(MARKER.format(head=head) in str(c.get('body', '')) for c in json.loads(out or '{}').get('comments', []))
    except ValueError:
        return False


def post(rep, repo, number, runner):
    if rep.get('posted_url') or already_posted(repo, number, rep['head'], runner):
        return {'posted': False, 'why': 'already posted for this head'}
    rc, out, err = runner(['gh', 'pr', 'comment', str(number), '-R', repo, '--body', comment_body(rep)])
    if rc != 0:
        return {'posted': False, 'why': 'gh failed: ' + (err or '')[:160]}
    return {'posted': True, 'url': out.strip()}


def save(rep, repo, number):
    p = report_path(repo, number, rep['head'])
    gates.save_state(p, rep)
    return p


def run(repo, number, do_post=False, force=False, runner=runner_default, ollama=ollama_default, gpu=gpu_default, lanes=None):
    mech = mechanical(repo, number, runner)
    head = mech['head']
    if head:
        p = report_path(repo, number, head)
        if p.exists() and not force and (mech['proceed'] or mech['gate_verdict'] == 'mergeable'):
            rep = gates.load_state(p)
            if rep.get('verdict'):
                rep['cached'] = True
                if do_post:
                    rep['post'] = post(rep, repo, number, runner)
                    if rep['post'].get('posted'):
                        rep['posted_url'] = rep['post']['url']
                        gates.save_state(p, {k: v for k, v in rep.items() if k not in ('cached', 'post')})
                return rep
    rep = {'repo': repo, 'pr': number, 'head': head, 'mechanical': mech}
    if mech['gate_verdict'] == 'mergeable':
        rep.update(stopped_at='mechanical', verdict='ready-for-human', questions=[])
    elif not mech['proceed']:
        rep.update(stopped_at='mechanical', verdict='blocked', questions=[], blocked_on=mech['reason'], items=mech['items'])
    else:
        diff, truncated, err = get_diff(repo, number, runner)
        if diff is None:
            rep.update(stopped_at='diff', verdict='needs-claude', questions=['Could not fetch the diff: ' + err])
        else:
            files = diff_files(diff)
            rep['local'] = local_stage(diff, truncated, files, ollama=ollama, gpu=gpu)
            rep['second'] = second_stage(repo, number, diff, files, mech.get('author_actor'), runner, lanes=lanes)
            rep['diff'] = {'files': sorted(files), 'truncated': truncated}
            rep['verdict'], rep['questions'] = decide(mech, rep['local'], rep['second'])
            rep['stopped_at'] = 'second' if rep['second'].get('lane') else 'verdict'
    if head:
        rep['report'] = str(save(rep, repo, number))
    if do_post and rep['verdict'] != 'blocked' and head:
        rep['post'] = post(rep, repo, number, runner)
        if rep['post'].get('posted'):
            rep['posted_url'] = rep['post']['url']
            gates.save_state(report_path(repo, number, head), {k: v for k, v in rep.items() if k != 'post'})
    return rep


def render(rep):
    m = rep['mechanical']
    out = [f"{rep['repo']}#{rep['pr']} head {rep['head'][:12]}: {rep['verdict'].upper()}" + (' (cached)' if rep.get('cached') else '')]
    out.append(f"  mechanical: {m['gate_verdict']} - {m['reason']}" + (f"; infra checks: {', '.join(m['infra_checks'])}" if m['infra_checks'] else ''))
    for i in rep.get('items', []):
        out.append(f'    needs: {i}')
    if 'local' in rep:
        l = rep['local']
        out.append('  local: ' + (f"{len(l['findings'])} finding(s), {len(l['dropped'])} dropped" if l['ran'] else l.get('skipped', 'not run')))
    if 'second' in rep:
        s = rep['second']
        out.append('  second: ' + (f"{s['lane']} -> {s['verdict']}" if s.get('lane') else 'no lane available'))
        for a in s['attempts']:
            if a['status'] != 'ok':
                out.append(f"    {a['lane']}: unavailable - {a.get('reason', '')}")
    for q in rep.get('questions', []):
        out.append(f'  ? {q}')
    if rep.get('report'):
        out.append(f"  report: {rep['report']}")
    if 'post' in rep:
        out.append('  post: ' + (rep['post'].get('url') or rep['post'].get('why', '')))
    return '\n'.join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('repo')
    ap.add_argument('pr', type=int)
    ap.add_argument('--post', action='store_true', help='post one advisory comment (default: dry run)')
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--force', action='store_true', help='ignore a saved report for this head')
    a = ap.parse_args(argv)
    rep = run(a.repo, a.pr, do_post=a.post, force=a.force)
    print(json.dumps(rep, indent=1, ensure_ascii=False) if a.json else render(rep))
    return 0


if __name__ == '__main__':
    sys.exit(main())
