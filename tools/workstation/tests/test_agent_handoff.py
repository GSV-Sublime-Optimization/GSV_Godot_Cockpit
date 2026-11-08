"""Safe interoperability tests: no agent can turn a source capsule into a grant."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / "agent_handoff.py"
spec = importlib.util.spec_from_file_location("agent_handoff", MODULE)
handoff = importlib.util.module_from_spec(spec)
spec.loader.exec_module(handoff)


def fixture(kind="project"):
    ref = {
        "kind": kind, "id": "C:/dev/active/Furyline", "repo": "C:/dev/active/Furyline",
        "branch": "main", "title": "Furyline", "state": "observed", "source": "Studio",
        "observed": True, "execution_admitted": False,
    }
    if kind == "mission":
        ref.update(id="msn_012345abcdef", state="awaiting_approval")
    if kind == "capability":
        ref.update(id="serena", observed=False)
    return {
        "schema": handoff.SCHEMA, "resource": ref,
        "authority": {"owner": "KiloCore-Studio", "next_route": (
            "requalify_capability_with_owner" if kind == "capability" else
            "inspect_mission_log_validator_receipt" if kind == "mission" else
            "compose_studio_r0_after_fresh_recheck"),
            "actor_authenticated": False, "permission_granted": False,
            "session_attached": False, "studio_r2_bypassed": False},
        "next_step": "Refresh owning service before acting.",
    }


class CapsuleTest(unittest.TestCase):
    def test_project(self):
        result = handoff.validate(fixture())
        self.assertEqual(result["branch"], "main")
        self.assertIs(result["permission_granted"], False)

    def test_real_mission_not_approval(self):
        result = handoff.validate(fixture("mission"))
        self.assertEqual(result["id"], "msn_012345abcdef")
        self.assertIs(result["execution_admitted"], False)

    def test_static_capability(self):
        result = handoff.validate(fixture("capability"))
        self.assertFalse(result["observed"])

    def test_fake_grant_fails(self):
        row = fixture()
        row["authority"]["permission_granted"] = True
        with self.assertRaisesRegex(ValueError, "false_authority_grant"):
            handoff.validate(row)

    def test_sneaky_project_fails(self):
        row = fixture()
        row["resource"]["repo"] = "C:/dev/active/../secrets"
        with self.assertRaisesRegex(ValueError, "invalid_project"):
            handoff.validate(row)

    def test_fake_live_capability_fails(self):
        row = fixture("capability")
        row["resource"]["observed"] = True
        with self.assertRaisesRegex(ValueError, "false_live_capability"):
            handoff.validate(row)

    def test_unknown_route_fails(self):
        row = fixture()
        row["authority"]["next_route"] = "execute_shell"
        with self.assertRaisesRegex(ValueError, "bad_owner_route"):
            handoff.validate(row)

    def test_file_size_and_valid_import(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "capsule.json"
            path.write_text(json.dumps(fixture()), encoding="utf-8")
            self.assertEqual(handoff.load(path)["kind"], "project")
            path.write_text("x" * (handoff.MAX_BYTES + 1), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "oversized"):
                handoff.load(path)


if __name__ == "__main__":
    unittest.main()
