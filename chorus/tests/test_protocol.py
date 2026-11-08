"""The shared colony protocol as CHORUS reads it: gsv-review head check, receipts, read receipts,
suggestions, and the order fold. Pure functions over fixtures; no network."""
import mindview_feed
import protocol
from conftest import HEAD_A, HEAD_B, NOW, iso, marker
from shop import orders


# ---------------------------------------------------------------- 1. reviews by the gsv-review head check
def test_review_at_current_head_counts():
    st = protocol.pr_stage({"headRefOid": HEAD_A, "comments": [{"body": marker(HEAD_A)}]})
    assert st["stage"] == "approved" and st["reviewers"] == ["agent/codex"]


def test_review_at_older_head_is_stale_not_reviewed():
    st = protocol.pr_stage({"headRefOid": HEAD_B, "comments": [{"body": marker(HEAD_A)}]})
    assert st["stage"] == "stale-review" and st["reviewers"] == [] and st["older_reviews"] == 1


def test_review_decision_is_ignored():
    """Agents post as the PR author's account, so reviewDecision never moves; it must not count."""
    st = protocol.pr_stage({"headRefOid": HEAD_A, "reviewDecision": "APPROVED", "comments": []})
    assert st["stage"] == "needs-review"


def test_marker_in_a_review_body_counts_and_request_changes_wins():
    st = protocol.pr_stage({"headRefOid": HEAD_A, "comments": [{"body": marker(HEAD_A, "approve")}],
                            "reviews": [{"body": marker(HEAD_A, "request-changes", "agent/gpt-6")}]})
    assert st["stage"] == "changes"
    assert st["reviewers"] == ["agent/codex", "agent/gpt-6"]


def test_abbreviated_head_matches_but_too_short_does_not():
    assert protocol.at_head(HEAD_A[:10], HEAD_A)
    assert not protocol.at_head(HEAD_A[:6], HEAD_A)
    assert not protocol.at_head(HEAD_B[:10], HEAD_A)


def test_feeder_does_not_list_reviewed_prs_as_waiting():
    """Regression: the feeder asked GitHub for `--review none` and only read issue comments, so its
    'waiting' list came from GitHub's review state. Now every open PR is staged by the head check."""
    rows = [{"repository": {"name": "dev"}, "number": n, "title": f"pr {n}", "url": f"u/{n}",
             "createdAt": iso(NOW), "isDraft": n == 4} for n in (1, 2, 3, 4)]
    views = {1: {"headRefOid": HEAD_A, "headRefName": "codex/x", "comments": [], "reviews": [{"body": marker(HEAD_A)}]},
             2: {"headRefOid": HEAD_B, "headRefName": "codex/y", "comments": [{"body": marker(HEAD_A)}]},
             3: {"headRefOid": HEAD_A, "headRefName": "gpt6/z", "comments": [], "reviewDecision": "APPROVED"}}
    seen = []

    def view(repo, number):
        seen.append(number)
        return views[number]
    staged = {p["number"]: p for p in mindview_feed.classify_prs(rows, view)}
    assert staged[1]["stage"] == "approved"          # reviewed in a review body at the head: not waiting
    assert staged[2]["stage"] == "stale-review"      # reviewed at an old head: waiting for a fresh look
    assert staged[3]["stage"] == "needs-review"      # reviewDecision APPROVED alone does not count
    assert staged[4]["stage"] == "draft" and 4 not in seen
    assert staged[1]["author"]["name"] == "Codex"
    waiting = [p["number"] for p in staged.values() if p["stage"] in protocol.WAITING]
    assert waiting == [2, 3]


# ---------------------------------------------------------------- 2. receipts: verified / reported / NOT confirmed
def _done(**kw):
    return {"status": "done", "station": "pegs", "text": "Review dev#430", **kw}


def test_review_order_verified_only_with_review_at_head():
    idx = {"dev#430": {"reviewers": ["agent/codex"]}, "dev#431": {"reviewers": []}}
    assert protocol.receipt(_done(), idx) == "verified"
    assert protocol.receipt(_done(text="Review dev#431"), idx) == "NOT confirmed"
    assert protocol.receipt(_done(text="Review dev#999"), idx) == "reported"   # closed or unseen: can't check


