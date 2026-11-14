"""reroute.py: a stale order to a seat that cannot act gets exactly ONE re-route; a reachable seat that is
only slow is left alone; a review of a Claude-authored PR never lands on a Claude seat. Also the router
rule behind it: the i3 Mind (a chat model with no tools) is never picked for orders or reviews.
No test reaches xanadu or GitHub: the channel writer and the GitHub mirror are lists."""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import reroute  # noqa: E402
import router  # noqa: E402
from shop import CLOSED, orders  # noqa: E402

NOW = time.time()


def iso(t: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


def order(oid, to, text, mins_ago, station="quench", **kw):
    return {"kind": "order", "id": oid, "at": iso(NOW - mins_ago * 60), "from": "keath (chorus)", "to": to,
            "station": station, "text": text, **kw}


def seen(seat, mins_ago=2):
    return {"from": seat, "at": iso(NOW - mins_ago * 60), "text": "here"}


FEED_LIVE = {"smiths": [], "prs_recent": [
    {"agent": "a Claude", "repo": "dev", "number": 428, "title": "docs(colony): fork atlas",
     "url": "https://github.com/GSV-Sublime-Optimization/dev/pull/428", "state": "OPEN"}]}


def channel_with(*lines):
    return [seen("claude (msi seat)"), seen("claude (i3 seat)"), seen("i3-mind"), *lines]


def run(channel, feed=None):
    feed = {**FEED_LIVE, **(feed or {}), "channel": channel}
    return reroute.plan(channel, feed, now=NOW, ledger=set())


def test_stale_order_to_the_i3_mind_gets_one_reroute_to_a_seat_with_hands():
    ch = channel_with(order("o-1", "i3-mind", "The mempalace-api service is down on the spine. Find out why.", 40))
    items = run(ch)
    assert len(items) == 1 and items[0]["to"] in ("claude (msi seat)", "claude (i3 seat)")
    assert "cannot execute" in items[0]["reason"]
    lines, mirrored = [], []
    res = reroute.apply(items, lines.append, lambda *a, **k: mirrored.append(a), now=NOW, ledger=set(), persist=False)
    assert res[0]["ok"] and not mirrored
    new, status = lines
    assert new["kind"] == "order" and new["ref"] == "o-1" and new["to"] == items[0]["to"]
    assert status == {**status, "kind": "order-status", "id": "o-1", "status": "rerouted"}
    assert status["note"].startswith(f"to {items[0]['to']}: ")
    # the original now counts as closed, the new order is open
    folded = {o["id"]: o for o in orders(ch + lines)}
    assert folded["o-1"]["status"] == "rerouted" and "rerouted" in CLOSED
    assert folded[new["id"]]["status"] == "posted" and folded[new["id"]]["ref"] == "o-1"


def test_stale_order_to_an_unseen_seat_is_rerouted():
    ch = [seen("claude (msi seat)"), order("o-2", "claude (i3 seat)", "Fix the i3 tunnel check.", 30)]
    items = run(ch)
    assert len(items) == 1 and items[0]["to"] == "claude (msi seat)"
    assert "not seen" in items[0]["reason"]


def test_reachable_but_slow_seat_is_left_alone():
    ch = channel_with(order("o-3", "claude (msi seat)", "Fix the backup receipt.", 90))
    assert run(ch) == []


def test_fresh_orders_and_orders_to_any_are_left_alone():
    ch = channel_with(order("o-4", "i3-mind", "Fix something.", 5), order("o-5", "any", "Fix another thing.", 60))
    assert run(ch) == []


def test_never_rerouted_twice():
    ch = channel_with(order("o-6", "i3-mind", "Kilo_Core holds 55 uncommitted files. Sort them.", 40))
    lines = []
    reroute.apply(run(ch), lines.append, now=NOW, ledger=set(), persist=False)
    assert run(ch + lines) == []                       # the channel now says so
    # a re-route by a seat's own convention (ref "reroute:<id>", or a declined "re-routed" note) counts too
    manual = order("o-9", "claude (msi seat)", "Re-routed from o-7: ...", 1, ref="reroute:o-7")
    assert run(channel_with(order("o-7", "i3-mind", "Fix it.", 40), manual)) == []
    # and the re-routed order itself is never re-routed again (no ping-pong), even when it goes stale
    stale_child = order("o-10", "i3-mind", "Re-routed from o-8: fix it.", 60, ref="o-8")
    assert run(channel_with(order("o-8", "i3-mind", "Fix it.", 90), stale_child)) == []
    # the local ledger stops a second writer that reads a stale channel
    items = run(channel_with(order("o-11", "i3-mind", "Fix it.", 40)))
    assert reroute.apply(items, lines.append, now=NOW, ledger={"o-11"}, persist=False) == []


def test_unrelated_refs_are_not_reroutes():
    ch = channel_with(order("o-12", "i3-mind", "Fix it.", 40, ref="decision:xanadu card 08"))
    assert [i["id"] for i in run(ch)] == ["o-12"]


def test_review_of_a_claude_pr_never_goes_to_a_claude_seat():
    ch = channel_with(order("o-13", "i3-mind", 'Review dev#428 ("docs(colony): fork atlas") and post evidence.', 40))
    items = run(ch)
    assert len(items) == 1 and items[0]["kind"] == "review-request"
    assert router.TARGETS[items[0]["to"]]["vendor"] != "claude"
    assert items[0]["to"] in router.CLOUD_SEATS
    lines, mirrored = [], []

    def gh(t, kind, sender, about, text, why, when, url, base, ref=""):
        mirrored.append((t["label"], url, ref))
        return {"summary": "prepared"}
    res = reroute.apply(items, lines.append, gh, now=NOW, ledger=set(), persist=False)
    assert res[0]["ok"] and mirrored[0][1] == "https://github.com/GSV-Sublime-Optimization/dev/pull/428"
    assert mirrored[0][2] == res[0]["new_id"]


def test_review_with_unknown_author_is_treated_as_claude():
    ch = channel_with(order("o-14", "i3-mind", "Review Furyline#999 and post evidence.", 40))
    items = run(ch)
    assert items and router.TARGETS[items[0]["to"]]["vendor"] != "claude"


def test_stale_review_to_a_cloud_seat_moves_to_another_independent_actor():
    ch = channel_with(order("o-15", "gpt-6", "dev#428 awaits a second review: docs(colony): fork atlas", 40, station="pegs"))
    items = run(ch)
    assert items[0]["to"] in ("codex", "muse") and "does not read the channel" in items[0]["reason"]


# ------------------------------------------------------------------ the router never hands the i3 Mind work
def test_i3_mind_only_asks_and_status():
    assert router.can_take("i3-mind", "ask") and router.can_take("i3-mind", "status")
    for kind in ("order", "action-order", "review-request", "handoff"):
        assert not router.can_take("i3-mind", kind)


def test_router_never_picks_i3_mind_for_orders_or_reviews():
    feed = {"smiths": [], "channel": [seen("i3-mind"), seen("claude (i3 seat)"), seen("claude (msi seat)")]}
    i3 = {"kind": "rig", "id": "i3", "rig": "i3", "failing": True, "detail": "docker failing"}
    for text, node in (("fix docker on the i3", i3), ("", i3),
                       ("review it", {"kind": "pr", "repo": "dev", "number": "1", "waiting": True}),
                       ("review it", {"kind": "pr", "repo": "dev", "number": "2", "waiting": True, "agent": "codex/x"})):
        out = router.route(text, node, feed, use_atlas=False)
        assert out["to"] != "i3-mind"
        assert all(a["to"] != "i3-mind" for a in out["alternatives"])


def test_router_may_send_a_question_to_the_i3_mind():
    feed = {"smiths": [], "channel": [seen("i3-mind")]}
    out = router.route("why is the gpu hot?", {"kind": "rig", "id": "i3", "rig": "i3"}, feed, use_atlas=False)
    assert "i3-mind" in [out["to"]] + [a["to"] for a in out["alternatives"]]
