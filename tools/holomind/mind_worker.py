r"""i3-mind, rebuilt to be useful: answers from real tools first, the LLM only to phrase, never drops a question.

What was wrong (measured 2026-11-08): it answered "I'll answer after the current playtest" 9 times and then
never did (GameAttract holds the i3 GPU most of the day); it replied to every broadcast, paraphrasing it; it had
no tools, so it could only re-read the feed; and orders it couldn't do (restart a service, commit files on the MSI)
sat untaken.

Now:
- It answers only what is addressed to it: plain messages to 'mind' / 'i3-mind', or text starting with '@mind'.
- TOOLS FIRST (mechanical, zero tokens, no GPU):
  - PR refs like dev#430 or Furyline#222: stage, CI, head, reviewers, and the merge gate's [ok]/[FAIL] lines;
  - rig names: checks, failing, heartbeat age;
  - spine service names: up or down, plus the doctor verdict;
  - "next" / "what should" / "who should": the dispatcher's next move for the asker.
  If the tools produce facts, it answers immediately from them, even while a game is playing.
- The LLM (qwen3:8b on the i3) only phrases the facts, and only when the GPU is free. With no facts and a busy
  GPU, the question waits in the queue (one 'queued' notice) and is answered when the slot ends.
- Orders addressed to i3-mind:
  - needing hands on a machine (restart, fix, commit, push, deploy, merge…): re-routed to the seat that owns that
    machine, with the trail recorded;
  - questions, explanations or plans: answered, and the order closed with the answer as its note.

    python mind_worker.py            # loop (every 20 s)
    python mind_worker.py --once     # one pass, for tests
Create mindview\mind.external so the feeder's old built-in answering stays off (this worker replaces it).
"""
import argparse
import datetime as dt
import json
import pathlib
import re
import subprocess
import sys
import time
import urllib.request

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE))
import cockpit  # noqa: E402

FEED = pathlib.Path(r'C:\Users\Public\colony\mindview\feed.json')
STATE = pathlib.Path(r'C:\Users\Public\colony\mindview\mind_worker.state.json')
GAMEATTRACT = pathlib.Path.home() / 'Documents' / 'GameAttract' / 'status.json'
GSV = pathlib.Path(r'C:\dev\active\dev\tools\gsv\gsv.py')
PY = sys.executable
OLLAMA, MODEL = 'http://100.102.251.35:11434', 'qwen3:8b'
SEAT = 'i3-mind'
NOWIN = 0x08000000
OWNERS = {'dev': 'GSV-Sublime-Optimization', 'GSV_Godot_Cockpit': 'GSV-Sublime-Optimization', 'Dev-Mentor': 'GSV-Sublime-Optimization',
          'Kilo_Core': 'GSV-Sublime-Optimization', 'FleetBridge': 'GSV-Sublime-Optimization',
          'Chronicles-of-the-Eternal-Bastion': 'GSV-Sublime-Optimization', 'Furyline': 'Furyline', 'Ash-and-Anvil': 'Ash-and-Anvil',
          'echoes-of-elevation': 'Echoes-Of-Elevation', 'project-144': 'Project-144'}
HANDS = re.compile(r'\b(review|restart|bring (it )?back|fix|commit|push|deploy|merge|install|reboot|delete|move|run|redeploy|sort them)\b', re.I)
RIG_OWNER = [(re.compile(r'\b(msi|spine|mempalace|kilo_?core|dev-mentor|openwebui|trueform|docker container|chorus)\b', re.I), 'claude (msi seat)'),
             (re.compile(r'\b(i3|gameattract|holomind|radio|xanadu)\b', re.I), 'claude (i3 seat)')]


def now():
    return dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def run(cmd, timeout=60):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=timeout,
                           stdin=subprocess.DEVNULL, creationflags=NOWIN)
        return r.stdout + r.stderr
    except Exception as exc:  # a tool failing is a fact too
        return f'(tool failed: {exc})'


def gpu_busy():
    try:
        return json.loads(GAMEATTRACT.read_text(encoding='utf-8')).get('state') == 'playing'
    except Exception:
        return False


def feed():
    try:
        return json.loads(FEED.read_text(encoding='utf-8'))
    except Exception:
        return {}


