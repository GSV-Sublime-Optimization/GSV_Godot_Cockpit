r"""HOLOMIND cockpit feeder: what the Minds see and think, what every agent is doing, and a shared channel to talk in.

Every 10 s it writes C:\Users\Public\colony\mindview\feed.json (schema colony.mindview-feed/v0, plus `agents` and
`channel`) from:
  - xanadu, one SSH call: Mind events (~/steward/events), heartbeats (~/steward/heartbeats) and the shared cockpit
    channel (~/steward/cockpit/channel.jsonl: any agent or person appends one JSON line {at, from, to, text});
  - GitHub, every 3 min: open PRs touched in the last 24 h across the colony's busiest repos, attributed to agents by
    branch prefix (claude-cli/, gpt6/, codex/, muse/, gordon/...);
  - this rig: the GameAttract rotation's state.
Messages typed in HOLOMIND land in C:\Users\Public\colony\mindview\outbox.jsonl; this feeder appends them to the
shared channel, so every agent sees them.
The Mind answers messages addressed to it ("mind", or no address) with the i3's local model, grounded only on the
feed, unloaded right after (keep_alive 0), and never while a game is playing on the i3 screen. Its replies say so.
Nothing here can run commands or change systems: the only writes are chat lines and the local feed file.
"""
import base64
import datetime as dt
import json
import pathlib
import subprocess
import sys
import time
import urllib.request

HERE = pathlib.Path(r'C:\Users\Public\colony\mindview')
FEED = HERE / 'feed.json'
OUTBOX = HERE / 'outbox.jsonl'
SENT = HERE / 'outbox.sent'
STATE = HERE / 'cockpit.state.json'
XANADU = 'xeno@100.74.243.72'
OLLAMA = 'http://100.102.251.35:11434'
MODEL = 'qwen3:8b'
GAMEATTRACT = pathlib.Path.home() / 'Documents' / 'GameAttract' / 'status.json'
SILENT_AFTER_S = 15 * 60
REPOS = ['GSV-Sublime-Optimization/dev', 'GSV-Sublime-Optimization/GSV_Godot_Cockpit', 'GSV-Sublime-Optimization/Chronicles-of-the-Eternal-Bastion',
         'GSV-Sublime-Optimization/Dev-Mentor', 'GSV-Sublime-Optimization/Kilo_Core', 'GSV-Sublime-Optimization/FleetBridge',
         'Furyline/Furyline', 'Ash-and-Anvil/Ash-and-Anvil', 'Echoes-Of-Elevation/echoes-of-elevation', 'Project-144/project-144']
