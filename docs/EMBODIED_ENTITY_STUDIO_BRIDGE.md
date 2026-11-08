# Embodied Colony Entity: Godot → Studio sensory bridge (Slice 0)

The requested entity is **not** a Godot imitation of the agent ecosystem, an
unrestricted shell, a self-authorizing model, or a second mission database.
The Godot process is an *embodied client* with local perception, optional
native policy inference and a visible/interactive presence. Actual authority
continues to reside with each owning service.

## Ownership map

| Contract owner | What it owns | How Godot gains it |
| --- | --- | --- |
| `KiloCore-Studio` | Missions, risk R0-R3, budget, approvals, cancellation, execution/receipt ledger | First read-only `GET /api/health`; later authenticated mission proposal with normal Studio risk gates |
| `Kilo_Core` | Fleet identity, capability admission, policy, resource/thermal budgets | Typed, source-attributed observation supplied by Studio/authorized backend |
| `NuSyQ-Hub` and Gateway | Tool/missions routing and available authenticated MCP surfaces | Broker-side MCP client, not a Godot-owned arbitrary MCP proxy |
| Serena | Code symbols and language-server analysis | Broker calls a Serena-scoped tool; results are evidence, not permission to edit |
| Hermes / OpenClaw / Goose / other harnesses | Specialized agent sessions and tooling | Existing harness adapters and actual readiness/capability canaries; never pretend aliases are running processes |
| Culture Ship | Strategy and self-reporting observations | Existing event/insight feed with provenance, not an alternate policy engine |
| Terminal Depths / game adapters | Real game state, legal actions and outcomes | Typed read-only observations; optional explicit authorized action channel in a later slice |
| Godot | Scene tree, sensors, physics/simulation, body state, interaction, replayable local decisions | Native GDScript/GDExtension; cannot mint server authority |

The `StudioHealthProjection` intentionally admits **only** schema,
nonnegative mission counts, and the thermal-gate state. The local `StudioObservationBridge`:
* makes one asynchronous, explicit GET to `http://127.0.0.1:7340/api/health`;
* never posts missions, executes commands, reads files or calls remote peers;
* distinguishes unknown before first observation, unavailable on failure,
  live after a validated HTTP+schema result, and stale after failure or expiry;
* does not import raw mission bodies, secrets or connector tokens into the
  Godot scene tree.

The 15-second freshness threshold is an interface budget, not proof the
source API measured each individual fleet rig within that period.

## Slice 1 — Constellation sensor (Studio `GET /api/projects`)

The Studio `/api/projects` scan is slow: its own backend runs
`project_constellation.py` and times out after 15s, so the endpoint answers
in ~15s with a graceful `UNKNOWN` envelope
(`kilocore-studio.projects-scan.v2`, `count: null`, `projects: null`) when
the scan does not finish. A 4s timeout would fail every time, and polling
the endpoint on the 15s sensory tick would stack slow requests. So the
constellation sensor is **bounded and cached**, not a poller:

* `StudioConstellationBridge` — async GET only to hardcoded
  `http://127.0.0.1:7340/api/projects`; 20s timeout (the server needs ~15s
  to answer); 256KB body cap; one request in flight; no redirect following;
  a 120s minimum refresh (observe() is a no-op inside the window unless
  forced); 300s freshness. The observation carries `age_ms` so the consumer
  always knows how old the cached constellation is.
* `StudioProjectsProjection` — schema-pinned parser for
  `kilocore-studio.projects-scan.v2`. Admits only schema, scan state/source,
  `generated_at`, a bounded project count, and at most 50 project
  name/status pairs (malformed entries are skipped and counted, never fatal).
  A well-formed envelope whose scan produced no constellation (null count /
  null projects) is an honest `unavailable` with the fixed reason
  `constellation_scan_unavailable` — never a fabricated `live`. No project
  bodies, paths, prompts, secrets, or tokens cross.
* `EntitySession` observes the constellation on its own slow cadence (180s
  by default, separate from the 15s health tick) and records
  `constellation_observation` events in the same bounded history. The
  self-model gains a `constellation` key and a `studio.projects.read`
  capability (`mutation: false`).

## Slice 2 — Gateway health sensor (`GET 127.0.0.1:8001/health`)

The Mind's second sense, wired to the routing layer in the same bridge
pattern. The gateway `/health` endpoint answers `{"status":"ok"}` (15
bytes); `/mcp` GET returns a discovery document (version 0.2.0) and is
**not** sensed here — the MCP surface is a POST-based JSON-RPC API, and
this slice reads health only.

* `GatewayHealthProjection` — admits only the `status` string (bounded,
  64 chars). `ok` is `live`; any other non-empty status is an honest
  `unavailable` with the fixed reason `gateway_not_ok`. Malformed JSON,
  missing/non-string status, and oversized bodies are rejected closed.
* `GatewayObservationBridge` — async GET only to hardcoded
  `http://127.0.0.1:8001/health`; 4s timeout; 8KB body cap; one request in
  flight; no redirect following; 15s freshness; the same
  unknown/unavailable/live/stale state machine.
