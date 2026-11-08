"""The feeder ships a containerised Mind's outbox (the MSI Culture Ship) to xanadu's events: each
complete line once, a half-written line waits, junk is dropped, a failed ship is retried next cycle."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mindview_feed as feed  # noqa: E402

EV = {"at": "2026-11-08T19:00:00+00:00", "mind": "culture-ship", "model": "qwen3:8b", "level": "routine",
      "floor": "routine", "reasons": [], "line": "quiet", "ms": 900, "focus": "msi", "simulated": False}


def test_ships_each_complete_line_once(tmp_path):
    out, off = tmp_path / "outbox", tmp_path / "off.json"
    out.mkdir()
    f = out / "2026-11-08.jsonl"
    f.write_text(json.dumps(EV) + "\nnot json\n" + json.dumps({**EV, "line": "half"})[:30], encoding="utf-8")
    sent = []
    assert feed.ship_minds(out, off, lambda day, blob: sent.append((day, blob)))["shipped"] == 1
    assert sent[0][0] == "2026-11-08" and json.loads(sent[0][1])["line"] == "quiet"
    assert feed.ship_minds(out, off, lambda day, blob: sent.append((day, blob)))["shipped"] == 0
    with f.open("a", encoding="utf-8") as fh:              # the half line completes; a new one arrives
        fh.write("\n" + json.dumps({**EV, "line": "second"}) + "\n")
    assert feed.ship_minds(out, off, lambda day, blob: sent.append((day, blob)))["shipped"] == 1
    assert json.loads(sent[-1][1])["line"] == "second"


def test_failed_ship_is_retried_and_odd_names_are_ignored(tmp_path):
    out, off = tmp_path / "outbox", tmp_path / "off.json"
    out.mkdir()
    (out / "2026-11-08.jsonl").write_text(json.dumps(EV) + "\n", encoding="utf-8")
    (out / "x;rm -rf ~.jsonl").write_text(json.dumps(EV) + "\n", encoding="utf-8")

    def down(day, blob):
        raise RuntimeError("xanadu unreachable")
    r = feed.ship_minds(out, off, down)
    assert r["shipped"] == 0 and "unreachable" in r["error"]
    sent = []
    assert feed.ship_minds(out, off, lambda day, blob: sent.append(day))["shipped"] == 1
    assert sent == ["2026-11-08"]
