r"""Mind View feeder: gathers what the colony's Minds see and think into one local file for the Godot view.

Every 15 s (or once with --once):
- from xanadu, in one SSH call: the Minds' event lines (~/steward/events/<date>.jsonl, newest 60) and every rig's
  heartbeat (~/steward/heartbeats/*.json);
- from this rig: the GameAttract rotation's status.json;
- turns *changes* into observer lines (a rig going red or green or silent, a new game on screen). These are labelled
  mind="observer" and model=null: deterministic, not a model thinking.
Writes C:\Users\Public\colony\mindview\feed.json atomically. Read-only everywhere else: it changes nothing it watches.
"""
import datetime as dt
import json
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).parent
FEED = HERE / 'feed.json'
JOURNAL = HERE / 'observer.jsonl'
STATE = HERE / 'observer.state.json'
XANADU = 'xeno@100.74.243.72'
GAMEATTRACT = pathlib.Path.home() / 'Documents' / 'GameAttract' / 'status.json'
SILENT_AFTER_S = 15 * 60
BODIES = {   # id -> (label, role); positions are the view's business
    'msi': ('MSI', 'workshop'),
    'i3': ('i3', 'engine room'),
    'l9': ('L9', 'second engine'),
    'xanadu': ('xanadu', 'librarian + watchman'),
}
REMOTE = r'''
import json, glob, os, datetime
out = {"events": [], "heartbeats": {}}
days = sorted(glob.glob(os.path.expanduser("~/steward/events/*.jsonl")))[-2:]
lines = []
for d in days:
    with open(d, encoding="utf-8") as f:
        lines += f.read().splitlines()
for l in lines[-60:]:
    try: out["events"].append(json.loads(l))
    except Exception: pass
for h in glob.glob(os.path.expanduser("~/steward/heartbeats/*.json")):
    try: out["heartbeats"][os.path.basename(h)[:-5]] = json.load(open(h, encoding="utf-8"))
    except Exception: pass
mem = {}
for l in open("/proc/meminfo"):
    k, v = l.split(":", 1); mem[k] = int(v.split()[0])
out["xanadu_self"] = {"at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"), "mem_avail_mb": mem.get("MemAvailable", 0) // 1024}
print(json.dumps(out))
'''


def now():
    return dt.datetime.now(dt.timezone.utc)


def iso(t):
    return t.strftime('%Y-%m-%dT%H:%M:%SZ')


def age_s(stamp):
    try:
        t = dt.datetime.fromisoformat(stamp.replace('Z', '+00:00'))
        return int((now() - t).total_seconds())
    except Exception:
        return None


def fetch_remote():
    r = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', XANADU, 'python3 -'],
                       input=REMOTE, capture_output=True, text=True, timeout=40, creationflags=0x08000000)
    if r.returncode:
        return None
    return json.loads(r.stdout)


def observe(state, bodies, game):
    """Observer lines for anything that changed since the last tick."""
    lines = []
    for bid, b in bodies.items():
        status = b['status']
        if state.get(bid) != status:
            if bid in state:  # not on the very first tick
                why = ', '.join(b.get('failing', [])) or ''
                lines.append({'level': 'alarm' if status in ('red', 'silent') else 'calm', 'focus': bid,
                              'line': f"{b['label']} went {status}" + (f': {why}' if why else '')})
            state[bid] = status
    if game and state.get('_game') != game:
        if '_game' in state:
            lines.append({'level': 'calm', 'focus': 'i3', 'line': f'i3 screen: {game}'})
        state['_game'] = game
    stamp = iso(now())
    return [{'at': stamp, 'mind': 'observer', 'model': None, 'reasons': [], **l} for l in lines]


def tick():
    remote = fetch_remote()
    bodies = {}
    for bid, (label, role) in BODIES.items():
        bodies[bid] = {'label': label, 'role': role, 'status': 'unknown', 'failing': [], 'age_s': None, 'detail': ''}
    if remote:
        for rig, hb in remote.get('heartbeats', {}).items():
            if rig not in bodies:
                continue
            a = age_s(hb.get('at', ''))
            failing = [c['name'] for c in hb.get('checks', []) if not c.get('ok')]
            status = 'silent' if a is None or a > SILENT_AFTER_S else ('green' if hb.get('green') else 'red')
            disks = ', '.join(f"{k}: {v.get('pct_free')}% free" for k, v in (hb.get('disks') or {}).items())
            bodies[rig].update(status=status, failing=failing, age_s=a,
                               detail=f"RAM {hb.get('ram_avail_mb', '?')} MB free; {disks}")
        xs = remote.get('xanadu_self', {})
        bodies['xanadu'].update(status='green', age_s=0, detail=f"answering; RAM {xs.get('mem_avail_mb', '?')} MB free")
    else:
        bodies['xanadu'].update(status='silent', detail='SSH to xanadu failed this tick')
    game = ''
    try:
        s = json.loads(GAMEATTRACT.read_text(encoding='utf-8'))
        game = f"playing {s.get('game')}" if s.get('state') == 'playing' else f"rotation {s.get('state', '?')}"
    except Exception:
        pass
    try:
        state = json.loads(STATE.read_text())
    except Exception:
        state = {}
    new = observe(state, bodies, game)
    STATE.write_text(json.dumps(state))
    if new:
        with open(JOURNAL, 'a', encoding='utf-8') as j:
            for e in new:
                j.write(json.dumps(e) + '\n')
    observer = []
    if JOURNAL.exists():
        for l in JOURNAL.read_text(encoding='utf-8').splitlines()[-60:]:
            try:
                observer.append(json.loads(l))
            except Exception:
                pass
    minds = (remote or {}).get('events', [])
    for e in minds:   # the Minds name rigs in their reasons; point the attention at the first one they mention
        text = ' '.join(e.get('reasons', [])) + ' ' + e.get('line', '')
        e['focus'] = e.get('focus') or next((b for b in ('i3', 'msi', 'l9', 'xanadu') if b in text.lower()), 'xanadu')
    events = sorted(minds + observer, key=lambda e: e.get('at', ''))[-80:]
    latest = events[-1] if events else None
    feed = {'schema': 'colony.mindview-feed/v0', 'at': iso(now()), 'source_ok': remote is not None, 'bodies': bodies,
            'events': events, 'attention': (latest or {}).get('focus', 'xanadu'), 'screen': game}
    tmp = FEED.with_suffix('.tmp')
    tmp.write_text(json.dumps(feed, ensure_ascii=False), encoding='utf-8')
    tmp.replace(FEED)
    return feed


if __name__ == '__main__':
    if '--once' in sys.argv:
        f = tick()
        print(json.dumps({k: (v if k != 'events' else len(v)) for k, v in f.items()}, indent=1)[:1500])
        sys.exit(0)
    while True:
        try:
            tick()
        except Exception as exc:
            (HERE / 'feeder.err.txt').write_text(f'{iso(now())} {exc}\n')
        time.sleep(15)