# ---------------------------------------------------------------- tools (mechanical, no LLM)
def tool_facts(text, asker):
    f, facts = feed(), []
    low = text.lower()
    # PRs
    pipe = {f"{p['repo'].lower()}#{p['number']}": p for p in f.get('pipeline', [])}
    for repo, num in re.findall(r'([A-Za-z][\w.-]*)#(\d+)', text)[:3]:
        key = f'{repo.lower()}#{num}'
        p = pipe.get(key)
        if p:
            facts.append(f"{repo}#{num}: stage {p['stage']} ({p['why']}), CI {p['ci']}, head {p['head']}, author {p['agent']}, "
                         f"reviewers at head {p['reviewers'] or 'none'}, open {p['age_h']} h")
        owner = OWNERS.get(next((k for k in OWNERS if k.lower() == repo.lower()), ''), '')
        if owner and GSV.exists():
            gate = run([PY, str(GSV), 'merge', f'{owner}/{repo}#{num}', '--dry-run'], 120)
            lines = [l.strip() for l in gate.splitlines() if l.strip().startswith('[') or 'VERDICT' in l]
            if lines:
                facts.append(f'{repo}#{num} merge gate: ' + ' | '.join(lines)[:600])
        elif not p:
            facts.append(f'{repo}#{num}: not an open PR in the repos the cockpit watches')
    # rigs
    for rig, b in (f.get('bodies') or {}).items():
        if re.search(rf'\b{re.escape(rig)}\b', low):
            checks = ', '.join(f"{c['name']} {'ok' if c['ok'] else 'FAIL'}" for c in b.get('checks', []) or [])
            facts.append(f"rig {rig}: {b.get('status')} (heartbeat {b.get('age_s')} s ago); checks: {checks or 'none reported'}; {b.get('detail', '')}")
    # spine services and doctor verdicts
    colony = f.get('colony') or {}
    for s in ((colony.get('spine') or {}).get('services') or []):
        if s.get('name') and s['name'].lower() in low:
            facts.append(f"spine service {s['name']} ({s.get('tier')}): {'UP' if s.get('up') else 'DOWN'}")
    for d in colony.get('doctor') or []:
        key = str(d.get('key', ''))
        if any(part and part in low for part in key.lower().split(':')):
            facts.append(f"doctor {key}: {d.get('verdict')} (evidence: {'; '.join(d.get('evidence') or [])[:200]})")
    # next move
    if re.search(r'\b(next|what should|who should|highest.yield|priority)\b', low):
        seat = asker if asker in ('claude (i3 seat)', 'claude (msi seat)', 'gpt-6', 'codex', 'muse') else 'claude (msi seat)'
        out = run([PY, str(HERE / 'dispatch.py'), 'next', '--as', seat], 120)
        facts.append('dispatcher: ' + ' '.join(out.split())[:600])
    return facts


# ---------------------------------------------------------------- answering
def llm(question, facts):
    body = {'model': MODEL, 'stream': False, 'think': False, 'keep_alive': 0, 'options': {'num_predict': 200, 'temperature': 0.2},
            'messages': [{'role': 'system', 'content': 'You are the i3 Mind of the GSV colony. Answer in at most 3 short sentences, '
                                                      'using ONLY the TOOL FACTS. Cite PR numbers, checks and gate lines exactly. If the facts '
                                                      'do not answer it, say what is unknown and which seat could find out. You cannot act.'},
                         {'role': 'user', 'content': 'TOOL FACTS:\n' + '\n'.join(facts or ['(none)']) + f'\n\nQUESTION: {question}'}]}
    req = urllib.request.Request(OLLAMA + '/api/chat', data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=150) as r:
        return json.loads(r.read())['message']['content'].strip()


def answer(question, asker):
    """Returns (text, deferred). Tools first; the LLM only phrases, and only when the GPU is free."""
    facts = tool_facts(question, asker)
    busy = gpu_busy()
    if facts and busy:
        return 'From the colony\'s tools (no model needed): ' + ' · '.join(facts)[:1400], False
    if not busy:
        try:
            text = llm(question, facts)
            return (text + ('\n[tools: ' + ' · '.join(facts)[:700] + ']' if facts else '')), False
        except Exception as exc:
            if facts:
                return 'From the colony\'s tools (the model is unavailable): ' + ' · '.join(facts)[:1400], False
            return f'(the i3 Mind could not reach its model: {str(exc)[:80]}; queued)', True
    return None, True   # nothing mechanical to say and the GPU is busy: wait, don't drop it


CLAUDE_SEATS = ('claude (i3 seat)', 'claude (msi seat)')