* `EntitySession` observes the gateway on the same 15s tick as Studio
  health (both are fast senses) and records `gateway_health_observation`
  events. The self-model gains a `gateway` key and a
  `gateway.health.read` capability (`mutation: false`).

## Configuration

Sensory cadence, trace bound, and timeouts are configuration with safe
defaults and bounds, enforced by setters on every assignment (not just at
load). The defaults are the values proven in Slices 0–2.

| Setting | Where | Default | Bounds |
| --- | --- | --- | --- |
| `observe_period_seconds` (health + gateway tick) | `EntitySession` | 15.0 | 2–300 s |
| `constellation_period_seconds` | `EntitySession` | 180.0 | 60–3600 s |
| `max_history_events` | `EntitySession` | 64 | 8–1024 |
| `http_timeout_seconds` (health bridge) | `StudioObservationBridge` | 4.0 | 1–30 s |
| `freshness_msec` (health bridge) | `StudioObservationBridge` | 15000 | 5000–300000 ms |
| `http_timeout_seconds` (constellation bridge) | `StudioConstellationBridge` | 20.0 | 5–60 s |
| `freshness_msec` (constellation bridge) | `StudioConstellationBridge` | 300000 | 60000–1800000 ms |
| `min_refresh_msec` (constellation bridge) | `StudioConstellationBridge` | 120000 | 30000–1800000 ms |
| `http_timeout_seconds` (gateway bridge) | `GatewayObservationBridge` | 4.0 | 1–30 s |
| `freshness_msec` (gateway bridge) | `GatewayObservationBridge` | 15000 | 5000–300000 ms |

Body caps (128KB health, 256KB projects, 8KB gateway) and the 50-project
admission cap are safety bounds, not tuning knobs — they stay constants.

## Visible presence

`EntitySession.tscn` carries a `StatusReadout` `Label` (top-left, 16pt).
`EntitySession.status_text()` returns the same four lines the label shows —
phase, tick, and actuator count; Studio state with mission counts and the
thermal gate; gateway state; constellation state with project count and
source age. Unknown/unavailable/stale states are printed honestly; the
readout never invents a live state and carries no secrets. A session built
from the script alone (no scene) has no label; `status_text()` still works
and is what the config/presence test asserts.

## Cultivation log (what is real vs planned)

