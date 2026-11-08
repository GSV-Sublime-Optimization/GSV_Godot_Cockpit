"""Regression tests for the strict Godot smoke log gate."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import struct
import zlib

from godot_smoke_gate import CASES, MIN_SHOT_BYTES, assess, assess_shot, png_size


def _png(width: int, height: int, pad: int = 0) -> bytes:
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    chunk = b"IHDR" + ihdr
    body = struct.pack(">I", len(ihdr)) + chunk + struct.pack(">I", zlib.crc32(chunk))
    return b"\x89PNG\r\n\x1a\n" + body + b"\0" * pad


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

    def test_war_room_case_is_gated(self):
        names = [name for name, _, _ in CASES]
        self.assertIn("war-room", names)


class WarRoomShotGateTests(unittest.TestCase):
    OK = "[holo-shot] wrote C:/x/room.png\n"

    def test_png_size_reads_ihdr(self):
        self.assertEqual(png_size(_png(1280, 720)), (1280, 720))
        self.assertIsNone(png_size(b"not a png at all, not even close"))

    def test_real_render_passes(self):
        result = assess_shot(0, self.OK, _png(1280, 720, MIN_SHOT_BYTES))
        self.assertTrue(result["passed"])
        self.assertEqual(result["png_size"], [1280, 720])

    def test_missing_png_is_rejected(self):
        self.assertFalse(assess_shot(0, self.OK, None)["passed"])

    def test_tiny_png_is_rejected(self):
        # A blank/truncated render is not proof the room drew anything.
        self.assertFalse(assess_shot(0, self.OK, _png(1280, 720))["passed"])

    def test_headless_refusal_is_rejected(self):
        out = "[holo-shot] FAIL: no renderer (headless)\n"
        self.assertFalse(assess_shot(2, out, None)["passed"])

    def test_engine_error_during_render_is_rejected(self):
        out = self.OK + "SCRIPT ERROR: Invalid call\n"
        self.assertFalse(assess_shot(0, out, _png(1280, 720, MIN_SHOT_BYTES))["passed"])


if __name__ == "__main__":
    unittest.main()
