"""Regression tests for the strict Godot smoke log gate."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from godot_smoke_gate import assess


class GodotSmokeLogGateTests(unittest.TestCase):
    def test_godot_exit_zero_and_pass_banner_are_not_sufficient(self):
        result = assess(0, "[boot-test] PASS\nSCRIPT ERROR: Invalid call\n", "[boot-test] PASS")
        self.assertFalse(result["passed"])
        self.assertEqual(len(result["engine_errors"]), 1)

    def test_engine_error_in_offline_json_path_is_rejected(self):
        result = assess(0, "[boot-test] PASS\nERROR: Parse JSON failed.\n", "[boot-test] PASS")
        self.assertFalse(result["passed"])

    def test_nonzero_exit_is_rejected_even_without_errors(self):
        self.assertFalse(assess(2, "[boot-test] PASS", "[boot-test] PASS")["passed"])

    def test_verified_clean_boot_passes(self):
        self.assertTrue(assess(0, "[boot-test] PASS\n", "[boot-test] PASS")["passed"])


if __name__ == "__main__":
    unittest.main()
