"""doctor.py: read-only diagnosis for what CHORUS reports as failing.

For every failing heartbeat check that has a probe, it measures the likely cause and returns
evidence plus a verdict ("confirmed: ...", "not confirmed: ...", "unknown: ..."). It never fixes
anything: it changes no state, starts nothing, and only reads. Results are cached by the feeder
(5 min) and shown beside the item they explain.

    python chorus/doctor.py            # diagnose everything failing in feed.json now
"""
from __future__ import annotations

import base64
import json
import subprocess
import time
import urllib.request
from pathlib import Path

import portable

HERE = Path(__file__).resolve().parent
SSH = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "LogLevel=ERROR"]


def _http_ms(url: str, timeout: float = 15) -> tuple[int | None, float]:
    t = time.perf_counter()
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            r.read(1024)
            code = r.status
    except OSError:
        code = None
    return code, round((time.perf_counter() - t) * 1000)


def msi_dev_mentor() -> dict:
    ev, slow = [], 0
    for path in ("/health", "/api/capabilities", "/api/spine/services"):
        code, ms = _http_ms(f"http://127.0.0.1:7337{path}")
        ev.append(f"{path}: {code or 'no answer'} in {ms} ms")
        slow += code is None or ms > 3000
    if slow:
        return {"verdict": "confirmed: Terminal Depths stalls under load (the event-table bug Dev-Mentor#286 fixes)", "evidence": ev}
    return {"verdict": "not confirmed: all routes answer quickly now; the failure was intermittent", "evidence": ev}


def i3_docker() -> dict:
    ps = ("$p=Get-CimInstance Win32_Processor; $c=Get-CimInstance Win32_ComputerSystem; "
          "$s=(Get-Service com.docker.service -EA SilentlyContinue).Status; "
          "\"vtx=$($p.VirtualizationFirmwareEnabled) hypervisor=$($c.HypervisorPresent) docker_service=$s\"")
    enc = base64.b64encode(ps.encode("utf-16-le")).decode()      # no quoting survives ssh -> cmd -> powershell; this does
    r = subprocess.run(SSH + [portable.I3_SSH, f"powershell -NoProfile -EncodedCommand {enc}"], capture_output=True, text=True, timeout=40)
    line = (r.stdout or "").strip().splitlines()[-1:] or ["no answer"]
    ev = [f"i3 says: {line[0]}"]
    if "vtx=False" in line[0]:
        return {"verdict": "confirmed: VT-x is off in the i3's BIOS, so WSL and Docker cannot start", "evidence": ev}
    if "vtx=True" in line[0]:
        return {"verdict": "not confirmed: VT-x is on; look at the Docker Desktop service and WSL next", "evidence": ev}
    return {"verdict": "unknown: the i3 did not answer over SSH", "evidence": ev}


def i3_ollama() -> dict:
    code, ms = _http_ms(f"{portable.I3_OLLAMA}/api/version", 10)
    return {"verdict": "confirmed: Ollama on the i3 is unreachable from MSI" if code is None else "not confirmed: Ollama answers",
            "evidence": [f"/api/version: {code or 'no answer'} in {ms} ms"]}


def msi_docker() -> dict:
    t = time.perf_counter()
    try:
        r = subprocess.run(["docker", "version", "--format", "{{.Server.Version}}"], capture_output=True, text=True, timeout=20)
        ok, out = r.returncode == 0, (r.stdout or r.stderr).strip()[:120]
    except subprocess.TimeoutExpired:
        ok, out = False, "no answer in 20 s"
    ms = round((time.perf_counter() - t) * 1000)
    builds = "n/a (not Windows)"
    if portable.WINDOWS:
        builds = subprocess.run(["powershell", "-NoProfile", "-Command",
                                 "(Get-CimInstance Win32_Process -Filter \"Name='docker.exe'\" | ? CommandLine -match ' build ').Count"],
                                capture_output=True, text=True, timeout=20).stdout.strip() or "0"
    ev = [f"docker version: {out} ({ms} ms)", f"docker builds running: {builds}"]
    if ok:
        return {"verdict": "not confirmed: the Docker engine answers", "evidence": ev}
    return {"verdict": "confirmed: MSI's Docker engine is not answering; containers may still run, but nothing can be started or inspected", "evidence": ev}


def spine_container(name: str, container: str, url: str):
    """Probe for a spine service that runs as a container: is it running, what is its restart policy, does it answer."""
    def probe() -> dict:
        r = subprocess.run(["docker", "inspect", container, "--format",
                            "{{.State.Status}}|{{.State.ExitCode}}|{{.State.FinishedAt}}|{{.HostConfig.RestartPolicy.Name}}"],
                           capture_output=True, text=True, timeout=20)
        state = (r.stdout or "").strip() or "missing"
        code, ms = _http_ms(url, 8)
        ev = [f"{container}: {state}", f"{url}: {code or 'no answer'} in {ms} ms"]
        parts = state.split("|")
        if parts[0] == "exited" and len(parts) > 3 and parts[3] == "no":
            return {"verdict": f"confirmed: {container} exited (code {parts[1]}) and its restart policy is 'no', so it stayed down after Docker restarted", "evidence": ev}
        if code:
            return {"verdict": f"not confirmed: {name} answers now", "evidence": ev}
        return {"verdict": f"unknown: {container} is {parts[0]} but {url} does not answer", "evidence": ev}
    return probe


SPINE_PROBES = {"openwebui": spine_container("OpenWebUI", "ai-openwebui", "http://127.0.0.1:8080/")}


PROBES = {"msi:docker": msi_docker, "msi:dev-mentor": msi_dev_mentor, "i3:docker": i3_docker, "i3:ollama": i3_ollama}


def diagnose(feed: dict) -> list[dict]:
    out = []
    for rig, hb in (feed.get("heartbeats") or {}).items():
        for c in hb.get("checks", []):
            key = f"{rig}:{c.get('name')}"
            if c.get("ok") or key not in PROBES:
                continue
            try:
                res = PROBES[key]()
            except (OSError, subprocess.SubprocessError, ValueError) as e:
                res = {"verdict": f"unknown: probe failed ({e.__class__.__name__})", "evidence": []}
            out.append({"key": key, "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **res})
    for svc in (feed.get("spine") or {}).get("services", []):
        if not svc.get("up") and svc.get("name") in SPINE_PROBES:
            try:
                res = SPINE_PROBES[svc["name"]]()
            except (OSError, subprocess.SubprocessError, ValueError) as e:
                res = {"verdict": f"unknown: probe failed ({e.__class__.__name__})", "evidence": []}
            out.append({"key": f"spine:{svc['name']}", "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **res})
    return out


if __name__ == "__main__":
    feed = json.loads((HERE / "feed.json").read_text(encoding="utf-8"))
    for d in diagnose(feed):
        print(f"{d['key']}: {d['verdict']}")
        for e in d["evidence"]:
            print(f"    {e}")
