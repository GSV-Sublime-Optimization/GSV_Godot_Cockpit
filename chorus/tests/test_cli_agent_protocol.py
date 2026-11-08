"""chorus.py's agent commands: suggest, next, orders (receipts) and work (PR stages); and the page
reading the new feed fields. _post and load are replaced, so nothing reaches xanadu."""
import json
import sys
from pathlib import Path

import pytest

import chorus
from conftest import NOW, iso

HERE = Path(__file__).resolve().parents[1]


def run(monkeypatch, capsys, argv, feed=None):
    posted = []
    monkeypatch.setattr(chorus, "_post", posted.append)
    if feed is not None:
        monkeypatch.setattr(chorus, "load", lambda: feed)
    monkeypatch.setattr(sys, "argv", ["chorus.py", *argv])
    chorus.main()
    return posted, capsys.readouterr().out


def test_suggest_posts_a_shared_protocol_suggestion_line(monkeypatch, capsys):
    posted, _ = run(monkeypatch, capsys, ["suggest", "show the head sha  on PR cards", "--as", "codex", "--node", "forge"])
    (m,) = posted
    assert m["kind"] == "suggestion" and m["from"] == "codex" and m["text"] == "show the head sha on PR cards"
    assert m["node"] == "forge" and "id" not in m                     # a suggestion, not an order
    json.dumps(m)


def test_suggest_refuses_empty_text_and_signing_as_keath(monkeypatch, capsys):
    with pytest.raises(SystemExit):
        run(monkeypatch, capsys, ["suggest", "   ", "--as", "codex"])
    with pytest.raises(SystemExit):
        run(monkeypatch, capsys, ["suggest", "x", "--as", "keath (chorus)"])


def test_next_as_seat_prints_the_plan(monkeypatch, capsys, colony_feed):
    _, out = run(monkeypatch, capsys, ["next", "--as", "claude (msi seat)"], colony_feed)
    assert out.startswith("NEXT for claude (msi seat): [review] dev#430")
    assert "who:" in out and "    1. gh pr checkout 430" in out
    _, out = run(monkeypatch, capsys, ["next", "--as", "claude (msi seat)", "--json"], colony_feed)
    assert json.loads(out)["item"]["pr"]["number"] == 430


def test_orders_view_shows_receipts(monkeypatch, capsys, colony_feed):
    u = colony_feed["prs_open"]
    colony_feed["channel"] += [
        {"kind": "order", "id": "o-1", "at": iso(NOW), "to": "any", "station": "pegs", "text": "Review dev#432", "url": u[3]["url"]},
        {"kind": "order-status", "id": "o-1", "status": "done", "from": "codex"},
        {"kind": "order", "id": "o-2", "at": iso(NOW), "to": "any", "station": "pegs", "text": "Review dev#431", "url": u[1]["url"]},
        {"kind": "order-status", "id": "o-2", "status": "done", "from": "muse"},
        {"kind": "order", "id": "o-3", "at": iso(NOW), "to": "any", "station": "anvil", "text": "restart litellm"},
        {"kind": "order-status", "id": "o-3", "status": "done", "from": "claude (msi seat)"}]
    _, out = run(monkeypatch, capsys, ["orders", "--all"], colony_feed)
    lines = {l.split()[0]: l for l in out.splitlines()[1:] if l.strip().startswith("o-")}
    assert "done: verified" in lines["o-1"]
    assert "done: NOT confirmed" in lines["o-2"]
    assert "done: reported" in lines["o-3"]


def test_work_view_counts_reviews_by_head_check(monkeypatch, capsys, colony_feed):
    _, out = run(monkeypatch, capsys, ["work"], colony_feed)
    assert "2 needs-review" in out and "1 approved" in out and "1 reviewed" in out
    waiting = [l for l in out.splitlines() if "[needs-review" in l]
    assert not any("#432" in l or "#286" in l for l in waiting)      # reviewed at head: never listed as waiting


def test_pages_read_the_new_feed_fields():
    index = (HERE / "index.html").read_text(encoding="utf-8")
    assert "suggestions: d.suggestions" in index and "open suggestion" in index
    forge = (HERE / "forge.html").read_text(encoding="utf-8")
    assert "o.receipt" in forge and "NOT confirmed" in forge