def test_merge_order_verified_once_pr_closed():
    idx = {"dev#430": {"reviewers": []}}
    merge = {"status": "done", "station": "anvil", "ref": "merge:dev#430", "text": "merge it"}
    assert protocol.receipt(merge, idx) == "NOT confirmed"
    assert protocol.receipt({**merge, "ref": "merge:dev#429"}, idx) == "verified"
    assert protocol.receipt({**merge, "ref": "", "text": "MERGE https://github.com/GSV-Sublime-Optimization/dev/pull/429"}, idx) == "verified"


def test_receipt_is_only_reported_when_unmeasured_or_unverifiable():
    assert protocol.receipt(_done(), None) == "reported"               # GitHub never answered
    assert protocol.receipt({"status": "done", "station": "anvil", "text": "restart litellm"}, {}) == "reported"
    assert protocol.receipt({"status": "working", "station": "pegs", "text": "Review dev#430"}, {}) is None


def test_order_fold_keeps_ref_and_url_and_never_resets():
    ch = [{"kind": "order", "id": "o-1", "at": iso(NOW), "to": "codex", "station": "pegs", "text": "Review dev#430",
           "ref": "review:dev#430", "url": "https://github.com/GSV-Sublime-Optimization/dev/pull/430"},
          {"kind": "order-status", "id": "o-1", "status": "done", "from": "codex", "link": "l"},
          {"kind": "order", "id": "o-1", "at": iso(NOW + 5), "to": "any", "text": "re-posted"}]
    (o,) = orders(ch)
    assert o["status"] == "done" and o["ref"] == "review:dev#430" and o["url"].endswith("/430")
    protocol.annotate_receipts([o], {"dev#430": {"reviewers": []}})
    assert o["receipt"] == "NOT confirmed"


# ---------------------------------------------------------------- read receipts, both shapes
def test_read_receipts_both_shapes():
    ch = [{"at": "2026-11-08T07:00:00Z", "from": "keath (chorus)", "text": "a"},
          {"at": "2026-11-08T07:05:00Z", "from": "claude (i3 seat)", "text": "b"},
          {"at": "2026-11-08T07:10:00Z", "from": "keath (chorus)", "text": "c"},
          {"kind": "read", "from": "claude (i3 seat)", "at": "2026-11-08T07:06:00Z"},
          {"kind": "read", "from": "claude (msi seat)", "at": "2026-11-08T07:20:00Z", "reads": ["2026-11-08T07:10:00Z"]}]
    rb = protocol.read_by(ch)
    assert rb["2026-11-08T07:00:00Z"] == {"claude (i3 seat)"}
    assert "2026-11-08T07:05:00Z" not in rb                 # a watermark never marks the reader's own line
    assert rb["2026-11-08T07:10:00Z"] == {"claude (msi seat)"}


# ---------------------------------------------------------------- suggestions
def test_open_suggestions_close_when_ordered_and_expire():
    s1 = {"at": iso(NOW - 60), "from": "codex", "kind": "suggestion", "text": "show heads"}
    s2 = {"at": iso(NOW - 120), "from": "muse", "kind": "suggestion", "text": "bigger PR cards"}
    old = {"at": iso(NOW - 8 * 86400), "from": "muse", "kind": "suggestion", "text": "ancient"}
    legacy = {"kind": "order", "id": "s-1", "at": iso(NOW - 30), "to": "claude (msi seat)", "station": "cockpit",
              "text": "SUGGEST [holo]: label the moons"}
    taken = {"kind": "order", "id": "o-9", "at": iso(NOW), "ref": protocol.suggestion_id(s2), "text": "do it"}
    ch = [s1, s2, old, legacy, taken]
    got = protocol.open_suggestions(ch, orders(ch), NOW)
    assert [g["text"] for g in got] == ["label the moons", "show heads"]
