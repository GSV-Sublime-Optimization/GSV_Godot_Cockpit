"""`chorus.py next --as SEAT`: one highest-yield item per seat, under the colony's dispatch rules."""
import nextmove
from conftest import NOW, iso


def item_of(seat, feed):
    return nextmove.plan_for(seat, feed, NOW)["item"]


def test_never_assigns_a_review_to_the_prs_author(colony_feed):
    # dev#430 is the i3 Claude's own branch and the highest-yield review (a fix): the i3 seat must not get it
    i3 = item_of("claude (i3 seat)", colony_feed)
    assert i3["kind"] == "review" and i3["pr"]["number"] != 430
    msi = item_of("claude (msi seat)", colony_feed)
    assert msi["kind"] == "review" and msi["pr"]["number"] == 430


def test_generic_claude_author_excludes_every_claude_seat():
    a = {"name": "a Claude", "family": "Claude", "rig": None}
    assert nextmove.is_author("claude (msi seat)", a) and nextmove.is_author("claude (i3 seat)", a)
    assert not nextmove.is_author("codex", a)
    assert nextmove.pr_author("contrib/x", "...\nGenerated with [Claude Code](https://claude.com/claude-code)")["family"] == "Claude"
    assert nextmove.pr_author("bakeoff/mindview-msiclaude", "")["rig"] == "msi"


def test_codex_cannot_review_its_own_pr(colony_feed):
    it = item_of("codex", colony_feed)
    assert not (it["kind"] == "review" and (it["pr"]["author"] or {}).get("family") == "Codex")


def test_one_open_order_per_seat(colony_feed):
    colony_feed["channel"].append({"kind": "order", "id": "o-7", "at": iso(NOW - 600), "from": "keath (chorus)",
                                   "to": "claude (i3 seat)", "station": "anvil", "text": "tidy the radio logs"})
    colony_feed["channel"].append({"kind": "order-status", "id": "o-7", "status": "working", "from": "claude (i3 seat)"})
    it = item_of("claude (i3 seat)", colony_feed)
    assert it["kind"] == "order" and it["id"] == "o-7"


def test_items_held_by_another_seats_order_are_skipped(colony_feed):
    colony_feed["channel"].append({"kind": "order", "id": "o-8", "at": iso(NOW - 600), "to": "codex", "station": "pegs",
                                   "text": "Review dev#430", "url": colony_feed["prs_open"][0]["url"]})
    colony_feed["channel"].append({"kind": "order-status", "id": "o-8", "status": "taken", "from": "codex"})
    it = item_of("claude (msi seat)", colony_feed)
    assert not (it["kind"] == "review" and it["pr"]["number"] == 430)


def test_keath_only_decisions_go_to_keath(colony_feed):
    k = item_of("keath", colony_feed)
    assert k["kind"] == "merge" and k["pr"]["number"] == 286         # approved at head: the top Keath-only item
    for seat in ("claude (msi seat)", "claude (i3 seat)", "codex", "gpt-6", "muse"):
        plan = nextmove.plan_for(seat, colony_feed, NOW)
        assert plan["item"] is None or plan["item"]["kind"] not in nextmove.KEATH_ONLY


def test_hands_on_hardware_goes_to_keath(colony_feed):
    items = {i["id"]: i for i in nextmove.queue(colony_feed, NOW)}
    hw = items["rig:i3:docker"]
    assert hw["kind"] == "hands"                                      # the doctor said BIOS
    assert nextmove.fit("claude (i3 seat)", hw) == 0 and nextmove.fit("keath (chorus)", hw) > 0
    colony_feed["prs_open"] = [p for p in colony_feed["prs_open"] if p["stage"] != "approved"]
    colony_feed["steward_cards"] = []
    assert item_of("keath", colony_feed)["id"] == "rig:i3:docker"


def test_rig_fault_without_hands_goes_to_a_seat_on_that_rig(colony_feed):
    colony_feed["doctor"] = [{"key": "i3:docker", "verdict": "Docker Desktop is not started", "evidence": []}]
    hw = {i["id"]: i for i in nextmove.queue(colony_feed, NOW)}["rig:i3:docker"]
    assert hw["kind"] == "rig"
    assert nextmove.fit("claude (i3 seat)", hw) > 0 and nextmove.fit("claude (msi seat)", hw) == 0
    assert item_of("claude (i3 seat)", colony_feed)["id"] == "rig:i3:docker"   # yield 60 beats a review


def test_not_confirmed_done_comes_back_to_its_seat(colony_feed):
    url = colony_feed["prs_open"][1]["url"]                           # dev#431: no review at its head
    colony_feed["channel"] += [
        {"kind": "order", "id": "o-5", "at": iso(NOW - 900), "to": "gpt-6", "station": "pegs", "text": "Review dev#431", "url": url},
        {"kind": "order-status", "id": "o-5", "status": "done", "from": "gpt-6", "note": "looks fine"}]
    it = item_of("gpt-6", colony_feed)
    assert it["kind"] == "redo" and it["order"]["id"] == "o-5"
    assert item_of("codex", colony_feed)["kind"] != "redo"


def test_suggestions_go_to_chorus_seat_and_replies_to_the_asked(colony_feed):
    s = {i["id"]: i for i in nextmove.queue(colony_feed, NOW) if i["kind"] == "suggestion"}
    (sug,) = s.values()
    assert nextmove.fit("claude (msi seat)", sug) > 0 and nextmove.fit("claude (i3 seat)", sug) == 0
    colony_feed["channel"].append({"at": iso(NOW - 100), "from": "keath (chorus)", "to": "codex", "text": "status of echoes?"})
    rep = [i for i in nextmove.queue(colony_feed, NOW) if i["kind"] == "reply"]
    assert rep and nextmove.fit("codex", rep[0]) > 0 and nextmove.fit("muse", rep[0]) == 0


def test_render_names_who_what_where_when_why_and_numbered_steps(colony_feed):
    out = nextmove.render("claude (msi seat)", nextmove.plan_for("claude (msi seat)", colony_feed, NOW))
    for label in ("who:", "what:", "where:", "when:", "why:", "how:", "    1. ", "    2. "):
        assert label in out
    assert "head=" + "a" * 40 in out                                   # the review step binds to the PR's head


def test_old_feed_without_prs_open_still_works(colony_feed):
    colony_feed.pop("prs_open")
    colony_feed["prs_waiting"] = [{"repo": "dev", "number": 1, "title": "t", "url": "u", "created": iso(NOW)}]
    assert item_of("codex", colony_feed)["kind"] == "review"