| Slice | Status | Evidence |
| --- | --- | --- |
| 0 — Studio health sense | **Proven** at exact head `745f283b` (MSI, Godot 4.7.1) | `ENTITY_SESSION_PASS`, `STUDIO_ENTITY_BRIDGE_PASS` (real Studio GET /api/health 200), `ENTITY_SCENE_LIVE_PASS`, `gsv/check=success` |
| 1 — Constellation sensor | **Filed as a draft PR** (stacked on #8); negative controls written; live canary opt-in | `studio_constellation_test.gd` (projection + bridge guards); Godot run queued behind Furyline Phase B |
| 2 — Gateway health sensor | **Filed as a draft PR** (stacked on Slice 1); negative controls written; live canary opt-in | `gateway_health_test.gd`; Godot run queued behind Furyline Phase B |
| 3 — Config + visible presence | **Filed as a draft PR** (stacked on Slice 2) | `entity_config_presence_test.gd`; Godot run queued behind Furyline Phase B |
| Independent review of #8 | **Done** (comment on #8) | 2 hardening findings (redirect following, parser size cap — both applied in Slice 3), 3 test gaps, 1 note |
| Embodied policy (local ONNX/RL reflex) | Planned | Not started; needs a simulated-action baseline first |
| Mission intent (`POST /api/missions`) | Planned | Owner-approved later slice under R0/R1/R2/R3 gates; NOT this round |
| Harness adapters (Serena, Hermes, OpenClaw) | Planned | Behind the authorized broker, one at a time, with a real negative authorization test |
| Learning loop (durable redacted logs) | Planned | Godot scene tree is working state, not durable memory |
| Agent gameplay evaluation | Planned | Reproducible sims + legal-action adapters; a seed alone never makes external systems deterministic |

## How to verify

A source-only test uses fake *data*, not a fake service, to exercise negative
controls. The separately opt-in real test requires Studio to be running
locally. Use the repository's Godot 4.7 engine and standard project import.

```powershell
# Source/parse and fail-closed contract checks
& godot --headless --path . --import
& godot --headless --path . --script res://tests/studio_entity_bridge_test.gd
& godot --headless --path . --script res://tests/studio_constellation_test.gd
& godot --headless --path . --script res://tests/gateway_health_test.gd
& godot --headless --path . --script res://tests/entity_config_presence_test.gd

# Actual same-host Studio HTTP handshake, not a fabricated response
$env:GSV_STUDIO_LIVE = "1"
& godot --headless --path . --script res://tests/studio_entity_bridge_test.gd
& godot --headless --path . --script res://tests/studio_constellation_test.gd
Remove-Item Env:GSV_STUDIO_LIVE

# Actual same-host gateway HTTP handshake
$env:GSV_GATEWAY_LIVE = "1"
& godot --headless --path . --script res://tests/gateway_health_test.gd
Remove-Item Env:GSV_GATEWAY_LIVE
```

The live tests count as **R0 sensor canaries**, not ML intelligence, mission
execution, agent identity, or productive fleet work. Run them from an
isolated clone so imports and user data cannot affect occupied agent worktrees.
The constellation canary is slow by nature (~15s per fetch); the gateway
canary is fast. Do not run Godot on the MSI while Furyline Phase B proof
lanes are running — single-flight plus the 2,500 MB RAM gate.

## Next slices, each independently gated

Done (Slices 0–3 above): Studio health sense, constellation sensor,
gateway health sensor, configuration, visible presence.

1. **Contracted observation:** source-stamped fleet host pressure and admitted
   capabilities through a typed Studio/Kilo_Core endpoint, with expiry and
   explicit unknown/denied states. Never copy live credentials into Godot.
2. **Embodied policy:** a local ONNX policy or native RL reflex over bounded,
   *simulated* action choices; compare its decisions against deterministic
   baselines. Real high-risk actions remain subject to the same backend gate.
3. **Mission intent:** route proposed goals to Studio's existing
   `POST /api/missions` with explicit project, acceptance, risk and budget.
   R2 remains human-reviewed and R3 proposal-only.
4. **Harness adapters:** Serena, Hermes, OpenClaw, and local model calls live
   **behind** the existing authorized broker. Add one at a time with a
   real negative authorization test and an actual tool invocation receipt.
5. **Learning loop:** use durable, redacted backend event logs/SQLite receipts
   for model training and memory retrieval. The Godot scene tree is working
   state and presentation, **not** durable long-term memory.
6. **Agent gameplay evaluation:** Godot can host reproducible simulations,
   legal-action adapters, and actor policy inference; a deterministic seed
   alone never makes external networks, concurrent services or LLM outputs
   deterministic. Log actual observations/actions and replay IDs.

Engine-specific accelerator paths (ncnn, ONNX, IREE, NobodyWho) remain
**candidates** until version compatibility, licensing, resource contention,
and native crash isolation are demonstrated on the owning rig. Existing
Ollama/LiteLLM model routing is the initial reasoning path.

## Non-goals

No consciousness or sentience is established or asserted by this feature.
A persistent identity, active self-model, and adaptive memory can make the
entity behave coherently without implying subjective experience.
No ambient shell access, self-signed privileged commands, automatic GitHub
merges, remote-service exposure or new mutation plane is introduced.


## Four physical body observations (next read-only seam)

The same `EntitySession.tscn` now mounts **two** local asynchronous sensors:
- existing Studio health (`/api/health`) for the mission/thermal snapshot;
- new `FleetBodiesBridge.gd` (`/api/entity/bodies`) for four fixed-body
  slots: MSI, I3, L9 and Xanadu. Studio owns the read projection in
  [KiloCore-Studio #56](https://github.com/GSV-Sublime-Optimization/KiloCore-Studio/pull/56).
  Physical R0 source is [FleetBridge #51](https://github.com/GSV-Sublime-Optimization/FleetBridge/pull/51).
  No arbitrary SSH client or tool runner was added to Godot.

The entity keeps one bounded session history; per-body records are
`reported_fresh`, `stale`, `invalid`, or `unknown`. Any source asserting
`identity_attested`, `remote_work_admitted` or
`execution_authorized` is **rejected** by the new Godot projection. The
proof is read-only data flow, not self-authentication or an admission grant.

**Real end-to-end test, 2026-11-07 evening:** A single exact-code Python
observer, sent over preexisting authenticated SSH stdin (no remote install),
ran successfully on I3, L9 and Xanadu, and locally on MSI. Four observations
were captured on MSI only. A separate isolated Studio Python server (port
chosen locally, loopback only) exposed the opt-in observation directory;
Godot 4.7.1 instantiated `EntitySession.tscn`, fetched all four physical
reports over **real** `GET /api/entity/bodies`, and exited with
`ENTITY_FOUR_BODIES_LIVE_PASS`. All four were reported fresh, each with
`execution_authorized=false`. The temporary server exited cleanly.

An optional inspection scene is `res://scenes/EntityObservationConsole.tscn`.
It presents the reported machine states, not credentials, tool controls,
or a privileged task editor. **The installed Studio service at 7340 will
continue to show all four bodies UNKNOWN until PR #56 is independently
reviewed, merged, deployed, and pointed at collected receipts.**
Do not run a competing public Studio server or open remote access to make
a demonstration look live.

Port override `GSV_STUDIO_ENTITY_PORT` exists for isolated same-host tests
only; it changes the loopback port, never the host. No production startup
config, background listener or scheduled collection task is installed by
this Godot PR. Missing observations expire rather than being silently
replaced by canned telemetry.

The next genuine intelligence milestone is *typed capability qualification
and an authorized read-only tool invocation* through the owning Studio/Kilo_Core
broker. Native learning policies and durable memory remain separate future
milestones, not shipped claims.
