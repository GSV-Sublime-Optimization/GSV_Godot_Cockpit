import json

import chorus


def test_brief_cursors_are_independent_and_legacy_cursor_is_preserved(tmp_path, monkeypatch, capsys):
    legacy = tmp_path / "cli.seen"
    monkeypatch.setattr(chorus, "SEEN", legacy)
    monkeypatch.setattr(chorus, "needs", lambda data: [])
    feed = {"_age_s": 900, "channel": [{"at": "2026-11-08T12:00:00Z", "from": "other", "text": "hello"}]}
    monkeypatch.setattr(chorus, "SEAT", "claude (msi seat)")
    chorus.brief(feed, False)
    assert legacy.is_file()
    monkeypatch.setattr(chorus, "SEAT", "codex")
    assert len(chorus.unseen(feed)) == 1
    chorus.brief(feed, False)
    assert chorus.unseen(feed) == []
    assert legacy.read_text() == "2026-11-08T12:00:00Z"
    assert chorus.seen_path("../../codex").parent == tmp_path
    capsys.readouterr()


def test_json_brief_reports_age_without_advancing_cursor(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(chorus, "SEEN", tmp_path / "cli.seen")
    monkeypatch.setattr(chorus, "SEAT", "codex")
    monkeypatch.setattr(chorus, "needs", lambda data: [])
    feed = {"_age_s": 345.5, "channel": [{"at": "2026-11-08T12:00:00Z", "from": "other", "text": "hello"}]}
    chorus.brief(feed, True)
    result = json.loads(capsys.readouterr().out)
    assert result["feed_age_s"] == 345.5
    assert len(result["new_messages"]) == 1
    assert not chorus.seen_path("codex").exists()
