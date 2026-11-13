"""order_janitor: close Forge orders whose PR has merged, closed, or moved.

Covers the fold + PR extraction + head-move rule with a fake channel and a
fake gh. Nothing here touches xanadu or the network.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import order_janitor as jan  # noqa: E402


def _order(oid, text, link="", status_line=None):
    lines = [{"kind": "order", "id": oid, "at": "2026-11-08T18:33:11Z",
              "from": "keath", "to": "any", "station": "pegs", "text": text, "link": link}]
    if status_line:
        lines.append({"kind": "order-status", "id": oid, "at": "2026-11-08T19:00:00Z",
                      "from": "claude (msi seat)", "status": status_line, "note": "", "link": ""})
    return lines


class ExtractTest(unittest.TestCase):
    def test_link_url_wins(self):
        o = {"text": "Review dev#429", "link": "https://github.com/GSV-Sublime-Optimization/dev/pull/428"}
        self.assertEqual(jan.extract_pr(o), ("GSV-Sublime-Optimization/dev", 428))

    def test_short_names(self):
        cases = {
            "Review dev#424": ("GSV-Sublime-Optimization/dev", 424),
            "echoes-of-elevation#32 has changes requested": ("Echoes-Of-Elevation/echoes-of-elevation", 32),
            "Fix Furyline#224": ("Furyline/Furyline", 224),
            "Review GSV_Godot_Cockpit#31": ("GSV-Sublime-Optimization/GSV_Godot_Cockpit", 31),
            "Review KiloEthereal_Prime_Architect#11": ("GSV-Sublime-Optimization/KiloEthereal_Prime_Architect", 11),
            "Fix Forge-Build#50": ("Trueform-Forge/Forge-Build", 50),
            "Review Dev-Mentor#293": ("GSV-Sublime-Optimization/Dev-Mentor", 293),
        }
        for text, want in cases.items():
            with self.subTest(text=text):
                self.assertEqual(jan.extract_pr({"text": text}), want)

    def test_full_org_repo(self):
        self.assertEqual(jan.extract_pr({"text": "see GSV-Sublime-Optimization/dev#424"}),
                         ("GSV-Sublime-Optimization/dev", 424))

    def test_first_pr_mentioned(self):
        # Cockpit #31's order also mentions #21 and #17/#19; the order is about #31.
        o = {"text": "Review GSV_Godot_Cockpit#31 (fixes the parse error on YOUR #17/#19 branch). "
                     "Note: #21 fixes the same parse error; keep one, close the other."}
        self.assertEqual(jan.extract_pr(o), ("GSV-Sublime-Optimization/GSV_Godot_Cockpit", 31))

    def test_no_pr_reference(self):
        self.assertIsNone(jan.extract_pr({"text": "The mempalace-api service is down on the spine."}))
        self.assertIsNone(jan.extract_pr({"text": "Review SomeUnknownRepo#9"}))

    def test_named_head(self):
        self.assertEqual(jan.named_head({"text": "Fix Furyline#224, missing-provenance at head eba64e7f690c"}),
                         "eba64e7f690c")
        self.assertEqual(jan.named_head({"text": "Review dev#425 at head 9968ba48bae3"}), "9968ba48bae3")
        self.assertIsNone(jan.named_head({"text": "Review dev#428, no head here"}))


class DecideTest(unittest.TestCase):
    def test_merged(self):
        note, _ = jan.decide({"text": "Review dev#424"}, "MERGED", "9b0c4d34")
        self.assertIn("merged", note)

    def test_closed_unmerged(self):
        note, _ = jan.decide({"text": "Review GSV_Godot_Cockpit#31"}, "CLOSED", "3b17a21a")
        self.assertIn("closed unmerged", note)

    def test_head_moved(self):
        note, _ = jan.decide({"text": "Fix Furyline#224 at head eba64e7f690c"}, "OPEN", "89ea92ad3fcf")
        self.assertIn("89ea92ad", note)
        self.assertIn("stale", note)

    def test_head_prefix_matches(self):
        # Order names an 8-char prefix of the current full head: same head, not moved.
        self.assertIsNone(jan.decide({"text": "Review dev#429 at head 4bbabc0e"}, "OPEN",
                                      "4bbabc0e6acbcce601f2da548bedc8cb527b519a"))

    def test_same_head(self):
        self.assertIsNone(jan.decide({"text": "Review KiloEthereal_Prime_Architect#11 at head 601555fb948a"},
                                      "OPEN", "601555fb948a0ddd2b24ea6a671e3b27ccd83a14"))

    def test_open_no_head_named(self):
        self.assertIsNone(jan.decide({"text": "echoes-of-elevation#32 has changes requested"}, "OPEN", "cb0fb360"))

    def test_no_pr(self):
        self.assertIsNone(jan.decide({"text": "mempalace-api is down"}, "OPEN", "abc"))


class RunTest(unittest.TestCase):
    def setUp(self):
        self.channel = []
        self.channel += _order("o-1", "Review dev#424", "https://github.com/GSV-Sublime-Optimization/dev/pull/424")
        self.channel += _order("o-2", "Fix Furyline#224 at head eba64e7f690c",
                               "https://github.com/Furyline/Furyline/pull/224")
        self.channel += _order("o-3", "Review dev#429 at head 4bbabc0e",
                               "https://github.com/GSV-Sublime-Optimization/dev/pull/429")
        self.channel += _order("o-4", "The mempalace-api service is down")
        self.channel += _order("o-5", "Review dev#428", status_line="done")
        self.channel += _order("o-6", "Review dev#425", status_line="declined")
        self.gh = {("GSV-Sublime-Optimization/dev", 424): ("MERGED", "9b0c4d34"),
                   ("Furyline/Furyline", 224): ("OPEN", "89ea92ad3fcf"),
                   ("GSV-Sublime-Optimization/dev", 429): ("OPEN", "4bbabc0e6acb")}
        self.appended = []

    def fake_gh(self, repo, number):
        return self.gh.get((repo, number))

    def fake_append(self, oid, note, link):
        self.appended.append((oid, note, link))
        return True

    def test_dry_run_closes_only_stale(self):
        report = jan.run(self.channel, apply=False, gh=self.fake_gh, append=self.fake_append)
        self.assertEqual([c["id"] for c in report["closed"]], ["o-1", "o-2"])
        self.assertEqual(self.appended, [])  # dry run writes nothing
        self.assertEqual(sorted(s["id"] for s in report["skipped"]), ["o-3", "o-4"])
        # done/declined orders are not posted, so they never appear
        self.assertEqual(report["errors"], [])

    def test_apply_and_idempotent(self):
        jan.run(self.channel, apply=True, gh=self.fake_gh, append=self.fake_append)
        self.assertEqual([a[0] for a in self.appended], ["o-1", "o-2"])
        # After the appends, the fold sees o-1/o-2 as done: a re-run closes nothing.
        channel2 = self.channel + [
            {"kind": "order-status", "id": oid, "at": "2026-11-09T12:00:00Z",
             "from": "janitor", "status": "done", "note": note, "link": link}
            for oid, note, link in self.appended]
        report = jan.run(channel2, apply=True, gh=self.fake_gh, append=self.fake_append)
        self.assertEqual(report["closed"], [])
        self.assertEqual(len(self.appended), 2)  # nothing appended twice

    def test_gh_failure_leaves_order_alone(self):
        def failing_gh(repo, number):
            return None
        report = jan.run(self.channel, apply=True, gh=failing_gh, append=self.fake_append)
        self.assertEqual(report["closed"], [])
        self.assertEqual(len(report["errors"]), 3)  # o-1, o-2, o-3 all undeterminable
        self.assertEqual(self.appended, [])


if __name__ == "__main__":
    unittest.main()