AGENTS = [  # (branch prefix, agent, where it runs)
    ('bakeoff/mindview-i3claude', 'Claude (i3 seat)', 'i3'), ('claude-cli/', 'Claude CLI', 'msi'), ('claude/', 'Claude', 'cloud'),
    ('agent/chatgpt-gpt6', 'GPT-6', 'cloud'), ('gpt6/', 'GPT-6', 'cloud'), ('codex/', 'Codex', 'cloud'), ('muse/', 'Muse', 'cloud'),
    ('gordon/', 'Gordon', 'cloud'), ('autopilot/', 'Autopilot lane', 'cloud'), ('procgen/', 'Procgen lane', 'cloud'),
]
BODIES = {'msi': ('MSI', 'workshop'), 'i3': ('i3', 'engine room'), 'l9': ('L9', 'second engine'), 'xanadu': ('xanadu', 'librarian + watchman')}
REMOTE = r'''
import json, glob, os, sys
out = {"events": [], "heartbeats": {}, "channel": []}
days = sorted(glob.glob(os.path.expanduser("~/steward/events/*.jsonl")))[-2:]
lines = []
for d in days:
    lines += open(d, encoding="utf-8").read().splitlines()
for l in lines[-60:]:
    try: out["events"].append(json.loads(l))
    except Exception: pass
for h in glob.glob(os.path.expanduser("~/steward/heartbeats/*.json")):
    try: out["heartbeats"][os.path.basename(h)[:-5]] = json.load(open(h, encoding="utf-8"))
    except Exception: pass
ch = os.path.expanduser("~/steward/cockpit/channel.jsonl")
os.makedirs(os.path.dirname(ch), exist_ok=True)
raw = sys.stdin.read()
try: data = json.loads(raw) if raw.strip() else {}
except Exception: data = {}
new = data.get("append", "")
if new.strip():
    with open(ch, "a", encoding="utf-8") as f: f.write(new if new.endswith("\n") else new + "\n")
if data.get("brief"):
    tmp = os.path.expanduser("~/steward/cockpit/brief.json.tmp")
    json.dump(data["brief"], open(tmp, "w", encoding="utf-8"), ensure_ascii=False)
    os.replace(tmp, os.path.expanduser("~/steward/cockpit/brief.json"))
out["cards"] = []
for c in sorted(glob.glob(os.path.expanduser("~/steward/outbox/*.md"))):
    try:
        first = next((l.strip("# ").strip() for l in open(c, encoding="utf-8") if l.strip()), os.path.basename(c))
        out["cards"].append({"file": os.path.basename(c), "title": first[:100]})
    except Exception: pass
if os.path.exists(ch):
    for l in open(ch, encoding="utf-8").read().splitlines()[-80:]:
        try: out["channel"].append(json.loads(l))
        except Exception: pass
print(json.dumps(out))
'''


def now():
    return dt.datetime.now(dt.timezone.utc)


def iso(t=None):
    return (t or now()).strftime('%Y-%m-%dT%H:%M:%SZ')


def age_s(stamp):
    try:
        return int((now() - dt.datetime.fromisoformat(str(stamp).replace('Z', '+00:00'))).total_seconds())
    except Exception:
        return None


def ssh(script, stdin=''):
    # The script travels base64-encoded so newlines and quotes arrive intact; stdin carries new channel lines.
    b64 = base64.b64encode(script.encode()).decode()
    r = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', XANADU,
                        f"python3 -c 'import base64; exec(base64.b64decode(\"{b64}\"))'"],
                       input=stdin, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=40, creationflags=0x08000000)
    if r.returncode:
        (HERE / 'cockpit.err.txt').write_text(f'{iso()} ssh rc={r.returncode} {r.stderr[-300:]}\n')
    return json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else None


def agent_of(branch):
    for prefix, name, home in AGENTS:
        if branch.startswith(prefix):
            return name, home
    return None, None


def github_activity():
    """Agents' latest PRs (last 24 h) and every open, non-draft PR still waiting for a second review."""
    acts, awaiting = [], []
    since = now() - dt.timedelta(hours=24)
    for repo in REPOS:
        r = subprocess.run(['gh', 'pr', 'list', '-R', repo, '--state', 'open', '--limit', '60', '--json',
                            'number,title,headRefName,headRefOid,updatedAt,isDraft,reviewDecision,url,comments'], stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=60, creationflags=0x08000000)
        try:
            prs = json.loads(r.stdout or '[]')
        except Exception:
            continue
        for p in prs:
            name, home = agent_of(p['headRefName'])
            reviewed = any(f'head={p.get("headRefOid", "")}' in c.get('body', '') and 'gsv-review:' in c.get('body', '') for c in p.get('comments') or [])
            if not p['isDraft'] and not reviewed and p.get('reviewDecision') in (None, '', 'REVIEW_REQUIRED'):
                awaiting.append({'repo': repo, 'number': p['number'], 'title': p['title'][:80], 'agent': name or 'unattributed',
                                 'url': p['url'], 'at': p['updatedAt']})
            if dt.datetime.fromisoformat(p['updatedAt'].replace('Z', '+00:00')) < since:
                continue
            if name:
                acts.append({'agent': name, 'home': home, 'at': p['updatedAt'], 'repo': repo.split('/')[1], 'number': p['number'],
                             'title': p['title'][:90], 'draft': p['isDraft']})
    github_activity.awaiting = sorted(awaiting, key=lambda a: a['at'], reverse=True)
    agents = {}
    for a in sorted(acts, key=lambda a: a['at'], reverse=True):
        g = agents.setdefault(a['agent'], {'agent': a['agent'], 'home': a['home'], 'recent': []})
        if len(g['recent']) < 4:
            g['recent'].append(a)
    return sorted(agents.values(), key=lambda g: g['recent'][0]['at'], reverse=True)


