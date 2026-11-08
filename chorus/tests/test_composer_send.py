"""The feeder's /route and /send: /route never writes; /send keeps the POST guards and the allowlist,
records every send in the channel, and reports a local model's failure instead of swallowing it.
No test reaches xanadu, GitHub or a model: the channel writer and the HTTP call are replaced."""
import functools
import http.server
import json
import subprocess
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mindview_feed as feed  # noqa: E402
from shop import orders  # noqa: E402


class ComposerTest(unittest.TestCase):
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

    def setUp(self):
        self.lines = []
        self._orig = (feed._append, feed._post_json, feed.current_feed, subprocess.run)
        feed._append = self.lines.append
        feed.current_feed = lambda: {"smiths": [], "channel": []}

        def no_gh(*a, **k):
            raise AssertionError("no subprocess may run in these tests")
        feed.subprocess.run = no_gh

    def tearDown(self):
        feed._append, feed._post_json, feed.current_feed, subprocess.run = self._orig
        feed.subprocess.run = self._orig[3]

    def post(self, path, body, headers=None):
        hdr = {"Content-Type": "application/json", **(headers or {})}
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", data=json.dumps(body).encode(),
                                     method="POST", headers=hdr)
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                return e.code, json.loads(raw)
            except ValueError:
                return e.code, {}

    # ---------------------------------------------------------------- /route
    def test_route_has_no_side_effects(self):
        code, j = self.post("/route", {"text": "", "node": {"kind": "check", "rig": "i3", "check": "docker", "ok": False}})
        self.assertEqual(code, 200)
        self.assertEqual(j["message"]["to"], "claude (i3 seat)")
        self.assertEqual(self.lines, [])

    def test_route_refuses_cross_origin(self):
        code, _ = self.post("/route", {"text": "hi"}, {"Origin": "http://evil.example"})
        self.assertEqual(code, 403)

    # ---------------------------------------------------------------- /send guards and allowlist
    def test_send_refuses_cross_origin_and_text_plain(self):
        body = {"kind": "ask", "to": "claude (msi seat)", "where": "channel", "text": "hi"}
        self.assertEqual(self.post("/send", body, {"Origin": "http://evil.example"})[0], 403)
        self.assertEqual(self.post("/send", body, {"Content-Type": "text/plain"})[0], 403)
        self.assertEqual(self.lines, [])

    def test_send_refuses_unknown_target_and_wrong_where(self):
        self.assertEqual(self.post("/send", {"kind": "ask", "to": "root", "text": "x"})[0], 400)
        self.assertEqual(self.post("/send", {"kind": "ask", "to": "local:msi", "where": "channel", "text": "x"})[0], 400)
        self.assertEqual(self.post("/send", {"kind": "launch", "to": "all", "text": "x"})[0], 400)
        self.assertEqual(self.lines, [])

    def test_action_order_off_the_allowlist_is_refused(self):
        code, j = self.post("/send", {"kind": "action-order", "to": "claude (msi seat)", "where": "channel", "text": "wipe",
                                      "action": "restart", "target": "postgres-prod"})
        self.assertEqual(code, 400)
        self.assertIn("allowlist", j["error"])
        self.assertEqual(self.lines, [])

    def test_action_order_from_an_agent_is_refused(self):
        code, _ = self.post("/send", {"kind": "action-order", "to": "claude (msi seat)", "text": "re-measure",
                                      "action": "doctor", "target": "all", "from": "claude (i3 seat)"})
        self.assertEqual(code, 400)
        self.assertEqual(self.lines, [])

    # ---------------------------------------------------------------- /send dispatch
    def test_order_keeps_due_and_why_through_the_fold(self):
        code, j = self.post("/send", {"kind": "order", "to": "claude (i3 seat)", "where": "channel", "text": "enable VT-x",
                                      "due": "after:#424", "why": "docker is failing (doctor: VT-x off)"})
        self.assertEqual(code, 200, j)
        (line,) = self.lines
        self.assertEqual((line["kind"], line["to"], line["due"]), ("order", "claude (i3 seat)", "after:#424"))
        o = orders(self.lines)[0]
        self.assertEqual((o["due"], o["why"]), ("after:#424", "docker is failing (doctor: VT-x off)"))

    def test_question_to_all_is_one_channel_line(self):
        code, _ = self.post("/send", {"kind": "status", "to": "all", "text": "backup running"})
        self.assertEqual(code, 200)
        self.assertEqual([(m["to"], m["intent"], m["from"]) for m in self.lines], [("all", "status", "keath (chorus)")])

    def test_github_is_prepared_not_sent_by_default(self):
        node = {"kind": "pr", "repo": "dev", "number": 429, "url": "https://github.com/GSV-Sublime-Optimization/dev/pull/429"}
        code, j = self.post("/send", {"kind": "review-request", "to": "gpt6", "where": "github", "text": "review @everyone",
                                      "node": node})
        self.assertEqual(code, 200, j)
        res = j["message"]
        self.assertFalse(res["delivered"])
        self.assertIn("gh pr comment https://github.com/GSV-Sublime-Optimization/dev/pull/429", res["prepared"]["command"])
        self.assertNotIn("@", res["prepared"]["body"])                      # never pings anyone
        self.assertEqual(self.lines[0]["kind"], "sent")                     # the ledger shows it

    def test_github_refuses_a_foreign_url(self):
        node = {"kind": "pr", "url": "https://github.com/someone/else/pull/1"}
        code, _ = self.post("/send", {"kind": "review-request", "to": "codex", "where": "github", "text": "x", "node": node})
        self.assertEqual(code, 400)

    def test_studio_is_only_a_prepared_payload(self):
        code, j = self.post("/send", {"kind": "order", "to": "studio", "where": "studio", "text": "build the thing"})
        self.assertEqual(code, 200)
        self.assertFalse(j["message"]["delivered"])
        self.assertEqual(j["message"]["prepared"]["body"]["posted_by"], "chorus")

    def test_local_model_answer_is_returned_and_recorded(self):
        feed._post_json = lambda url, payload, headers, timeout: {"choices": [{"message": {"content": "<think>x</think>Four."}}]}
        code, j = self.post("/send", {"kind": "ask", "to": "local:l9", "where": "local", "text": "2+2?"})
        self.assertEqual(code, 200)
        self.assertEqual(j["message"]["answer"], "Four.")
        self.assertEqual((self.lines[0]["kind"], self.lines[0]["ok"]), ("local-ask", True))

    def test_local_model_failure_is_reported_not_swallowed(self):
        def down(*a, **k):
            raise urllib.error.URLError("connection refused")
        feed._post_json = down
        code, j = self.post("/send", {"kind": "ask", "to": "local:msi", "where": "local", "text": "summarize"})
        self.assertEqual(code, 400)
        self.assertFalse(j["ok"])
        self.assertIn("did not answer", j["error"])
        self.assertIn("connection refused", j["error"])
        self.assertEqual((self.lines[0]["kind"], self.lines[0]["ok"]), ("local-ask", False))


if __name__ == "__main__":
    unittest.main()
