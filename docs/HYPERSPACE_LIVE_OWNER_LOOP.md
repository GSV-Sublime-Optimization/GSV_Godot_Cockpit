# Live owner re-observation from a Godot agent handoff

[Msg⛛{GPT6-HYPERSPACE-OWNER-ROUNDTRIP-20261108}]

The previously implemented `EXPORT AGENT HANDOFF` is a safe, inert source capsule. It now supports an optional second stage: an AI or terminal worker can **read** the exact owning KiloCore Studio record and return a bounded evidence index. This removes the need to scrape the UI, paste mission prompts or infer completion from colors.

## Real path on MSI

```text
GET Studio /api/missions?limit=12 (actual loopback owner)
    ↓
Godot HYPERSPACE / native 3D selected mission
    ↓
EXPORT AGENT HANDOFF / user://hyperspace-agent-handoff.json
    ↓
py -3 tools/workstation/agent_handoff.py --json --observe-studio "<Godot-exported-file>"
    ↓
GET Studio /api/missions/<exact validated mission ID>
    ↓
allowlisted owner observation / status, risk, repo, receipt ID,
reported acceptance counts, validator state, commit IDs and changed paths
```

**Verified 2026-11-08 on MSI:** `WORKSTATION_LIVE_STUDIO_HANDOFF_PASS`, exact source mission ID `msn_9ab3fa38b213`. The real CLI read the *same* Godot-created file, then observed source mission `succeeded`, risk `R2`, receipt `rcpt_02bdf3fbfa9c4ece9c8943ba09907e50`, 3/3 owner-reported criteria, and one commit. It returned `validator=NOT_REPORTED` and **`artifact_verified=false`**, despite runner exit 0. This is historical mission evidence, not a claim that the live cockpit authored or approved the mission or produced a working build.

The temporary live smoke script is deliberately NOT in the offline `.gsv/build.yaml` check. The official gate uses fixture-only, network-free unit tests. To repeat the live read-only smoke when Studio is already running:

```powershell
$godot = 'C:\dev\tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --audio-driver Dummy --path . --script res://tests/workstation_agent_live_owner_smoke.gd
$handoff = Join-Path $env:APPDATA 'Godot\app_userdata\ΞNuSyQ Colony Workstation - HOLO DIVE\hyperspace-agent-handoff.json'
py -3 tools/workstation/agent_handoff.py --json --observe-studio "$handoff"
```

This smoke overwrites the local `user://hyperspace-agent-handoff.json` with the **latest selected real mission** from Studio, so deliberately copy a capsule elsewhere before running if it matters.

## Authority and fault model

- The CLI accepts only a validated `gsv.hyperspace-agent-handoff.v1` file, then **GETs** a hard-coded path from `127.0.0.1` on `GSV_STUDIO_ENTITY_PORT` (default 7340). No arbitrary host, scheme, URL, redirects, POST, shell, credentials, tokens or persistence.
- Requests have a 131 KB body limit and a bounded timeout. Outputs omit raw mission objectives, summaries, notes, chat logs, tool data and sensitive unvalidated fields. An ambiguous/failed lookup fails closed.
- **Mission:** validates exact mission ID, lifecycle, risk and source repo equality (if supplied); returns observed evidence without declaring running/approval/merge/artifact quality.
- **Project:** GETs Studio `/api/projects`; only a current `OBSERVED` catalogue with the **exact path and branch** makes `ready_for_composer=true`. An `UNKNOWN` discovery source is a visible non-admission state.
- **Rig:** read-only `/api/entity/bodies` and explicitly requires identity/remote-work/execution permission flags to stay false in that observation.
- **Service:** uses Studio health projection; unavailable colony observations remain UNKNOWN.
- **Capability:** says `REQUIRES_LIVE_PROBE`, with no invented provider network call. Tool qualification, auth, scope and budget must come from each owning provider.
- A created, succeeded or receipt-bearing mission is not automatically a validated build. The boolean `artifact_verified=false` is intentional until an independent owning artifact gate provides such evidence.
- A project listing may be slow/unavailable. In the observed MSI session, the canonical Kilo_Core Project Constellation command took ~30.66 seconds for 73 projects, exceeding Studio's 15-second process timeout, producing `state=UNKNOWN`. This is an upstream performance defect; do not bypass it by using an old/static catalogue. The independently tested owner repair is [Kilo_Core PR #697](https://github.com/GSV-Sublime-Optimization/Kilo_Core/pull/697), still draft and not deployed to the running Studio server.

## Tests

The `tools/workstation/tests/test_studio_reobserve.py` suite uses injected fixture readers without opening a network connection, covering exact owner identity, repo drift, no false success, unsafe URLs, invalid acceptance and validator types, stale project refusal, rig non-admission and unknown provider states. The existing `.gsv/build.yaml` runs these together with the older portable handoff tests.

## Outstanding production acceptance

A real eligible project scan, a newly created mission, R2 authorization, an actual source edit/validator/playtest, a screenshot and independent review remain separate. The command-line consumer provides **current task evidence**; it is not yet an agent terminal or continuous background controller.