QUEUE = pathlib.Path(r'K:\quarantine\QUEUE.md')


MSI_SSH = ['ssh', '-i', str(pathlib.Path.home() / '.ssh' / 'i3_to_msi_ed25519'), '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes',
           '-o', 'ConnectTimeout=8', 'colony-i3@100.110.22.88', 'curl -s -m 8 http://127.0.0.1:8767/feed.json']


def chorus_facts():
    """The MSI's CHORUS cockpit measures what HOLOMIND can't: the off-box backup, the mirror and the MSI's spine
    services. Read its feed (read-only, over the i3's SSH account) and keep only those measured facts."""
    try:
        r = subprocess.run(MSI_SSH, capture_output=True, text=True, encoding='utf-8', timeout=30, stdin=subprocess.DEVNULL,
                           creationflags=0x08000000)
        f = json.loads(r.stdout)
    except Exception:
        return None
    sp = f.get('spine') or {}
    return {'at': iso(), 'backup': f.get('backup'), 'mirror': {k: v for k, v in (f.get('mirror') or {}).items() if k != 'repos'},
            'spine': {'up': sp.get('up'), 'total': sp.get('total'),
                      'down': [x.get('name') for x in sp.get('services', []) if not x.get('up', True)]}}


ORDER_RANK = {'working': 0, 'taken': 1, 'posted': 2, 'declined': 3, 'done': 4}


def fold_orders(lines):
    """Work orders in the shared channel, in CHORUS's shape: {kind:'order', id, to, station, text[, ref]} then
    {kind:'order-status', id, status: taken|working|done|declined, note, link}. One queue for every cockpit."""
    state = {}
    for m in lines:
        if m.get('kind') == 'order' and m.get('id'):
            state[m['id']] = {'id': m['id'], 'at': m.get('at'), 'from': m.get('from'), 'to': m.get('to', 'any'),
                              'station': m.get('station', 'anvil'), 'text': m.get('text', ''), 'ref': m.get('ref', ''),
                              'url': m.get('url', ''), 'status': 'posted', 'by': None, 'note': '', 'link': '',
                              'history': [{'at': m.get('at'), 'status': 'posted', 'by': m.get('from')}]}
        elif m.get('kind') == 'order-status' and m.get('id') in state:
            o = state[m['id']]
            o.update(status=m.get('status', o['status']), by=m.get('from'), note=m.get('note', o['note']), link=m.get('link', o['link']))
            o['history'].append({'at': m.get('at'), 'status': m.get('status'), 'by': m.get('from')})
    return sorted(state.values(), key=lambda o: (ORDER_RANK.get(o['status'], 5), o['at'] or ''))


