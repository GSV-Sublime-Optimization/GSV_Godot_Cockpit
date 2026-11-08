"""The feeder's POST endpoints (/say, /order, /act) must refuse cross-site requests.

Reproduction before the fix: a text/plain POST with Origin http://evil.example to /act returned
{"ok": true, "message": {"token": ...}} and /say or /order would append to xanadu's channel signed
"keath (chorus)" (which chorus_inbox.py then hands to the MSI Claude as Keath's words).
Only /act's propose step is exercised here: it is in-memory and touches no host.
"""
import functools
import http.server
import json
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mindview_feed as feed  # noqa: E402


class PostGuardTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        h = functools.partial(feed.Handler, directory=str(feed.HERE))
        cls.srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), h)
        cls.port = cls.srv.server_address[1]
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def post(self, headers: dict) -> int:
        body = json.dumps({"action": "doctor", "target": "all"}).encode()
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}/act", data=body, method="POST", headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status
        except urllib.error.HTTPError as e:
            return e.code

    def test_cross_origin_simple_post_refused(self):
        self.assertEqual(self.post({"Origin": "http://evil.example", "Content-Type": "text/plain"}), 403)

    def test_cross_origin_json_refused(self):
        self.assertEqual(self.post({"Origin": "http://evil.example", "Content-Type": "application/json"}), 403)

    def test_text_plain_without_origin_refused(self):
        self.assertEqual(self.post({"Content-Type": "text/plain"}), 403)

    def test_rebound_host_refused(self):
        self.assertEqual(self.post({"Host": f"attacker.example:{self.port}", "Content-Type": "application/json"}), 403)

    def test_same_origin_page_allowed(self):
        self.assertEqual(self.post({"Origin": f"http://127.0.0.1:{self.port}", "Content-Type": "application/json"}), 200)

    def test_local_tool_without_origin_allowed(self):
        self.assertEqual(self.post({"Content-Type": "application/json"}), 200)


if __name__ == "__main__":
    unittest.main()
