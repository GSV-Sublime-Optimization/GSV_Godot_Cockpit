r"""portable: where HOLOMIND's tools find things on whichever rig they run.

Every default is the value the i3 used before this module existed, so nothing changes on the i3.
Each one can be overridden by an environment variable, and the Windows-only parts are guarded by
os.name, so the same files run on MSI, L9 and a Linux box (xanadu) without edits.

| Env var | Default | What |
|---|---|---|
| HOLOMIND_DIR | Windows: C:\Users\Public\colony\mindview; elsewhere: $XDG_DATA_HOME/colony/mindview | feed.json, outbox, state, activity |
| XANADU_SSH | xeno@100.74.243.72 (`local` = run on this box; automatic when the hostname is xanadu) | where the steward lives |
| OLLAMA_URL / OLLAMA_MODEL | http://100.102.251.35:11434 (the i3) / qwen3:8b | the Mind's model |
| CHORUS_FEED_URL | on the MSI: http://127.0.0.1:8767/feed.json; elsewhere unset (SSH to the MSI) | CHORUS's feed |
| CHORUS_MSI_SSH / CHORUS_MSI_KEY | colony-i3@100.110.22.88 / ~/.ssh/i3_to_msi_ed25519 | the SSH hop to the MSI's CHORUS |
| COLONY_QUARANTINE_QUEUE | K:\quarantine\QUEUE.md | the quarantine queue (missing = skipped) |
| COLONY_RIG | from the hostname: MSI* = msi, *L9* = l9, xanadu = xanadu, else i3 | which rig this is |
"""
import json
import os
import pathlib
import platform
import subprocess
import sys
import urllib.request

# subprocess's creationflags is Windows-only: passing it on Linux raises ValueError.
NO_WINDOW_KW = {'creationflags': 0x08000000} if os.name == 'nt' else {}


def env(name, default):
    v = os.environ.get(name, '').strip()
    return v or default


def rig():
    r = os.environ.get('COLONY_RIG', '').strip().lower()
    if r:
        return r
    node = platform.node().upper()
    if node.startswith('MSI'):
        return 'msi'
    if 'L9' in node:
        return 'l9'
    if node.split('.')[0] == 'XANADU':
        return 'xanadu'
    return 'i3'


def feed_dir(os_name=None):
    if os.environ.get('HOLOMIND_DIR', '').strip():
        return pathlib.Path(os.environ['HOLOMIND_DIR']).expanduser()
    if (os_name or os.name) == 'nt':
        return pathlib.Path(r'C:\Users\Public\colony\mindview')
    base = os.environ.get('XDG_DATA_HOME', '').strip() or str(pathlib.Path.home() / '.local' / 'share')
    return pathlib.Path(base) / 'colony' / 'mindview'


def xanadu():
    return env('XANADU_SSH', 'local' if rig() == 'xanadu' else 'xeno@100.74.243.72')


def xanadu_python(script_b64, timeout_s=10):
    """argv that runs a base64-encoded Python script where the steward lives: over SSH, or here if this is xanadu."""
    host = xanadu()
    if host == 'local':
        return [sys.executable, '-c', f'import base64; exec(base64.b64decode("{script_b64}"))']
    return ['ssh', '-o', 'BatchMode=yes', '-o', f'ConnectTimeout={timeout_s}', host,
            f"python3 -c 'import base64; exec(base64.b64decode(\"{script_b64}\"))'"]


OLLAMA = env('OLLAMA_URL', 'http://100.102.251.35:11434')
MODEL = env('OLLAMA_MODEL', 'qwen3:8b')
QUEUE = pathlib.Path(env('COLONY_QUARANTINE_QUEUE', r'K:\quarantine\QUEUE.md'))


def chorus_feed_url():
    return env('CHORUS_FEED_URL', 'http://127.0.0.1:8767/feed.json' if rig() == 'msi' else '')


def chorus_ssh(timeout_s=8):
    key = pathlib.Path(env('CHORUS_MSI_KEY', str(pathlib.Path.home() / '.ssh' / 'i3_to_msi_ed25519'))).expanduser()
    return ['ssh', '-i', str(key), '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', f'ConnectTimeout={timeout_s}',
            env('CHORUS_MSI_SSH', 'colony-i3@100.110.22.88'), f'curl -s -m {timeout_s} http://127.0.0.1:8767/feed.json']


def chorus_feed(timeout_s=8):
    """The MSI's CHORUS feed as a dict, read-only: straight over HTTP when CHORUS_FEED_URL is set (or on the MSI),
    else through the SSH hop. Raises on failure; callers treat that as 'not measured'."""
    url = chorus_feed_url()
    if url:
        with urllib.request.urlopen(url, timeout=timeout_s) as r:
            return json.loads(r.read().decode('utf-8', 'replace'))
    r = subprocess.run(chorus_ssh(timeout_s), capture_output=True, text=True, encoding='utf-8', timeout=timeout_s * 3 + 6,
                       stdin=subprocess.DEVNULL, **NO_WINDOW_KW)
    return json.loads(r.stdout)