def actions(bodies, awaiting, cards, channel, colony=None):
    """The colony's work queue: what needs doing, where it lives in the cockpit, and who it's for."""
    out = []
    for rid, b in bodies.items():
        if b['status'] in ('red', 'silent'):
            out.append({'kind': 'rig', 'where': rid, 'title': f"{b['label']} is {b['status']}" + (f": {', '.join(b['failing'])}" if b['failing'] else '')})
    for name in ((colony or {}).get('spine') or {}).get('down', []):
        out.append({'kind': 'rig', 'where': 'msi', 'title': f"MSI spine service down: {name}"})
    for a in awaiting[:12]:
        out.append({'kind': 'review', 'where': a['agent'], 'title': f"{a['repo'].split('/')[1]}#{a['number']} awaits a second review: {a['title']}", 'url': a['url']})
    for c in cards[:8]:
        out.append({'kind': 'decision', 'where': 'keath', 'title': f"xanadu card {c['file']}: {c['title']}"})
    try:
        for l in QUEUE.read_text(encoding='utf-8').splitlines():
            if l.startswith('|') and ('waiting for Keath' in l or '| open |' in l):
                out.append({'kind': 'decision', 'where': 'keath', 'title': 'quarantine: ' + l.split('|')[1].strip()[:80]})
    except OSError:
        pass
    # Messages to a person or agent that nobody has answered yet.
    for i, m in enumerate(channel):
        to = str(m.get('to', '')).lower()
        if to in ('', 'all', 'mind'):
            continue
        replied = any(str(n.get('from', '')).lower().startswith(to.split(' ')[0]) for n in channel[i + 1:])
        if not replied and age_s(m.get('at')) is not None and age_s(m.get('at')) < 86400:
            out.append({'kind': 'reply', 'where': to, 'title': f"{m.get('from')} asked {to}: {str(m.get('text'))[:70]}"})
    return out


def ask_mind(question, feed):
    """The i3 Mind answers from the feed only. Never while a game is playing (GPU is shared)."""
    if 'playing' in str(feed.get('screen', '')):
        return "I'll answer after the current playtest; the engine room's GPU is busy with the game."
    bodies = '; '.join(f"{b['label']} {b['status']}" + (f" (failing {', '.join(b['failing'])})" if b['failing'] else '') for b in feed['bodies'].values())
    thoughts = ' | '.join(f"{e.get('mind')}: {e.get('line')}" for e in feed['events'][-6:])
    agents = ' | '.join(f"{g['agent']}: {g['recent'][0]['title']} ({g['recent'][0]['repo']} #{g['recent'][0]['number']})" for g in feed.get('agents', [])[:8])
    actions = ' | '.join(f"[{a['kind']}] {a['title']}" for a in feed.get('actions', [])[:12])
    context = f"FLEET: {bodies}\nRECENT THOUGHTS: {thoughts}\nAGENTS AT WORK: {agents}\nWORK WAITING: {actions}\nSCREEN: {feed.get('screen')}"
    body = {'model': MODEL, 'stream': False, 'think': False, 'keep_alive': 0, 'options': {'num_predict': 160, 'temperature': 0.3},
            'messages': [{'role': 'system', 'content': 'You are the i3 Mind of the GSV colony, observing its fleet and agents. Answer in 1-3 short sentences, '
                                                      'only from CONTEXT. MEASURED NOW facts override older RECENT THOUGHTS. If CONTEXT does not say, say you cannot see that yet. You cannot act; you only observe.'},
                         {'role': 'user', 'content': f'CONTEXT:\n{context}\n\nQUESTION: {question}'}]}
    try:
        req = urllib.request.Request(OLLAMA + '/api/chat', data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read())['message']['content'].strip()
    except Exception as exc:
        return f'(the i3 Mind could not think just now: {str(exc)[:80]})'


