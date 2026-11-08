"""One-shot archive collector negative controls. No real SSH is invoked here."""
from __future__ import annotations
import contextlib
import datetime as dt
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

SOURCE = Path(__file__).resolve().parents[1] / "tools" / "prime_mind" / "collect_once.py"
spec = importlib.util.spec_from_file_location("prime_mind_collector", SOURCE)
assert spec and spec.loader
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)

NOW = dt.datetime(2026, 11, 8, 7, 0, tzinfo=dt.timezone.utc)
FIXTURES = Path(__file__).resolve().parent / "fixtures"
WORK_DIR = FIXTURES / "loom-work"
WORK_FEED = FIXTURES / "prime_mind_work_feed.json"
WORK_NOW = dt.datetime(2026, 11, 8, 6, 37, tzinfo=dt.timezone.utc)


def hb(rig, at, green, failing=()):
    return {"schema": "colony.heartbeat/v1", "rig": rig, "at": at, "green": green,
            "checks": [{"name": n, "ok": False} for n in failing]}


class CollectorTests(unittest.TestCase):
    def test_failure_not_fabricated_green(self):
        result = collector.project({}, now=NOW)
        self.assertTrue(result["source_ok"])
        self.assertEqual(result["events"], [])
        self.assertTrue(all(x["status"] == "unknown" for x in result["bodies"].values()))

    def test_true_source_metadata_and_staleness(self):
        data = {
            "events": [{
                "at": "2026-11-08T06:51:00Z", "mind": "l9-triage-drone",
                "model": "qwen3:4b-l9fast", "level": "notable",
                "line": "i3 failing: docker", "focus": "i3",
                "reasons": ["i3 failing: docker"], "simulated": False,
            }, {
                "at": "2026-11-08T06:56:00Z", "mind": "observer",
                "model": None, "level": "calm",
                "line": "i3 rotation waiting", "focus": "i3", "reasons": [],
            }],
            "heartbeats": {
                "i3": {
                    "schema": "colony.heartbeat/v1", "rig": "i3",
                    "at": "2026-11-08T06:59:55Z", "green": False,
                    "checks": [{"name": "docker", "ok": False, "ms": 0}],
                },
                "l9": {
                    "schema": "colony.heartbeat/v1", "rig": "l9",
                    "at": "2026-11-07T21:00:00Z", "green": True,
                }
            }
        }
        output = collector.project(data, now=NOW)
        self.assertEqual(output["bodies"]["i3"]["status"], "red")
        self.assertEqual(output["bodies"]["i3"]["failing"], ["docker"])
        self.assertEqual(output["bodies"]["l9"]["status"], "silent")
        self.assertEqual(output["bodies"]["xanadu"]["status"], "unknown")
        self.assertEqual(len(output["events"]), 2)
        self.assertEqual(output["events"][1]["model"], None)
        self.assertEqual(output["events"][0]["reasons"], ["i3 failing: docker"])

    def test_bad_source_structure_refused(self):
        with self.assertRaises(ValueError):
            collector.project({"events": "not a list"}, now=NOW)

    def test_bad_ssh_does_not_replace_last_known_local_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "latest.json"
            out.write_text("KEEP", encoding="utf-8")
            with patch.object(collector.subprocess, "run",
                              return_value=SimpleNamespace(
                                  returncode=255, stdout="", stderr="unavailable"
                              )) as run:
                with self.assertRaisesRegex(RuntimeError, "unavailable"):
                    collector.collect_once(output=out)
                self.assertEqual(out.read_text(encoding="utf-8"), "KEEP")
                command = run.call_args.args[0]
                self.assertEqual(command[-2:], ["xanadu", "python3 -"])
                self.assertIn("BatchMode=yes", command)

    def test_realistic_mock_one_ssh_call_and_atomic_local_file(self):
        blob = json.dumps({"events": [], "heartbeats": {}})
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "feed.json"
            with patch.object(collector.subprocess, "run",
                              return_value=SimpleNamespace(
                                  returncode=0, stdout=blob, stderr=""
                              )) as run:
                result = collector.collect_once(output=out)
            self.assertEqual(run.call_count, 1)
            self.assertTrue(result["source_ok"])
            self.assertEqual(json.loads(out.read_text())["schema"], collector.SCHEMA)
            self.assertFalse(any(Path(tmp).glob(".prime-mind-*.tmp")))

    def test_local_archive_copy_uses_shared_fixture_layout_without_ssh(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "events.jsonl").write_text(
                json.dumps({"at": "2026-11-08T06:16:16+00:00", "mind": "l9-triage-drone",
                            "model": "qwen3:4b-l9fast", "level": "notable",
                            "reasons": ["i3 failing: docker"], "line": "i3 failing: docker",
                            "focus": "i3"}) + "\nnot json\n", encoding="utf-8")
            (root / "heartbeat_i3.json").write_text(json.dumps({
                "schema": "colony.heartbeat/v1", "rig": "i3", "at": "2026-11-08T06:46:42Z",
                "green": False, "checks": [{"name": "docker", "ok": False}]}), encoding="utf-8")
            out = root / "out" / "feed.json"
            with patch.object(collector.subprocess, "run") as run:
                rc = collector.main(["--output", str(out), "--from-dir", str(root),
                                     "--now", "2026-11-08T06:47:00Z"])
            run.assert_not_called()
            self.assertEqual(rc, 0)
            feed = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(len(feed["events"]), 1)
            self.assertEqual(feed["at"], "2026-11-08T06:47:00Z")
            self.assertEqual(feed["bodies"]["i3"]["status"], "red")
            self.assertEqual(feed["bodies"]["i3"]["failing"], ["docker"])
            self.assertEqual(feed["bodies"]["msi"]["status"], "unknown")
            self.assertNotIn("SSH", feed["bodies"]["xanadu"]["detail"])

    def test_actual_shared_fixture_when_present(self):
        shared = Path(__file__).resolve().parent / "fixtures" / "mindview-20261108"
        if not shared.is_dir():
            self.skipTest("shared #14 fixture not on this branch (lives on PR #16)")
        feed = collector.project(collector.read_local_archive(shared),
                                 now=dt.datetime(2026, 11, 8, 6, 47, tzinfo=dt.timezone.utc))
        self.assertEqual(len(feed["events"]), 4)
        self.assertEqual(feed["bodies"]["i3"]["status"], "red")


