r"""Turn the bakeoff's shared fixture (issue #14, tests/fixtures/mindview-20261108/, from PR #16) into HOLOMIND's feed.

Pure and deterministic: ages are measured against the fixture's freeze time (2026-11-08 06:48 UTC), not the clock,
so every run renders the same picture. Nothing is invented: no agents, channel or work queue (the shared fixture
has none), and they are shown as empty, not simulated.

    python tools/holomind/shared_fixture.py            # writes tests/fixtures/holomind_shared_feed.json
"""
import datetime as dt
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / 'tests' / 'fixtures' / 'mindview-20261108'
OUT = ROOT / 'tests' / 'fixtures' / 'holomind_shared_feed.json'
FROZEN = dt.datetime(2026, 11, 8, 6, 48, tzinfo=dt.timezone.utc)
SILENT_AFTER_S = 15 * 60
BODIES = {'msi': ('MSI', 'workshop'), 'i3': ('i3', 'engine room'), 'l9': ('L9', 'second engine'), 'xanadu': ('xanadu', 'librarian + watchman')}


def age_s(stamp):
    return int((FROZEN - dt.datetime.fromisoformat(stamp.replace('Z', '+00:00'))).total_seconds())


def build():
    bodies = {}
    for rid, (label, role) in BODIES.items():
        bodies[rid] = {'label': label, 'role': role, 'status': 'unknown', 'failing': [], 'age_s': None, 'detail': ''}
        hp = SRC / f'heartbeat_{rid}.json'
        if hp.exists():
            hb = json.loads(hp.read_text(encoding='utf-8'))
            a = age_s(hb['at'])
            disks = ', '.join(f"{k}: {v.get('pct_free')}% free" for k, v in (hb.get('disks') or {}).items())
            bodies[rid].update(status='silent' if a > SILENT_AFTER_S else ('green' if hb.get('green') else 'red'),
                               failing=[c['name'] for c in hb.get('checks', []) if not c.get('ok')], age_s=a,
                               detail='; '.join(([f"RAM {hb['ram_avail_mb']} MB free"] if hb.get('ram_avail_mb') is not None else []) + ([disks] if disks else [])))
    # xanadu has no heartbeat in the fixture; it holds the record, so it is shown as unknown, not green.
    bodies['xanadu']['detail'] = 'no heartbeat in the shared fixture'
    events = [json.loads(l) for l in (SRC / 'events.jsonl').read_text(encoding='utf-8').splitlines() if l.strip()]
    for e in events:
        text = (' '.join(e.get('reasons', [])) + ' ' + e.get('line', '')).lower()
        e['focus'] = e.get('focus') or next((b for b in BODIES if b in text), 'xanadu')
    return {'schema': 'colony.mindview-feed/v0', 'at': FROZEN.strftime('%Y-%m-%dT%H:%M:%SZ'), 'source_ok': True,
            'source': 'SHARED FIXTURE mindview-20261108 (bakeoff #14)', 'bodies': bodies, 'events': events,
            'attention': events[-1]['focus'] if events else 'xanadu', 'screen': '', 'agents': [], 'channel': [], 'actions': []}


if __name__ == '__main__':
    OUT.write_text(json.dumps(build(), ensure_ascii=False, indent=1), encoding='utf-8')
    print('wrote', OUT)
