"""Regression tests for the strict Godot smoke log gate."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from godot_smoke_gate import CASES, assess, isolated_env


class GodotSmokeLogGateTests(unittest.TestCase):
    def test_godot_exit_zero_and_pass_banner_are_not_sufficient(self):
        result = assess(0, "[boot-test] PASS\nSCRIPT ERROR: Invalid call\n", "[boot-test] PASS")
        self.assertFalse(result["passed"])
        self.assertEqual(len(result["engine_errors"]), 1)

    def test_engine_error_in_offline_json_path_is_rejected(self):
        result = assess(0, "[boot-test] PASS\nERROR: Parse JSON failed.\n", "[boot-test] PASS")
        self.assertFalse(result["passed"])

    def test_import_exit_zero_with_fontconfig_errors_is_rejected(self):
        result = assess(0, "Godot Engine v4.7\nERROR: Unable to load fontconfig\n", "Godot Engine v")
        self.assertFalse(result["passed"])

    def test_nonzero_exit_is_rejected_even_without_errors(self):
        self.assertFalse(assess(2, "[boot-test] PASS", "[boot-test] PASS")["passed"])

    def test_verified_clean_boot_passes(self):
        self.assertTrue(assess(0, "[boot-test] PASS\n", "[boot-test] PASS")["passed"])

    def test_portable_partial_pass_is_not_final_pass(self):
        result = assess(0, "[portable-test] PASS: receipt displayed\n", "[portable-test] PASS")
        self.assertFalse(result["passed"])
        self.assertFalse(result["marker_seen"])

    def test_whole_line_final_portable_pass_is_accepted(self):
        self.assertTrue(assess(0, "[portable-test] PASS: detail\n[portable-test] PASS\n",
                               "[portable-test] PASS")["passed"])

    def test_all_offline_entity_projection_scopes_are_in_the_real_gate(self):
        checked = [case[1] for case in CASES]
        for required in (
            "res://tests/entity_session_test.gd",
            "res://tests/fleet_body_projection_test.gd",
            "res://tests/entity_observation_console_test.gd",
            "res://tests/studio_entity_bridge_test.gd",
        ):
            with self.subTest(scene=required):
                self.assertIn(required, checked)
        for forbidden in (
            "res://tests/entity_scene_live_test.gd",
            "res://tests/entity_four_bodies_live_test.gd",
            "res://tests/entity_observation_console_live_test.gd",
        ):
            self.assertNotIn(forbidden, checked)

    def test_ansi_coloured_script_error_cannot_hide_behind_pass(self):
        report = assess(0, "[boot-test] PASS\n\x1b[31mSCRIPT ERROR: Invalid call\x1b[0m\n", "[boot-test] PASS")
        self.assertFalse(report["passed"])
        self.assertEqual(len(report["engine_errors"]), 1)

    def test_bare_success_substring_in_a_log_is_not_a_real_pass(self):
        self.assertFalse(assess(0, "not really ENTITY_SESSION_PASS yet\n",
                                "ENTITY_SESSION_PASS")["passed"])

    def test_duplicate_positive_sentinels_fail_closed(self):
        self.assertFalse(assess(0, "ENTITY_SESSION_PASS\nENTITY_SESSION_PASS\n",
                                "ENTITY_SESSION_PASS")["passed"])

    def test_import_banner_prefix_still_works_once(self):
        self.assertTrue(assess(0, "Godot Engine v4.7.1.stable.official\n",
                               "Godot Engine v")["passed"])

    def test_offline_runner_strips_local_live_studio_opt_in(self):
        result = isolated_env({
            "GSV_STUDIO_LIVE": "1",
            "GSV_STUDIO_ENTITY_PORT": "7340",
            "GSV_KILOCORE_REPORTS_DIR": "/my-safe-local-fixture",
        })
        self.assertEqual(result["GSV_STUDIO_LIVE"], "0")
        self.assertNotIn("GSV_STUDIO_ENTITY_PORT", result)
        self.assertEqual(result["GSV_KILOCORE_REPORTS_DIR"], "/my-safe-local-fixture")

    def test_offline_runner_does_not_mutate_callers_environment(self):
        original = {"GSV_STUDIO_LIVE": "1", "GSV_STUDIO_ENTITY_PORT": "7340"}
        result = isolated_env(original)
        self.assertEqual(original["GSV_STUDIO_LIVE"], "1")
        self.assertEqual(original["GSV_STUDIO_ENTITY_PORT"], "7340")
        self.assertEqual(result["GSV_STUDIO_LIVE"], "0")
        self.assertNotIn("GSV_STUDIO_ENTITY_PORT", result)

    def test_build_contract_pins_engine_for_every_phase(self):
        manifest = (Path(__file__).resolve().parents[1] / ".gsv" / "build.yaml").read_text(
            encoding="utf-8"
        )
        self.assertIn('godot: "4.7"', manifest)
        self.assertIn("${godot} --headless --audio-driver Dummy --path . --import", manifest)
        self.assertIn("godot_parse_gate.py --project . --godot ${godot}", manifest)
        self.assertIn("godot_smoke_gate.py --godot ${godot} --project .", manifest)


if __name__ == "__main__":
    unittest.main()
