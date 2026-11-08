"""router.route picks kind, who, where and when from the words and the node, and never writes."""
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import router  # noqa: E402

NOW = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
FEED = {"smiths": [{"name": "MSI Claude", "at": NOW}, {"name": "i3 Claude", "at": NOW}, {"name": "i3 Mind", "at": NOW}],
        "channel": []}


def r(text, node=None, feed=FEED, **kw):
    return router.route(text, node, feed, use_atlas=False, **kw)


def test_failing_check_becomes_an_order_to_the_seat_owning_the_rig():
    out = r("", {"kind": "check", "rig": "i3", "check": "docker", "ok": False, "verdict": "VT-x is off"})
    assert out["draft"]["kind"] == "order"
    assert out["to"] == "claude (i3 seat)" and out["where"] == "channel"
    assert "VT-x is off" in out["why"] and "VT-x is off" in out["preview"]
    assert out["draft"]["text"]                          # never a blank prefill


def test_failing_check_on_msi_goes_to_the_msi_seat():
    out = r("fix it", {"kind": "check", "rig": "msi", "check": "dev-mentor", "ok": False})
    assert (out["draft"]["kind"], out["to"]) == ("order", "claude (msi seat)")


def test_claude_authored_pr_review_never_goes_to_a_claude():
    node = {"kind": "pr", "repo": "dev", "number": 429, "waiting": True, "agent": "a Claude",
            "url": "https://github.com/GSV-Sublime-Optimization/dev/pull/429"}
    out = r("", node)
    assert out["draft"]["kind"] == "review-request"
    assert router.TARGETS[out["to"]]["vendor"] != "claude"
    assert all(router.TARGETS[a["to"]]["vendor"] != "claude" for a in out["alternatives"])
    assert out["where"] == "github" and out["reach"] == "prepared"


def test_review_of_a_gpt_pr_may_go_to_a_claude_but_not_to_gpt():
    out = r("please review this", {"kind": "pr", "repo": "dev", "number": 5, "waiting": True, "agent": "GPT-6"})
    assert router.TARGETS[out["to"]]["vendor"] != "openai"
    assert all(router.TARGETS[a["to"]]["vendor"] != "openai" for a in out["alternatives"])
    assert out["where"] in ("channel", "review-queue")


def test_cockpit_idea_is_a_suggestion_to_the_msi_seat():
    out = r("the spine moons should show latency as their size", {"kind": "svc", "name": "litellm"})
    assert (out["draft"]["kind"], out["to"], out["draft"]["station"]) == ("suggest", "claude (msi seat)", "cockpit")


def test_summary_goes_to_a_local_model_first():
    out = r("summarize what the minds said about i3 tonight")
    assert out["draft"]["kind"] == "ask"
    assert out["to"].startswith("local:") and out["where"] == "local"


def test_everyone_fans_out_to_all():
    out = r("everyone: backup is running, hold pushes for 10 minutes")
    assert out["to"] == "all" and out["where"] == "channel" and out["draft"]["kind"] == "status"


def test_named_target_wins_and_the_directive_is_stripped():
    out = r("send to l9 local: what is the drone's model?")
    assert out["to"] == "local:l9" and out["confidence"] > 0.9
    assert out["draft"]["text"] == "what is the drone's model?"


def test_busy_i3_mind_is_ranked_down():
    feed = {**FEED, "channel": [{"from": "i3-mind", "at": NOW, "text": "I'll answer after the current playtest"}]}
    out = r("why is the gpu hot?", {"kind": "rig", "id": "i3", "rig": "i3"}, feed)
    mind = next(a for a in [out] + out["alternatives"] if a["to"] == "i3-mind")
    assert out["to"] != "i3-mind"
    assert "playtest" in (mind.get("because") or mind.get("reasons"))


def test_when_after_a_dependency_and_at_a_time():
    assert r("land the mirror fix after #424 merges")["due"] == "after:#424"
    when, due = router.parse_when("run it at 23:30", datetime(2026, 11, 8, 12, 0).astimezone())
    assert when == "at 23:30" and due.endswith("Z")
    assert r("check it next hourly cycle")["due"] == "hourly"


def test_action_node_and_restart_words_make_an_action_order():
    node = {"kind": "svc", "name": "dispatch", "down": True, "action": "restart", "target": "kilocore-dispatch"}
    out = r("restart it", node)
    assert out["draft"]["kind"] == "action-order" and out["draft"]["station"] == "act"
    assert router.TARGETS[out["to"]]["type"] == "seat"


def test_route_is_pure():
    feed = {"smiths": [], "channel": [{"from": "i3-mind", "at": NOW, "text": "hi"}]}
    before = repr(feed)
    r("what is up?", {"kind": "rig", "id": "i3"}, feed)
    assert repr(feed) == before