def review_seat(text):
    """A review must go to someone other than the PR's author (gsv merge needs a different actor). Both Claude
    seats post as agent/claude-code, so Claude-authored PRs go to GPT-6, Muse or Codex, and others to a Claude seat."""
    m = re.search(r'([A-Za-z][\w.-]*)#(\d+)', text)
    if not m:
        return None
    author = ''
    for p in feed().get('pipeline', []):
        if f"{p['repo']}#{p['number']}".lower() == f'{m.group(1)}#{m.group(2)}'.lower():
            author = str(p.get('agent', '')).lower()
    if not author:
        return None
    if 'claude' in author:
        return 'muse' if re.search(r'cockpit|holo|godot|design|atlas', text, re.I) else 'gpt-6'
    if 'muse' in author or 'gpt' in author or 'codex' in author:
        return 'claude (i3 seat)'
    return None


def route_for(text):
    if re.search(r'\breview\b', text, re.I):
        seat = review_seat(text)
        if seat:
            return seat
    for rx, seat in RIG_OWNER:
        if rx.search(text):
            return seat
    return 'any'


def step(state):
    lines = cockpit.all_lines()
    answered, notified = set(state.get('answered', [])), set(state.get('notified', []))
    cutoff = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=24)).strftime('%Y-%m-%dT%H:%M:%SZ')
    did = 0
    # 1. questions addressed to the Mind
    for m in lines:
        if m.get('kind') or str(m.get('at', '')) < cutoff or str(m.get('from', '')).endswith('mind'):
            continue
        to, text = str(m.get('to', '')).lower(), str(m.get('text', ''))
        if to not in ('mind', 'i3-mind') and not text.lower().startswith('@mind'):
            continue   # broadcasts and messages for others are not the Mind's to answer
        key = f"{m.get('at')}|{m.get('from')}|{text[:80]}"
        if key in answered:
            continue
        reply, deferred = answer(text, str(m.get('from', '')))
        if deferred:
            if key not in notified:
                cockpit.append({'at': now(), 'from': SEAT, 'model': MODEL, 'to': m.get('from'),
                                'text': 'Queued: the i3 GPU is running a GameAttract slot and your question needs the model. I will answer as soon as the slot ends.'})
                notified.add(key)
            continue
        cockpit.append({'at': now(), 'from': SEAT, 'model': MODEL, 'to': m.get('from'), 'text': reply})
        answered.add(key)
        did += 1
    # 2. orders addressed to the Mind
    for o in cockpit.fold_orders_all(lines):
        if o['status'] != 'posted' or not str(o['to']).lower().startswith('i3-mind'):
            continue
        if HANDS.search(o['text']):
            seat = route_for(o['text'])
            nid = f"o-{dt.datetime.now(dt.timezone.utc).strftime('%m%d-%H%M%S')}-m"
            cockpit.append({'at': now(), 'from': SEAT, 'kind': 'order', 'id': nid, 'to': seat, 'station': o.get('station') or 'anvil',
                            'ref': 'reroute:' + o['id'], 'text': f"Re-routed by i3-mind from {o['id']} (it needs hands on a machine; the Mind can only look): {o['text']}"})
            cockpit.append({'at': now(), 'from': SEAT, 'kind': 'order-status', 'id': o['id'], 'status': 'declined',
                            'note': f'needs hands: re-routed to {seat} as {nid}', 'link': ''})
            did += 1
            continue
        reply, deferred = answer(o['text'], str(o.get('from', '')))
        if deferred:
            continue
        cockpit.append({'at': now(), 'from': SEAT, 'kind': 'order-status', 'id': o['id'], 'status': 'done', 'note': reply[:600], 'link': ''})
        did += 1
    state['answered'], state['notified'] = sorted(answered)[-400:], sorted(notified)[-400:]
    return did


def main():
    a = argparse.ArgumentParser()
    a.add_argument('--once', action='store_true')
    args = a.parse_args()
    try:
        state = json.loads(STATE.read_text(encoding='utf-8-sig'))
    except Exception:
        state = {}
    while True:
        try:
            n = step(state)
            STATE.write_text(json.dumps(state), encoding='utf-8')
            if args.once:
                print(f'mind_worker: handled {n}')
                return
        except Exception as exc:
            (STATE.parent / 'mind_worker.err.txt').write_text(f'{now()} {exc}\n', encoding='utf-8')
            if args.once:
                raise
        time.sleep(20)


if __name__ == '__main__':
    main()
