"""Adversarial controls for source-stamped advisory-only PR routing."""
import datetime as dt
import json
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parents[1]))
import collect_review_queue as q

NOW = dt.datetime(2026, 11, 8, 17, 0, tzinfo=dt.timezone.utc)
REPO = "GSV-Sublime-Optimization/GSV_Godot_Cockpit"


def record(n=20, name="Protect Studio missions", draft=False):
    return {"number": n, "title": name, "repository": {"nameWithOwner": REPO},
            "updatedAt": "2026-11-08T16:59:00Z", "isDraft": draft,
            "url": f"https://github.com/{REPO}/pull/{n}"}


def details(n=20, *, ci="SUCCESS", provenance=True, review="", head="a" * 40,
            conflict="MERGEABLE", base="master", changed=2):
    return {
        "headRefOid": head, "baseRefName": base, "isDraft": False,
        "reviewDecision": review, "mergeable": conflict,
        "statusCheckRollup": [{"name": "gsv/check", "status": "COMPLETED",
                               "conclusion": ci}],
        "body": "<!-- KILOCORE-PROVENANCE-V1 -->\n{}\n<!-- /KILOCORE-PROVENANCE-V1 -->"
                if provenance else "No provenance",
        "changedFiles": changed,
    }


class TestReviewQueue(unittest.TestCase):
    def test_source_sample_and_exact_head(self):
        data = q.collect([record()], {f"{REPO}#20": details()}, NOW)
        self.assertEqual(data["schema"], q.SCHEMA)
        item = data["items"][0]
        self.assertEqual(item["head"], "a" * 40)
        self.assertEqual(item["lane"], "independent_review")
        self.assertEqual(item["review"], "UNVERIFIED")
        self.assertEqual(item["blockers"], ["independent_review_unverified"])
        self.assertFalse(item["assignment_authorized"])

    def test_missing_details_never_claims_provenance_failure(self):
        item = q.collect([record()], {}, NOW)["items"][0]
        self.assertEqual(item["lane"], "inspect_source")
        self.assertEqual(item["blockers"], ["details_unobserved"])
        self.assertEqual(item["head"], "")
        self.assertFalse(item["detail_observed"])

    def test_ci_completed_without_conclusion_is_not_success(self):
        self.assertEqual(q.check_rollup([{"status": "COMPLETED"}]), "pending")
        self.assertEqual(q.check_rollup([{"status": "COMPLETED", "conclusion": "FAILURE"}]), "failed")
        self.assertEqual(q.check_rollup([]), "unobserved")

    def test_draft_and_stack_never_merge_ready(self):
        item = q.collect([record(draft=True)],
                         {f"{REPO}#20": details(review="APPROVED", base="feature")}, NOW)["items"][0]
        self.assertEqual(item["lane"], "author_admission")
        self.assertIn("stacked_dependency", item["blockers"])
        self.assertFalse(item["assignment_authorized"])

    def test_ci_failure_outweighs_review(self):
        item = q.collect([record()],
                         {f"{REPO}#20": details(ci="FAILURE", review="APPROVED")}, NOW)["items"][0]
        self.assertEqual(item["lane"], "repair_ci")
        self.assertIn("ci_failed", item["blockers"])

    def test_repo_and_url_allowlist(self):
        impostor = record()
        impostor["url"] = "https://evil.example/steal"
        self.assertEqual(q.collect([impostor], {}, NOW)["items"], [])
        external = record()
        external["repository"]["nameWithOwner"] = "other/cockpit"
        self.assertEqual(q.collect([external], {}, NOW)["items"], [])

    def test_actor_availability_expiry_and_capacity(self):
        with tempfile.TemporaryDirectory() as td:
            file = Path(td) / "availability.json"
            payload = {"schema": q.ACTORS_SCHEMA, "generated_utc": "2026-11-08T16:59:00Z",
                       "actors": [{"id": "agent/muse", "state": "available", "can_review": True,
                                   "skills": ["code"], "max_concurrent": 1,
                                   "active": 0, "observed_utc": "2026-11-08T16:59:00Z"}]}
            file.write_text(json.dumps(payload), encoding="utf-8")
            actors = q.availability(file, NOW)
            self.assertEqual(actors[0]["slots"], 1)
            rows = [record(20), record(21)]
            facts = {f"{REPO}#20": details(), f"{REPO}#21": details()}
            result = q.collect(rows, facts, NOW, actors)
            selected = [r for r in result["items"] if r["suggested_actor"]]
            self.assertEqual(len(selected), 1)
            self.assertEqual(selected[0]["suggested_actor"], "agent/muse")
            self.assertFalse(selected[0]["assignment_authorized"])
            self.assertEqual(q.availability(file, NOW + dt.timedelta(minutes=20)), [])

    def test_no_actor_inference_from_account_or_rating(self):
        result = q.collect([record()], {f"{REPO}#20": details()}, NOW)
        self.assertEqual(result["actor_source"], "unobserved")
        self.assertEqual(result["items"][0]["routing_reason"],
                         "no_fresh_qualified_reviewer_capacity")

    def test_atomic_snapshot_and_no_token_body(self):
        with tempfile.TemporaryDirectory() as td:
            target = Path(td) / "review_queue.json"
            raw = q.collect([record()], {f"{REPO}#20": details()}, NOW)
            q.dump_atomic(target, raw)
            doc = json.loads(target.read_text(encoding="utf-8"))
            self.assertEqual(len(doc["items"]), 1)
            self.assertNotIn("body", doc["items"][0])
            self.assertNotIn("token", target.read_text(encoding="utf-8"))
            self.assertEqual(list(Path(td).glob(".review-*.tmp")), [])

    def test_offline_cli_no_network(self):
        with tempfile.TemporaryDirectory() as td:
            base = Path(td)
            fixture = base / "input.json"
            fixture.write_text(json.dumps({"rows": [record()],
                                           "details": {f"{REPO}#20": details()}}),
                               encoding="utf-8")
            result = q.run(["--output", str(base / "export.json"), "--fixture", str(fixture)])
            self.assertEqual(result, 0)
            self.assertEqual(json.loads((base / "export.json").read_text())["counts"]["open_sampled"], 1)


if __name__ == "__main__":
    unittest.main()
