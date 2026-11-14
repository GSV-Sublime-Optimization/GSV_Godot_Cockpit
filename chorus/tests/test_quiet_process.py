import quiet_process


def test_background_command_requests_no_window_on_windows(monkeypatch):
    calls = []
    monkeypatch.setattr(quiet_process.os, "name", "nt")
    monkeypatch.setattr(quiet_process.subprocess, "CREATE_NO_WINDOW", 0x08000000, raising=False)
    monkeypatch.setattr(quiet_process.subprocess, "run", lambda *a, **kw: calls.append((a, kw)))
    quiet_process.run(["gh", "--version"], capture_output=True, creationflags=4)
    assert calls[0][1]["creationflags"] == 0x08000004
    assert calls[0][1]["capture_output"] is True


def test_background_command_remains_portable(monkeypatch):
    calls = []
    monkeypatch.setattr(quiet_process.os, "name", "posix")
    monkeypatch.setattr(quiet_process.subprocess, "run", lambda *a, **kw: calls.append((a, kw)))
    quiet_process.run(["ssh", "-V"], capture_output=True)
    assert "creationflags" not in calls[0][1]
