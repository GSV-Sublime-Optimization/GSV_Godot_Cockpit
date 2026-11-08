"""portable.py: where CHORUS finds things on whichever rig it runs. Every default is the MSI's value.

| Env var | Default | What |
|---|---|---|
| CHORUS_XANADU | `xanadu` (an ~/.ssh/config alias); `local` when the hostname is xanadu | how to reach the steward |
| CHORUS_ROOTS | `C:/dev/active` and `K:/dev/worktrees` (os.pathsep-separated) | where colony checkouts live |
| COLONY_PY / COLONY_PYTHON | `C:/dev/tools/colony/colony.py` / `python` (Windows), this Python elsewhere | the claims board |
| CHORUS_I3_SSH | `i3` (an ~/.ssh/config alias) | the doctor's i3 probe |
| CHORUS_I3_OLLAMA | `http://100.102.251.35:11434` | the doctor's i3 Ollama probe |
"""
from __future__ import annotations

import os
import platform
import sys
from pathlib import Path

WINDOWS = os.name == "nt"
SSH_OPTS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8"]


def env(name: str, default: str) -> str:
    v = os.environ.get(name, "").strip()
    return v or default


def xanadu() -> str:
    on_xanadu = platform.node().split(".")[0].lower() == "xanadu"
    return env("CHORUS_XANADU", "local" if on_xanadu else "xanadu")


def xanadu_cmd(remote: str) -> list[str]:
    """argv that runs a POSIX shell command where the steward lives: over SSH, or in a local sh on xanadu."""
    host = xanadu()
    if host == "local":
        return ["sh", "-c", remote]
    return ["ssh", *SSH_OPTS, host, remote]


def roots() -> list[Path]:
    raw = os.environ.get("CHORUS_ROOTS", "").strip()
    if raw:
        return [Path(p).expanduser() for p in raw.split(os.pathsep) if p.strip()]
    return [Path("C:/dev/active"), Path("K:/dev/worktrees")]


COLONY = Path(env("COLONY_PY", "C:/dev/tools/colony/colony.py"))
COLONY_PYTHON = env("COLONY_PYTHON", "python" if WINDOWS else sys.executable)
I3_SSH = env("CHORUS_I3_SSH", "i3")
I3_OLLAMA = env("CHORUS_I3_OLLAMA", "http://100.102.251.35:11434").rstrip("/")
