"""Tests for chorus/studio_bridge.py (fresh, stale, missing rig, xanadu)."""
from __future__ import annotations

import datetime as dt
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import studio_bridge as sb  # noqa: E402

NOW = dt.datetime(2026, 11, 8, 7, 32, tzinfo=dt.timezone.utc)


def hb(rig, age_s, green=True, **extra):
    beat = {
        "schema": "colony.heartbeat/v1", "rig": rig, "green": green,
        "at": (NOW - dt.timedelta(seconds=age_s)).isoformat().replace("+00:00", "Z"),
        "ram_avail_mb": 6433,
        "disks": {"C": {"free_gb": 78.1, "pct_free": 8.4}},
        "checks": [{"name": "docker", "ok": green, "ms": 0, "detail": "x"}],
    }
    beat.update(extra)
    return beat


def feed(**beats):
    return {
        "served_at": NOW.isoformat(),
        "heartbeats": beats,
        "backup": {"set": "2026-11-07", "age_h": 1.9, "in_progress": True},
        "mirror": {"age_h": 1.6, "ok": True, "repos": 75, "failures": 0},
    }


class ConvertTests(unittest.TestCase):
    def test_fresh_heartbeat_maps_to_v0(self):
        out = sb.convert(feed(msi=hb("msi", 10)), now=NOW)
        obs = out["kilo-core-msi"]
        self.assertEqual(obs["schema"], sb.SOURCE_SCHEMA)
        self.assertEqual(obs["entity_id"], sb.ENTITY_ID)
        self.assertEqual(obs["role"], "primary-body")
        o = obs["observation"]
        self.assertEqual(o["kind"], "physical_local_os")
        self.assertEqual(o["captured_at_utc"], "2026-11-08T07:31:50Z")
        self.assertEqual(o["memory_available_bytes"], 6433 * 1024 * 1024)
        self.assertEqual(o["system_volume_free_bytes"], 78_100_000_000)
        self.assertIsNone(o["cpu_logical"])
        self.assertEqual(obs["authority"], {
            "execution": "none", "identity_attested": False,
            "remote_work_admitted": False, "writes_enabled": False})

    def test_stale_heartbeat_keeps_its_real_old_time(self):
        out = sb.convert(feed(i3=hb("i3", 20 * 60, green=False)), now=NOW)
        obs = out["desktop-i3anuvp"]
        self.assertEqual(obs["observation"]["captured_at_utc"], "2026-11-08T07:12:00Z")
        self.assertTrue(obs["bridge"]["heartbeat_stale"])
        self.assertFalse(obs["bridge"]["heartbeat_green"])
        self.assertEqual(obs["bridge"]["failing_checks"], ["docker"])

    def test_missing_rig_and_garbage_are_unknown(self):
        out = sb.convert(feed(msi=hb("msi", 5), l9={"at": "not-a-time"}), now=NOW)
        self.assertIsNone(out["desktop-i3anuvp"])
        self.assertIsNone(out["desktop-l9v3emb"])
        self.assertTrue(all(v is None for v in sb.convert(None, now=NOW).values()))

    def test_observer_only_heartbeat_has_null_resources(self):
        beat = {"schema": "colony.heartbeat/v1", "rig": "l9", "green": True,
                "at": "2026-11-08T07:31:00Z", "observer": "msi (triage drone)", "checks": []}
        o = sb.convert(feed(l9=beat), now=NOW)["desktop-l9v3emb"]["observation"]
        self.assertIsNone(o["memory_available_bytes"])
        self.assertIsNone(o["system_volume_free_bytes"])

    def test_xanadu_dated_by_newest_receipt(self):
        obs = sb.convert(feed(), now=NOW)["imac-xanadu"]
        expected = NOW - dt.timedelta(hours=1.6)
        self.assertEqual(sb._parse_time(obs["observation"]["captured_at_utc"]), expected)
        no_receipts = {"served_at": NOW.isoformat(), "heartbeats": {}}
        self.assertIsNone(sb.convert(no_receipts, now=NOW)["imac-xanadu"])


class WriteTests(unittest.TestCase):
    def test_writes_and_removes_atomically(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            first = sb.write_all(sb.convert(feed(msi=hb("msi", 5), i3=hb("i3", 5)), now=NOW), out_dir)
            self.assertEqual(first["desktop-i3anuvp"], "written")
            data = json.loads((out_dir / "desktop-i3anuvp.json").read_text(encoding="utf-8"))
            self.assertEqual(data["body_id"], "desktop-i3anuvp")
            self.assertLess((out_dir / "desktop-i3anuvp.json").stat().st_size, 8192)
            second = sb.write_all(sb.convert(feed(msi=hb("msi", 5)), now=NOW), out_dir)
            self.assertEqual(second["desktop-i3anuvp"], "removed")
            self.assertFalse((out_dir / "desktop-i3anuvp.json").exists())
            self.assertEqual([p.name for p in out_dir.glob("*.tmp")], [])


class StudioValidatorTests(unittest.TestCase):
    """Cross-check against PR #56's own validator when it is importable."""

    def setUp(self):
        try:
            from kilocore_studio.entity_bodies import project_bodies
        except ImportError:
            self.skipTest("kilocore_studio (PR #56) not on sys.path")
        self.project = project_bodies

    def test_studio_accepts_fresh_flags_stale_unknown_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = feed(msi=hb("msi", 10), i3=hb("i3", 20 * 60))
            sb.write_all(sb.convert(f, now=NOW), Path(tmp))
            got = {b["body_id"]: b for b in self.project(tmp, now=NOW)["bodies"]}
        self.assertEqual(got["kilo-core-msi"]["state"], "reported_fresh")
        self.assertEqual(got["desktop-i3anuvp"]["state"], "stale")
        self.assertEqual(got["desktop-l9v3emb"]["state"], "unknown")
        self.assertEqual(got["imac-xanadu"]["state"], "stale")
        self.assertTrue(all(b["execution_authorized"] is False for b in got.values()))


if __name__ == "__main__":
    unittest.main()
