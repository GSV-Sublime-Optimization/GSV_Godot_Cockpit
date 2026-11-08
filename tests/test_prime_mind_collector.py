"""One-shot archive collector negative controls. No real SSH is invoked here."""
from __future__ import annotations
import datetime as dt
import importlib.util
import json
import os
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

    def test_ssh_host_override_keeps_the_same_read(self):
        with patch.dict(os.environ, {"GSV_MINDS_SSH_HOST": "xeno@100.74.243.72"}):
            command = collector._command()
        self.assertEqual(command[-2:], ["xeno@100.74.243.72", "python3 -"])
        self.assertIn("StrictHostKeyChecking=yes", command)

    def test_no_window_flag_only_on_windows(self):
        # creationflags is Windows-only; on Linux subprocess raises ValueError if it is non-zero.
        with tempfile.TemporaryDirectory() as tmp, patch.object(
                collector.subprocess, "run",
                return_value=SimpleNamespace(returncode=255, stdout="", stderr="")) as run:
            with self.assertRaises(RuntimeError):
                collector.collect_once(output=Path(tmp) / "f.json")
        flags = run.call_args.kwargs["creationflags"]
        self.assertEqual(flags != 0, os.name == "nt")

    def test_local_mode_runs_the_read_only_script_on_a_local_archive(self):
        # On the archive host itself (GSV_MINDS_SSH_HOST=local) the same script reads ~/steward directly.
        with tempfile.TemporaryDirectory() as home, tempfile.TemporaryDirectory() as tmp:
            events = Path(home) / "steward" / "events"
            events.mkdir(parents=True)
            (events / "2026-11-08.jsonl").write_text(json.dumps({
                "at": "2026-11-08T06:51:00Z", "mind": "m", "level": "notable", "line": "hi"}) + "\n", encoding="utf-8")
            out = Path(tmp) / "feed.json"
            with patch.dict(os.environ, {"GSV_MINDS_SSH_HOST": "local", "HOME": home, "USERPROFILE": home}):
                result = collector.collect_once(output=out, timeout=60)
            self.assertEqual(result["events"], 1)
            self.assertEqual(json.loads(out.read_text(encoding="utf-8"))["events"][0]["line"], "hi")


if __name__ == "__main__":
    unittest.main()