class WorkTapeTests(unittest.TestCase):
    """Orders, receipts, decisions and rig changes: the colony's work on the tape."""

    def work_feed(self):
        return collector.project(collector.read_local_archive(WORK_DIR), now=WORK_NOW,
                                 xanadu_detail=collector.XANADU_LOCAL_NOTE)

    def test_fixture_projects_work_kinds_apart_from_thoughts(self):
        feed = self.work_feed()
        self.assertEqual(len(feed["events"]), 13)
        kinds = [w["kind"] for w in feed["work"]]
        self.assertEqual({k: kinds.count(k) for k in set(kinds)},
                         {"order": 3, "order-status": 7, "decision": 1, "rig-change": 5})
        # Work never leaks into thought events, and no work line looks like a thought.
        self.assertTrue(all("kind" not in e for e in feed["events"]))
        self.assertTrue(all("mind" not in w and "model" not in w for w in feed["work"]))
        self.assertEqual([w["at"] for w in feed["work"]], sorted(w["at"] for w in feed["work"]))
        self.assertTrue(all(collector.work_problem(w) is None for w in feed["work"]))

    def test_committed_work_feed_matches_the_fixture_dir(self):
        """The Godot tests read prime_mind_work_feed.json; it must be exactly what
        collect_once.py --from-dir tests/fixtures/loom-work --now 06:37Z writes."""
        committed = json.loads(WORK_FEED.read_text(encoding="utf-8"))
        regenerated = self.work_feed()
        self.assertEqual(committed, json.loads(json.dumps(regenerated)))

    def test_chat_and_malformed_channel_lines_are_not_work(self):
        work = collector.project_channel([
            {"at": "2026-11-08T06:00:00Z", "from": "op", "to": "all", "text": "hello"},
            {"at": "2026-11-08T06:00:00Z", "kind": "read", "from": "op"},
            {"at": "2026-11-08T06:00:00Z", "kind": "suggestion", "from": "op", "text": "x"},
            {"at": "2026-11-08T06:00:00Z", "kind": "order", "from": "op", "text": "no id"},
            {"at": "2026-11-08T06:00:00", "kind": "order", "id": "o1", "from": "op", "text": "naive time"},
            {"at": "2026-11-08T06:00:00Z", "kind": "order", "id": "o1", "text": "no author"},
            {"at": "2026-11-08T06:00:00Z", "kind": "order-status", "id": "o1", "from": "a",
             "status": "approved-by-root"},
            {"at": "2026-11-08T06:00:00Z", "kind": "decision", "from": "op", "card": "c",
             "verdict": "rm -rf"},
            "not a dict",
        ])
        self.assertEqual(work, [])

    def test_receipt_is_reported_unless_https_link(self):
        work = collector.project_channel([
            {"at": "2026-11-08T06:00:00Z", "kind": "order", "id": "o1", "from": "op", "to": "bot",
             "text": "do it"},
            {"at": "2026-11-08T06:01:00Z", "kind": "order-status", "id": "o1", "from": "bot",
             "status": "done", "note": "did it"},
            {"at": "2026-11-08T06:02:00Z", "kind": "order-status", "id": "o1", "from": "bot",
             "status": "done", "link": "javascript:alert(1)"},
            {"at": "2026-11-08T06:03:00Z", "kind": "order-status", "id": "o1", "from": "bot",
             "status": "done", "link": "http://example.com/plain-http"},
            {"at": "2026-11-08T06:04:00Z", "kind": "order-status", "id": "o1", "from": "bot",
             "status": "done", "link": "https://github.com/o/r/pull/1"},
        ])
        self.assertEqual([collector.receipt_state(w) for w in work],
                         ["", "reported", "reported", "reported", "linked"])
        self.assertEqual(work[1]["to"], "op")          # a receipt answers whoever posted the order
        self.assertEqual(work[1]["text"], "do it")
        self.assertNotIn("verified", json.dumps(work))

    def test_rig_changes_only_between_observed_heartbeats(self):
        changes = collector.rig_changes({
            "i3": [collector.heartbeat_state(hb("i3", "2026-11-08T06:00:00Z", True), "i3"),
                   collector.heartbeat_state(hb("i3", "2026-11-08T06:05:00Z", True), "i3"),
                   collector.heartbeat_state(hb("i3", "2026-11-08T06:40:00Z", False, ["docker"]), "i3")],
            "l9": [collector.heartbeat_state(hb("l9", "2026-11-08T06:00:00Z", True), "l9"),
                   collector.heartbeat_state(hb("l9", "2026-11-08T07:00:00Z", True), "l9")],
        })
        self.assertEqual(len(changes), 1)                # a long gap alone is not an event
        change = changes[0]
        self.assertEqual((change["rig"], change["prev_status"], change["status"]), ("i3", "green", "red"))
        self.assertIn("now failing: docker", change["note"])
        self.assertIn("35 min earlier", change["note"])
        self.assertIsNone(collector.heartbeat_state(hb("msi", "2026-11-08T06:00:00Z", True), "i3"))

    def test_consecutive_heartbeats_across_collections_via_previous_feed(self):
        first = collector.project({"heartbeats": {"msi": hb("msi", "2026-11-08T06:00:00Z", True)}},
                                  now=NOW)
        self.assertEqual(first["work"], [])
        second = collector.project(
            {"heartbeats": {"msi": hb("msi", "2026-11-08T06:10:00Z", False, ["dev-mentor"])}},
            now=NOW, previous=json.loads(json.dumps(first)))
        self.assertEqual([(w["kind"], w["status"]) for w in second["work"]], [("rig-change", "red")])
        third = collector.project(
            {"heartbeats": {"msi": hb("msi", "2026-11-08T06:20:00Z", False, ["dev-mentor"])}},
            now=NOW, previous=json.loads(json.dumps(second)))
        self.assertEqual(len(third["work"]), 1)          # carried forward, not duplicated

    def test_work_is_bounded(self):
        lines = [{"at": "2026-11-08T06:00:%02dZ" % (i % 60), "kind": "order", "id": f"o{i}",
                  "from": "op", "text": "y" * 2000} for i in range(500)]
        feed = collector.project({"channel": lines}, now=NOW)
        self.assertLessEqual(len(feed["work"]), collector.MAX_WORK)
        self.assertTrue(all(len(w["text"]) <= 280 for w in feed["work"]))
        self.assertLessEqual(len(json.dumps(feed).encode("utf-8")), collector.MAX_RESPONSE_BYTES)

    def test_work_problem_rejects_what_feedcontract_rejects(self):
        good = self.work_feed()["work"][0]
        self.assertIsNone(collector.work_problem(good))
        for change in ({"status": "hacked"}, {"kind": "shell"}, {"link": "javascript:x"},
                       {"at": "yesterday"}, {"rig": "i3"}, {"note": "x" * 281}):
            self.assertIsNotNone(collector.work_problem(dict(good, **change)), change)
        self.assertIsNotNone(collector.work_problem(dict(good, verified=True)))

    def test_export_json_lines_between_two_instants(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()), \
                patch.object(collector.subprocess, "run") as run:
            rc = collector.main(["--export-json", "--from-dir", str(WORK_DIR),
                                 "--now", "2026-11-08T06:37:00Z",
                                 "--since", "2026-11-08T06:20:00Z", "--until", "2026-11-08T06:31:00Z"])
        run.assert_not_called()
        self.assertEqual(rc, 0)
        rows = [json.loads(line) for line in out.getvalue().splitlines()]
        self.assertTrue(rows)
        self.assertTrue(all("2026-11-08T06:20:00Z" <= r["t"] <= "2026-11-08T06:31:00Z" for r in rows))
        self.assertEqual([r["t"] for r in rows], sorted(r["t"] for r in rows))
        self.assertEqual({r["lane"] for r in rows}, {"model", "observer", "work"})
        self.assertEqual([r["id"] for r in rows if r.get("receipt") == "linked"], ["o-202"])
        declined = [r for r in rows if r.get("status") == "declined"]
        self.assertEqual(declined[0]["from"], "codex-l9")

    def test_export_from_existing_feed_file_and_bad_feed_refused(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            rc = collector.main(["--export-json", "--feed", str(WORK_FEED)])
        self.assertEqual(rc, 0)
        self.assertEqual(len(out.getvalue().splitlines()), 29)
        with tempfile.TemporaryDirectory() as tmp:
            bad = json.loads(WORK_FEED.read_text(encoding="utf-8"))
            bad["work"][0]["status"] = "hacked"
            path = Path(tmp) / "bad.json"
            path.write_text(json.dumps(bad), encoding="utf-8")
            err = io.StringIO()
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
                rc = collector.main(["--export-json", "--feed", str(path)])
            self.assertEqual(rc, 2)
            self.assertIn("work_status", err.getvalue())

    def test_output_still_required_without_export(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            collector.main(["--from-dir", str(WORK_DIR)])

    def test_remote_script_reads_only_the_channel_tail(self):
        self.assertIn('"cockpit" / "channel.jsonl"', collector.REMOTE_SCRIPT)
        self.assertIn("size - 262144", collector.REMOTE_SCRIPT)
        self.assertIn('("order", "order-status", "decision")', collector.REMOTE_SCRIPT)


if __name__ == "__main__":
    unittest.main()
