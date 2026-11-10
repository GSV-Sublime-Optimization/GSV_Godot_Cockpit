"""Negative controls for the standalone source parser and script inventory."""
import unittest
from pathlib import Path

from cockpit_parse_gate import assess_parse, source_scripts


class SourceParseGateTests(unittest.TestCase):
    def test_real_first_party_scripts_are_discovered_without_editor_plugins(self):
        scripts = source_scripts()
        names = {p.relative_to(Path(__file__).resolve().parents[1]).as_posix() for p in scripts}
        self.assertIn("scripts/Main.gd", names)
        self.assertIn("scripts/entity/EntitySession.gd", names)
        self.assertIn("tests/cockpit_boot_test.gd", names)
        self.assertGreaterEqual(len(scripts), 15)
        self.assertFalse(any(name.endswith(".uid") for name in names))

    def test_clean_checkonly_output_passes(self):
        self.assertTrue(assess_parse(0, "Godot Engine v4.7.1\n"))

    def test_parse_error_with_zero_exit_fails(self):
        self.assertFalse(assess_parse(
            0, "Godot Engine v4.7.1\nSCRIPT ERROR: Parse Error: bad syntax\n"))

    def test_coloured_error_cannot_hide_with_escape_prefix(self):
        self.assertFalse(assess_parse(
            0, "\x1b[31mERROR: Failed to load script\x1b[0m\n"))

    def test_editor_fatal_diagnostic_is_rejected(self):
        self.assertFalse(assess_parse(0, "FATAL: plugin script error\n"))

    def test_nonzero_exit_without_diagnostic_fails(self):
        self.assertFalse(assess_parse(1, "Godot Engine v4.7.1\n"))


if __name__ == "__main__":
    unittest.main()
