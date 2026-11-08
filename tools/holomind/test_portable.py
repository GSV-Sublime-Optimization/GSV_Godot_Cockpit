"""Portability tests for HOLOMIND's Python tools: they must run on any colony rig (Windows or Linux).

    python tools/holomind/test_portable.py        # stdlib unittest, no network, no SSH
"""
import base64
import http.server
import importlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import portable  # noqa: E402

CLEAN = {k: '' for k in ('HOLOMIND_DIR', 'XANADU_SSH', 'COLONY_RIG', 'CHORUS_FEED_URL', 'CHORUS_MSI_SSH', 'CHORUS_MSI_KEY',
                         'COCKPIT_ACTIVITY', 'XDG_DATA_HOME')}


class Portable(unittest.TestCase):
    def test_no_window_flag_is_accepted_on_this_os(self):
        # creationflags on Linux raises ValueError; this is the call every feeder subprocess makes.
        r = subprocess.run([sys.executable, '-c', 'print(42)'], capture_output=True, text=True, **portable.NO_WINDOW_KW)
        self.assertEqual(r.stdout.strip(), '42')
        self.assertEqual(bool(portable.NO_WINDOW_KW), os.name == 'nt')

    def test_i3_defaults_unchanged(self):
        with mock.patch.dict(os.environ, dict(CLEAN, COLONY_RIG='i3')):
            self.assertEqual(portable.xanadu(), 'xeno@100.74.243.72')
            self.assertEqual(portable.chorus_feed_url(), '')
            self.assertIn('colony-i3@100.110.22.88', portable.chorus_ssh())
            if os.name == 'nt':
                self.assertEqual(portable.feed_dir(), pathlib.Path(r'C:\Users\Public\colony\mindview'))

    def test_linux_default_dir_is_not_a_windows_path(self):
        with mock.patch.dict(os.environ, dict(CLEAN, XDG_DATA_HOME='/srv/data')):
            self.assertEqual(portable.feed_dir('posix').as_posix(), '/srv/data/colony/mindview')
            self.assertEqual(portable.feed_dir('nt'), pathlib.Path(r'C:\Users\Public\colony\mindview'))

    def test_env_overrides(self):
        with mock.patch.dict(os.environ, dict(CLEAN, HOLOMIND_DIR='~/hm', XANADU_SSH='me@box', COLONY_RIG='l9',
                                              CHORUS_FEED_URL='http://x/feed.json')):
            self.assertEqual(portable.feed_dir(), pathlib.Path('~/hm').expanduser())
            self.assertEqual(portable.xanadu(), 'me@box')
            self.assertEqual(portable.rig(), 'l9')
            self.assertEqual(portable.chorus_feed_url(), 'http://x/feed.json')

    def test_rig_specific_defaults(self):
        with mock.patch.dict(os.environ, dict(CLEAN, COLONY_RIG='xanadu')):
            self.assertEqual(portable.xanadu(), 'local')
        with mock.patch.dict(os.environ, dict(CLEAN, COLONY_RIG='msi')):
            self.assertEqual(portable.chorus_feed_url(), 'http://127.0.0.1:8767/feed.json')
        with mock.patch.dict(os.environ, CLEAN), mock.patch.object(portable.platform, 'node', return_value='DESKTOP-L9V3EMB'):
            self.assertEqual(portable.rig(), 'l9')

    def test_local_xanadu_runs_the_script_here(self):
        b64 = base64.b64encode(b'import json; print(json.dumps({"ok": 1}))').decode()
        with mock.patch.dict(os.environ, dict(CLEAN, XANADU_SSH='local')):
            r = subprocess.run(portable.xanadu_python(b64), capture_output=True, text=True, timeout=30)
        self.assertEqual(json.loads(r.stdout), {'ok': 1})

    def test_chorus_feed_over_http(self):
        body = json.dumps({'spine': {'up': 3, 'total': 4, 'services': []}}).encode()

        class H(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *a):
                pass

        srv = http.server.HTTPServer(('127.0.0.1', 0), H)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            with mock.patch.dict(os.environ, dict(CLEAN, CHORUS_FEED_URL=f'http://127.0.0.1:{srv.server_port}/feed.json')):
                self.assertEqual(portable.chorus_feed(5)['spine']['up'], 3)
        finally:
            srv.shutdown()
            srv.server_close()


class Feeder(unittest.TestCase):
    """cockpit_feed's xanadu read, run locally against a temp ~/steward: the exact code path the i3 runs over SSH."""

    def test_feeder_reads_a_local_steward(self):
        with tempfile.TemporaryDirectory() as home, tempfile.TemporaryDirectory() as out:
            ev = pathlib.Path(home, 'steward', 'events')
            ev.mkdir(parents=True)
            (ev / '2026-11-08.jsonl').write_text(json.dumps({'at': '2026-11-08T06:00:00Z', 'mind': 'm', 'line': 'hi'}) + '\n')
            hb = pathlib.Path(home, 'steward', 'heartbeats')
            hb.mkdir()
            (hb / 'i3.json').write_text(json.dumps({'rig': 'i3', 'green': True}))
            env = dict(CLEAN, XANADU_SSH='local', HOLOMIND_DIR=out, HOME=home, USERPROFILE=home)
            with mock.patch.dict(os.environ, env):
                import cockpit_feed
                cockpit_feed = importlib.reload(cockpit_feed)
                self.assertEqual(cockpit_feed.HERE, pathlib.Path(out))
                got = cockpit_feed.ssh(cockpit_feed.REMOTE, '')
            self.assertEqual(got['events'][0]['line'], 'hi')
            self.assertTrue(got['heartbeats']['i3']['green'])


class Hook(unittest.TestCase):
    def test_seat_activity_writes_under_holomind_dir(self):
        with tempfile.TemporaryDirectory() as out:
            env = dict(os.environ, **dict(CLEAN, HOLOMIND_DIR=out))
            ev = json.dumps({'tool_name': 'Read', 'tool_input': {'file_path': '/a/b/secret.txt'}})
            subprocess.run([sys.executable, str(HERE / 'hooks' / 'seat_activity.py')], input=ev, text=True, env=env, timeout=30)
            rec = json.loads(pathlib.Path(out, 'activity.jsonl').read_text(encoding='utf-8'))
            self.assertEqual(rec['label'], 'secret.txt')


if __name__ == '__main__':
    unittest.main(verbosity=2)
