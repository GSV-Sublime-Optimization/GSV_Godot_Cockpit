"""index.html's ago(): a timestamp after the snapshot's "now" must not read as "just now".

The snapshot is frozen at 06:48 UTC but the extras (doctor, MSI Claude's steps, channel) were
captured 07:13-07:51 UTC; before the fix they all rendered as "just now" / "measured just now".
Runs the page's own ago() under node; skipped when node is not installed.
"""
import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

PAGE = Path(__file__).resolve().parents[1] / "index.html"


def _ago_source() -> str:
    m = re.search(r"function ago\(ms\) \{.*?\n\}", PAGE.read_text(encoding="utf-8"), re.S)
    assert m, "ago() not found in index.html"
    return m.group(0)


@unittest.skipUnless(shutil.which("node"), "node not installed")
class AgoTest(unittest.TestCase):
    def run_ago(self, now: str, at: str) -> str:
        js = (f"let nowFn = () => Date.parse({json.dumps(now)});\n{_ago_source()}\n"
              f"process.stdout.write(ago(Date.parse({json.dumps(at)})));")
        return subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout

    def test_past(self):
        self.assertEqual(self.run_ago("2026-11-08T06:48:00Z", "2026-11-08T06:36:20Z"), "12 min ago")

    def test_now(self):
        self.assertEqual(self.run_ago("2026-11-08T06:48:00Z", "2026-11-08T06:47:50Z"), "just now")

    def test_after_snapshot_is_not_just_now(self):
        out = self.run_ago("2026-11-08T06:48:00Z", "2026-11-08T07:51:12Z")
        self.assertNotEqual(out, "just now")
        self.assertEqual(out, "1 h after this snapshot")
        self.assertEqual(self.run_ago("2026-11-08T06:48:00Z", "2026-11-08T07:15:02Z"), "27 min after this snapshot")


if __name__ == "__main__":
    unittest.main()
