"""CHORUS must run on any colony rig: the MSI's defaults stay, env vars move them, and Windows-only calls are guarded.

    python -m unittest discover -s chorus/tests      # stdlib only; no SSH, no network
"""
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import actions  # noqa: E402
import doctor  # noqa: E402
import mindview_feed  # noqa: E402
import portable  # noqa: E402

CLEAN = {k: "" for k in ("CHORUS_XANADU", "CHORUS_ROOTS", "COLONY_PY", "COLONY_PYTHON", "CHORUS_I3_SSH", "CHORUS_I3_OLLAMA")}


class Defaults(unittest.TestCase):
    def test_msi_defaults_unchanged(self):
        with mock.patch.dict(os.environ, CLEAN), mock.patch.object(platform, "node", return_value="MSI"):
            self.assertEqual(portable.xanadu_cmd("true"),
                             ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "xanadu", "true"])
            self.assertEqual(portable.roots(), [Path("C:/dev/active"), Path("K:/dev/worktrees")])

    def test_env_overrides(self):
        with mock.patch.dict(os.environ, dict(CLEAN, CHORUS_XANADU="xeno@100.74.243.72",
                                              CHORUS_ROOTS=os.pathsep.join(["/srv/a", "/srv/b"]))):
            self.assertEqual(portable.xanadu_cmd("true")[-2:], ["xeno@100.74.243.72", "true"])
            self.assertEqual(portable.roots(), [Path("/srv/a"), Path("/srv/b")])

    def test_on_xanadu_it_runs_locally(self):
        with mock.patch.dict(os.environ, CLEAN), mock.patch.object(platform, "node", return_value="xanadu"):
            self.assertEqual(portable.xanadu_cmd("true"), ["sh", "-c", "true"])


class Guards(unittest.TestCase):
    def test_scheduled_task_off_windows_says_so_and_runs_nothing(self):
        with mock.patch.object(actions, "WINDOWS", False), mock.patch.object(actions.subprocess, "run") as run:
            ok, msg = actions._run("task", "heartbeat-msi")
        self.assertFalse(ok)
        self.assertIn("Windows-only", msg)
        run.assert_not_called()

    def test_missing_tool_is_a_result_not_a_crash(self):
        with mock.patch.object(actions.subprocess, "run", side_effect=FileNotFoundError("docker")):
            ok, msg = actions._run("restart", "kilocore-dispatch")
        self.assertFalse(ok)
        self.assertIn("could not run", msg)

    def test_msi_docker_probe_skips_powershell_off_windows(self):
        calls = []

        def fake(cmd, **kw):
            calls.append(cmd[0])
            return subprocess.CompletedProcess(cmd, 0, "27.0", "")
        with mock.patch.object(doctor.portable, "WINDOWS", False), mock.patch.object(doctor.subprocess, "run", side_effect=fake):
            res = doctor.msi_docker()
        self.assertNotIn("powershell", calls)
        self.assertIn("n/a", " ".join(res["evidence"]))


@unittest.skipUnless(os.name == "posix" and shutil.which("python3"), "local mode is for the Linux steward host")
class LocalSteward(unittest.TestCase):
    """mindview_feed.fetch's xanadu read, run with CHORUS_XANADU=local against a temp ~/steward."""

    def test_remote_script_reads_a_local_steward(self):
        with tempfile.TemporaryDirectory() as home:
            ev = Path(home, "steward", "events")
            ev.mkdir(parents=True)
            (ev / "2026-11-08.jsonl").write_text(json.dumps({"at": "2026-11-08T06:00:00Z", "mind": "m", "line": "hi"}) + "\n")
            with mock.patch.dict(os.environ, dict(CLEAN, CHORUS_XANADU="local", HOME=home)):
                r = subprocess.run(portable.xanadu_cmd(mindview_feed.REMOTE), capture_output=True, text=True, timeout=60)
            data = json.loads(r.stdout.strip().splitlines()[-1])
        self.assertEqual(data["events"][0]["line"], "hi")
        self.assertIsNone(data["backup"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
