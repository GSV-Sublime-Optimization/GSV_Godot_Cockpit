"""Offline negative controls: local source discovery is not agent admission."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from collect_tool_atlas import atomic_write, build_snapshot


class ToolAtlasTest(unittest.TestCase):
    def test_presence_vs_directory_and_missing(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "OMNISYNAPSE").mkdir()
            (root / "OMNISYNAPSE" / ".git").mkdir()
            (root / "GSV_Godot_Cockpit").mkdir()
            payload = build_snapshot(root, [], now=1700000000)
            items = {i["id"]: i for i in payload["tools"]}
            self.assertEqual(items["omnisynapse"]["state"], "source_present")
            self.assertEqual(items["gsv-cockpit"]["state"], "directory_seen")
            self.assertEqual(items["kilocore-studio"]["state"], "not_found")
            self.assertNotIn("connected", json.dumps(payload))
            self.assertEqual(payload["observed_at_unix"], 1700000000)

    def test_explicit_extra_and_atomic_output(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            extra = root / "vault"
            extra.mkdir()
            snapshot = build_snapshot(root, [f"obsidian={extra}"], now=1700000000)
            self.assertEqual(snapshot["tools"][-1]["id"], "obsidian")
            output = root / "state" / "atlas.json"
            atomic_write(output, snapshot)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), snapshot)
            atomic_write(output, snapshot)
            self.assertEqual(len(list(output.parent.iterdir())), 1)

    def test_reject_insecure_or_ambiguous_paths(self):
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            for extras in (["bad"], ["OMNISYNAPSE=local"], ["omnisynapse=/" ],
                           ["obsidian=relative"]):
                with self.assertRaises(ValueError):
                    build_snapshot(root, extras)
            with self.assertRaises(ValueError):
                atomic_write(Path("relative.json"), {})


if __name__ == "__main__":
    unittest.main()
