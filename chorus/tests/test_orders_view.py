"""chorus.py orders: every open order is printed (oldest first) before at most 5 closed ones, so open
work never scrolls off behind finished tickets (the hourly check once said "4 open" and showed none)."""
import contextlib
import io
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import chorus  # noqa: E402


def _line(i, to="any"):
    return {"kind": "order", "id": f"o-{i:03d}", "at": f"2026-11-08T{i // 60:02d}:{i % 60:02d}:00Z",
            "from": "keath (chorus)", "to": to, "station": "anvil", "text": f"order {i}"}


def _status(i, status):
    return {"kind": "order-status", "id": f"o-{i:03d}", "at": f"2026-11-08T20:{i % 60:02d}:00Z",
            "from": "claude (msi seat)", "status": status, "note": "", "link": ""}


def test_open_orders_are_never_hidden_behind_closed_ones():
    channel = [_line(i) for i in range(1, 31)]                     # 30 orders...
    channel += [_status(i, "done") for i in range(3, 31)]           # ...28 closed, the 2 OLDEST still open
    channel += [_status(2, "working")]
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        chorus.orders_view({"channel": channel}, mine=False)
    out = buf.getvalue()
    assert "2 open" in out
    assert out.index("o-001") < out.index("o-002") < out.index("last 5 closed")   # open first, oldest first
    shown_closed = [i for i in range(3, 31) if f"o-{i:03d}" in out]
    assert shown_closed == list(range(26, 31))                     # only the newest 5 closed


def test_rerouted_counts_as_closed():
    channel = [_line(1), _line(2), _status(1, "rerouted")]
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        chorus.orders_view({"channel": channel}, mine=False)
    out = buf.getvalue()
    assert "1 open" in out and out.index("o-002") < out.index("o-001")
