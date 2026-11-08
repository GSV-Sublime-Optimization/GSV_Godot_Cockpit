"""Shared fixtures for the agent-protocol tests: a small, frozen feed.json-shaped colony.
Nothing here touches xanadu, the MSI or GitHub."""
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

NOW = float(int(time.time()))   # "now", so the CLI (which reads the clock) and the fixtures agree
HEAD_A = "a" * 40
HEAD_B = "b" * 40
HEAD_C = "c" * 40


def iso(t: float) -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


def marker(head: str, verdict: str = "approve", actor: str = "agent/codex") -> str:
    return f"review text\n<!-- gsv-review: actor={actor} verdict={verdict} head={head} -->"


def pr(repo, number, stage, head="", author=None, reviewers=(), title="feat: a thing"):
    return {"repo": repo, "number": number, "title": title, "stage": stage, "head": head, "draft": stage == "draft",
            "url": f"https://github.com/GSV-Sublime-Optimization/{repo}/pull/{number}",
            "created": iso(NOW - 5 * 3600), "reviewers": list(reviewers), "author": author}


I3 = {"name": "i3 Claude", "family": "Claude", "rig": "i3"}
CODEX = {"name": "Codex", "family": "Codex", "rig": "cloud"}
SOME_CLAUDE = {"name": "a Claude", "family": "Claude", "rig": None}


@pytest.fixture
def colony_feed():
    """A colony with: a healthy MSI, an i3 whose docker check fails for a BIOS reason, an L9 that is ok,
    four open PRs in different stages, one approved PR, a Steward card and an open suggestion."""
    hb = lambda checks: {"at": iso(NOW - 60), "checks": checks, "green": all(c["ok"] for c in checks)}  # noqa: E731
    return {
        "heartbeats": {"msi": hb([{"name": "litellm", "ok": True}]),
                       "i3": hb([{"name": "docker", "ok": False, "detail": "engine not running"}]),
                       "l9": hb([{"name": "ollama-mind", "ok": True}])},
        "doctor": [{"key": "i3:docker", "verdict": "VT-x is disabled in the BIOS: Keath must enable it at the machine",
                    "evidence": ["systeminfo: Virtualization Enabled In Firmware: No"]}],
        "backup": {"set": "2026-11-08", "age_h": 2.0}, "mirror": {"age_h": 1.0, "ok": True, "failures": 0},
        "spine": {"up": 1, "total": 1, "services": [{"name": "litellm", "up": True}]},
        "work": {"claims": [], "at_risk": []},
        "steward_cards": [{"file": "REQUEST-01.md", "title": "make xanadu's network survive a reboot", "age_d": 3}],
        "prs_open": [
            pr("dev", 430, "needs-review", HEAD_A, author=I3, title="fix(mirror): keep deleted refs"),
            pr("dev", 431, "needs-review", HEAD_B, author=CODEX),
            pr("Dev-Mentor", 286, "approved", HEAD_C, author=CODEX, reviewers=["agent/claude-code"]),
            pr("dev", 432, "reviewed", HEAD_A, author=SOME_CLAUDE, reviewers=["agent/codex"]),
            pr("dev", 433, "draft"),
        ],
        "channel": [
            {"at": iso(NOW - 3000), "from": "codex", "kind": "suggestion", "text": "show the PR head sha on the card"},
        ],
    }