def tick(state):
    # Messages typed in HOLOMIND since the last tick go to the shared channel.
    lines = OUTBOX.read_text(encoding='utf-8').splitlines() if OUTBOX.exists() else []
    sent = int(state.get('outbox_sent', 0))
    pending = lines[sent:]
    remote = ssh(REMOTE, json.dumps({'append': '\n'.join(pending), 'brief': state.get('brief')}))
    if remote is None:
        return None
    state['outbox_sent'] = len(lines)
    if time.time() - state.get('gh_at', 0) > 180:
        state['agents'] = github_activity()
        state['awaiting'] = getattr(github_activity, 'awaiting', [])
        state['gh_at'] = time.time()
    bodies = {}
    for bid, (label, role) in BODIES.items():
        bodies[bid] = {'label': label, 'role': role, 'status': 'unknown', 'failing': [], 'age_s': None, 'detail': ''}
    for rig, hb in remote.get('heartbeats', {}).items():
        if rig in bodies:
            a = age_s(hb.get('at'))
            failing = [c['name'] for c in hb.get('checks', []) if not c.get('ok')]
            disks = ', '.join(f"{k}: {v.get('pct_free')}% free" for k, v in (hb.get('disks') or {}).items())
            parts = ([f"RAM {hb['ram_avail_mb']} MB free"] if hb.get('ram_avail_mb') is not None else []) + ([disks] if disks else [])
            bodies[rig].update(status='silent' if a is None or a > SILENT_AFTER_S else ('green' if hb.get('green') else 'red'),
                               failing=failing, age_s=a, detail='; '.join(parts))
    bodies['xanadu'].update(status='green', age_s=0, detail='answering')
    screen = ''
    try:
        s = json.loads(GAMEATTRACT.read_text(encoding='utf-8'))
        screen = f"playing {s.get('game')}" if s.get('state') == 'playing' else f"rotation {s.get('state')}"
    except Exception:
        pass
    events = remote.get('events', [])
    for e in events:
        text = (' '.join(e.get('reasons', [])) + ' ' + e.get('line', '')).lower()
        e['focus'] = e.get('focus') or next((b for b in ('i3', 'msi', 'l9', 'xanadu') if b in text), 'xanadu')
    raw_channel = remote.get('channel', [])
    # Read receipts: {"kind": "read", "from": seat, "at": t} lines say "seat has read everything up to t".
    # Two receipt shapes, both valid: a watermark {kind, from, at} (HOLOMIND) and a list {kind, from, reads: [at...]} (CHORUS).
    reads, listed = {}, {}
    for m in raw_channel:
        if m.get('kind') == 'read':
            if isinstance(m.get('reads'), list):
                listed.setdefault(str(m.get('from')), set()).update(str(a) for a in m['reads'])
            else:
                reads[str(m.get('from'))] = max(reads.get(str(m.get('from')), ''), str(m.get('at', '')))
    orders = fold_orders(raw_channel)
    decisions = {str(m.get('card')): m for m in raw_channel if m.get('kind') == 'decision'}
    channel = [m for m in raw_channel if m.get('kind') not in ('read', 'order-status', 'decision')]
    for i, m in enumerate(channel):
        who = str(m.get('from', ''))
        rb = sorted({s for s, t in reads.items() if t >= str(m.get('at', ''))}
                    | {s for s, ats in listed.items() if str(m.get('at', '')) in ats})
        rb = [s for s in rb if s.lower() != who.lower()]
        # Anyone who replied to this sender afterwards has evidently read it.
        for n in channel[i + 1:]:
            if str(n.get('to', '')).lower() == who.lower() and str(n.get('from')) not in rb and str(n.get('from')).lower() != who.lower():
                rb.append(str(n.get('from')))
        m['read_by'] = rb
    feed = {'schema': 'colony.mindview-feed/v0', 'at': iso(), 'source_ok': True, 'bodies': bodies, 'events': events[-40:],
            'attention': (events[-1] if events else {}).get('focus', 'xanadu'), 'screen': screen,
            'agents': state.get('agents', []), 'channel': channel[-40:]}
    if time.time() - state.get('chorus_at', 0) > 60:
        state['chorus_at'] = time.time()
        fresh, prev = chorus_facts(), state.get('colony') or {}
        if fresh and fresh['spine']['up'] is None and prev.get('spine'):
            fresh['spine'] = prev['spine']   # CHORUS omitted it this pass: keep the last measurement
        state['colony'] = fresh or state.get('colony')
    feed['colony'] = state.get('colony')
    feed['actions'] = actions(bodies, state.get('awaiting', []), remote.get('cards', []), channel, feed['colony'])
    feed['orders'] = orders[-30:]
    feed['decisions'] = list(decisions.values())[-30:]
    ordered = {o.get('ref') for o in orders if o.get('status') not in ('declined',)}
    for a in feed['actions']:
        a['id'] = a.get('id') or (a['kind'] + ':' + a.get('url', a['title'])[:120])
        if a['id'] in ordered:
            a['ordered'] = next(o for o in reversed(orders) if o.get('ref') == a['id'])['status']
        if a['kind'] == 'decision' and a['title'] in decisions:
            a['decided'] = decisions[a['title']].get('verdict')
    feed['actions'] = [a for a in feed['actions'] if not a.get('decided')]
    def publish():
        tmp = FEED.with_suffix('.tmp')
        tmp.write_text(json.dumps(feed, ensure_ascii=False), encoding='utf-8')
        tmp.replace(FEED)
    # Publish first, so a Mind busy thinking never freezes the view.
    pending = [m for m in channel if f"{m.get('at')}|{m.get('from')}|{m.get('text')}" not in set(state.get('answered', []))
               and not m.get('kind') and not m.get('from', '').endswith('mind') and str(m.get('to', 'mind')).lower() in ('mind', '', 'all')
               and not (age_s(m.get('at')) is not None and age_s(m.get('at')) > 600)]
    feed['mind_thinking'] = len(pending)
    publish()
    # The Mind answers new messages addressed to it (or to nobody in particular), one per tick.
    answered = set(state.get('answered', []))
    budget = 1
    for m in channel:
        key = f"{m.get('at')}|{m.get('from')}|{m.get('text')}"
        if key in answered or m.get('kind') or m.get('from', '').endswith('mind') or str(m.get('to', 'mind')).lower() not in ('mind', '', 'all'):
            continue
        if age_s(m.get('at')) is not None and age_s(m.get('at')) > 600:
            answered.add(key)
            continue
        if budget <= 0:
            break
        budget -= 1
        reply = ask_mind(m.get('text', ''), feed)
        line = {'at': iso(), 'from': 'i3-mind', 'model': MODEL, 'to': m.get('from'), 'text': reply}
        m.setdefault('read_by', []).append('i3-mind') if 'i3-mind' not in m.get('read_by', []) else None
        ssh(REMOTE, json.dumps({'append': json.dumps(line, ensure_ascii=False)}))
        channel.append({**line, 'read_by': []})
        answered.add(key)
    state['answered'] = sorted(answered)[-200:]
    feed['channel'] = channel[-40:]
    # The brief: the colony's state and work queue in one small document any agent can read from xanadu.
    state['brief'] = {'schema': 'colony.cockpit-brief/v0', 'at': feed['at'], 'screen': screen,
                      'rigs': {k: {'status': v['status'], 'failing': v['failing']} for k, v in bodies.items()},
                      'agents': [{'agent': g['agent'], 'latest': f"{g['recent'][0]['repo']}#{g['recent'][0]['number']} {g['recent'][0]['title']}"}
                                 for g in feed['agents']],
                      'actions': feed['actions'][:30], 'orders': [o for o in orders if o['status'] not in ('done', 'declined')][-20:], 'channel': channel[-8:]}
    feed['mind_thinking'] = max(0, len(pending) - (1 - budget))
    publish()
    return feed


if __name__ == '__main__':
    HERE.mkdir(parents=True, exist_ok=True)
    try:
        state = json.loads(STATE.read_text())
    except Exception:
        state = {}
    while True:
        try:
            f = tick(state)
            STATE.write_text(json.dumps(state))
            if '--once' in sys.argv:
                print(json.dumps({'agents': [(g['agent'], g['home'], g['recent'][0]['title']) for g in (f or {}).get('agents', [])],
                                  'channel': len((f or {}).get('channel', []))}, indent=1)[:2500])
                break
        except Exception as exc:
            (HERE / 'cockpit.err.txt').write_text(f'{iso()} {exc}\n')
            if '--once' in sys.argv:
                raise
        time.sleep(10)
