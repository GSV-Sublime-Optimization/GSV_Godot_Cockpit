# Fleet telemetry feed — read-only probe for the holographic cockpit

## Pattern

The cockpit runs **no shell** and holds **no credentials**. A probe script on the
rig writes **one typed JSON snapshot**; the cockpit reads that file with caps +
schema checks + age — the same pattern as Mind View's `mind_feed.py`:

```
fleet_feed.ps1  (MSI, via mssh or the MuseFleetFeed scheduled task, every 5 min)
      |
      v
C:\GSV\state\fleet-telemetry.json   (schema kilocore.fleet-telemetry.v1)
      |
      v
FleetTelemetryReader (Godot) — 64 KB cap, schema-pinned, age/stale states
      |
      v
Rig layers in the holographic volume (MSI / i3 / L9 / Xanadu)
```

## Snapshot schema (`kilocore.fleet-telemetry.v1`)

```json
{
  "schema": "kilocore.fleet-telemetry.v1",
  "generated_at": "2026-11-08T00:12:00Z",
  "generated_unix_ms": 1762564320000,
  "probe_host": "MSI-KATANA",
  "rigs": {
    "msi": {
      "state": "live",
      "ram_free_mb": 1234, "ram_total_mb": 32768, "ram_free_pct": 3.8,
      "cpu_load_pct": 12,
      "services": {"studio": "up", "gateway": "up", "hub": "up", "router": "up",
                   "dispatch": "up", "chatdev": "up", "devmentor": "up",
                   "ollama": "up", "openclaw": "up"},
      "tasks": {"KiloCore-Public-Gateway": "Ready", "...": "Ready"},
      "note": "MSI-KATANA, probed locally"
    },
    "i3":    {"state": "live|unavailable|unknown", "tcp22": "open|closed|timeout",
              "ssh": "ok|failed|not_attempted", "ram_free_mb": null, "...": null,
              "note": "..."},
    "l9":    {"state": "...", "ssh": "...", "...": null, "note": "..."},
    "xanadu": {"state": "live|unavailable", "services": {"icecast": "up|unknown"},
               "note": "HTTP only — SSH pause stands"}
  }
}
```

- `state` is one of `live | unavailable | degraded | unknown`. A rig with no live
  source is `unavailable`/`unknown` with a reason in `note` — never faked live.
- `services` values are `up | down | unknown`. `tasks` values are the Windows
  scheduled-task states (`Ready`, `Running`, `Disabled`, `not_found`).
- The Godot projection (`FleetTelemetryProjection.gd`) admits only these fields,
  bounded (64 KB body, ≤32 services, ≤16 tasks, strings capped). Anything else
  is rejected with a fixed reason; the reader then reports `unavailable`.

## What the probe reads (all read-only)

- **MSI (local):** CIM `Win32_OperatingSystem` (RAM) + `Win32_Processor` (CPU
  load); HTTP GETs (3 s timeout) to Studio :7340, gateway :8001, Hub :8000,
  router :9001, dispatch :9002 (root 404 = process live), ChatDev :7338,
  Dev-Mentor :7337, Ollama :11434; TCP connect to OpenClaw :18789 (never
  HTTP GET — it is a WebSocket/MCP gateway and GET times out); `Get-Process
  ollama`; `Get-ScheduledTask` for KiloCore-Public-Gateway,
  KiloCore-Studio-Backend, KiloCore-Mirror-Sync, KiloCore-Heartbeat-MSI.
- **i3:** TCP :22 (2 s); SSH via alias `i3` (LAN 10.0.0.193, user
  `studio cuckoo`) then `i3-tailscale` (100.102.251.35), each hard-capped at
  8 s — a hanging session-0 SSH can never stall the feed. Remote command is
  read-only (CIM memory + a short process list). GameAttract director has no
  known endpoint: recorded as not-yet-probed until one is found.
- **L9:** LAN alias `kilodesktop` (10.0.0.197, user `jacob`) via Git's bundled
  `ssh.exe` (MSI Windows OpenSSH returns exit 255), hard-capped at 8 s.
  Remote commands contain no shell metacharacters (no pipes/redirects — the
  remote default shell is cmd): Windows CIM form first, Linux `free -m`
  fallback, parsed locally.
- **Xanadu:** HTTP ONLY — Icecast `status-json.xsl` on :8000. **Never SSH.**
  The pause stands until Keath lifts it.

## Install

```powershell
# copy into place (versioned here, lives there)
New-Item -ItemType Directory -Force C:\GSV\tools\fleet-feed | Out-Null
Copy-Item tools\fleet_feed\fleet_feed.ps1 C:\GSV\tools\fleet-feed\fleet_feed.ps1

# refresh every 5 min (read-only probe)
$act = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\GSV\tools\fleet-feed\fleet_feed.ps1"
$trg = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName "MuseFleetFeed" -Action $act -Trigger $trg `
  -User "NT AUTHORITY\SYSTEM" -RunLevel Highest -Force
```

## Run once (manual)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\GSV\tools\fleet-feed\fleet_feed.ps1
Get-Content C:\GSV\state\fleet-telemetry.json
```
