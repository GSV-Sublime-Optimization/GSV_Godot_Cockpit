"""Owner re-observation: require real source identity, bounded fields and no false success."""
import importlib.util
from pathlib import Path
import unittest

BASE = Path(__file__).resolve().parents[1]


def load_module(name: str):
    spec = importlib.util.spec_from_file_location(name, BASE / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


handoff = load_module("agent_handoff")
obs = load_module("studio_reobserve")
MID = "msn_012345abcdef"
REPO = "C:/dev/active/Furyline"


def source(kind: str, **more):
    base = {"kind": kind, "id": MID if kind == "mission" else REPO,
            "state": "running", "repo": REPO}
    base.update(more)
    return base


def mission(**overrides):
    return {
        "id": MID, "status": "succeeded", "risk": "R0", "repo": REPO,
        "updated_at": "2026-11-08T15:00:00Z",
        "review": False, "mergeable": False, "needs_approval": False,
        "result": {
            "exit_code": 0, "receipt_id": "rcpt_0123456789abcdef",
            "validator": None,
            "report": {"raw_ok": True, "acceptance": [
                {"criterion": "one", "met": True},
                {"criterion": "two", "met": True}
            ]},
            "commits": [], "changed_paths": []
        }, **overrides
    }


class OwnerProof(unittest.TestCase):
    def test_live_report_is_not_an_artifact(self):
        calls = []
        def reader(path):
            calls.append(path)
            return mission()
        result = obs.observe(source("mission"), reader)
        self.assertEqual(calls, ["/api/missions/" + MID])
        self.assertTrue(result["fetched_from_owner"])
        self.assertEqual(result["receipt_id"], "rcpt_0123456789abcdef")
        self.assertTrue(result["runner_exit_zero"])
        self.assertEqual(result["report"], "REPORTED")
        self.assertEqual(result["acceptance_met"], 2)
        self.assertEqual(result["validator"], "NOT_REPORTED")
        self.assertFalse(result["artifact_verified"])
        self.assertTrue(result["lifecycle_changed_since_capsule"])
        self.assertNotIn("summary", result)
        self.assertNotIn("notes", result)

    def test_validator_proof_not_merge_permission(self):
        row = mission()
        row["risk"] = "R2"
        row["review"] = True
        row["mergeable"] = True
        row["result"]["validator"] = {"exit_code": 0, "timed_out": False}
        result = obs.observe(source("mission"), lambda _: row)
        self.assertEqual(result["validator"], "PASS")
        self.assertTrue(result["mergeable_flag"])
        self.assertFalse(result["merge_performed"])
        self.assertFalse(result["approval_granted"])
        self.assertFalse(result["artifact_verified"])

    def test_wrong_id_fails(self):
        with self.assertRaisesRegex(ValueError, "mission_identity_changed"):
            obs.observe(source("mission"), lambda _: mission(id="msn_aaaaaaaaaaaa"))

    def test_repo_drift_fails(self):
        with self.assertRaisesRegex(ValueError, "mission_repo_drift"):
            obs.observe(source("mission"), lambda _: mission(repo="C:/dev/active/other"))

    def test_bad_acceptance_fails(self):
        row = mission()
        row["result"]["report"]["acceptance"] = [{"met": "yes"}]
        with self.assertRaisesRegex(ValueError, "invalid_acceptance_entry"):
            obs.observe(source("mission"), lambda _: row)

    def test_invalid_validator_fails(self):
        row = mission()
        row["result"]["validator"] = {"exit_code": "0", "timed_out": False}
        with self.assertRaisesRegex(ValueError, "invalid_validator"):
            obs.observe(source("mission"), lambda _: row)

    def test_only_canonical_projects_enable_composer(self):
        exact = source("project", id=REPO, branch="main")
        good = {"schema": obs.PROJECT_SCHEMA, "state": "OBSERVED",
                "projects": [{"path": REPO, "git": {"is_repo": True, "branch": "main"}}]}
        proof = obs.observe(exact, lambda _: good)
        self.assertTrue(proof["ready_for_composer"])
        self.assertTrue(proof["qualified_exact_repo_and_branch"])
        self.assertFalse(proof["execution_admitted"])
        bad = dict(good, state="UNKNOWN", reason="untrusted_exception")
        proof = obs.observe(exact, lambda _: bad)
        self.assertFalse(proof["ready_for_composer"])
        self.assertEqual(proof["reason"], "owner_project_discovery_unavailable")
        self.assertNotIn("untrusted_exception", str(proof))
        bad = dict(good, projects=[{"path": REPO, "git": {
            "is_repo": True, "branch": "another-branch"}}])
        self.assertEqual(obs.observe(exact, lambda _: bad)["reason"], "branch_changed")

    def test_different_source_does_not_mint_capability(self):
        result = obs.observe(source("capability", id="Serena"), lambda _: (
            self.fail("capability file must not invoke a made-up provider")))
        self.assertEqual(result["state"], "REQUIRES_LIVE_PROBE")
        self.assertFalse(result["fetched_from_owner"])
        self.assertFalse(result["execution_admitted"])

    def test_body_gives_no_rights(self):
        item = {"body_id": "kilo-core-msi", "state": "reported_fresh",
                "identity_attested": False, "execution_authorized": False,
                "remote_work_admitted": False}
        data = {"schema": obs.BODY_SCHEMA, "bodies": [item] + [
            {"body_id": n, "state": "unknown"} for n in ("desktop-i3anuvp",
                                                           "desktop-l9v3emb",
                                                           "imac-xanadu")]}
        result = obs.observe(source("rig", id="kilo-core-msi"), lambda _: data)
        self.assertEqual(result["state"], "reported_fresh")
        self.assertFalse(result["remote_work_admitted"])
        data["bodies"][0]["execution_authorized"] = True
        with self.assertRaisesRegex(ValueError, "false_owner_body_admission"):
            obs.observe(source("rig", id="kilo-core-msi"), lambda _: data)

    def test_malformed_owner_status_fails_cleanly(self):
        row = mission()
        row["status"] = {"malicious": "unexpected"}
        with self.assertRaisesRegex(ValueError, "unrecognized_mission_state"):
            obs.observe(source("mission"), lambda _: row)

    def test_local_route_never_accepts_arbitrary_urls(self):
        with self.assertRaisesRegex(ValueError, "unapproved_studio_route"):
            obs.get_local_json("http://evil.invalid/api/health")
        with self.assertRaisesRegex(ValueError, "unapproved_studio_route"):
            obs.get_local_json("/api/missions/../../secrets")

    def test_service_stays_unknown_without_real_observation(self):
        data = {"schema": obs.HEALTH_SCHEMA,
                "colony_observation": {"available": False, "state": "UNKNOWN"}}
        result = obs.observe(source("service", id="studio"), lambda _: data)
        self.assertEqual(result["state"], "UNKNOWN")
        self.assertFalse(result["artifact_verified"])


if __name__ == "__main__":
    unittest.main()
