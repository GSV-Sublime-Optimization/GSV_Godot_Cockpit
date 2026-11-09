## Slice 3 — Configuration + visible presence + doc

Stacked on Slice 2 (base `muse/mind-slice2-gateway-20261107`).
Makes the senses tunable and the Mind's state readable on screen, and
extends the doc with the new sensors, a cultivation log, and the updated
next-slice map. **No authority change, no actuators (0 stays), no POST,
no secrets, no arbitrary URLs, no remote peers.**

### Configuration

Sensory cadence, trace bound, and timeouts are now configuration with safe
defaults and bounds, enforced by setters on every assignment:

| Setting | Where | Default | Bounds |
| --- | --- | --- | --- |
| `observe_period_seconds` (health + gateway tick) | `EntitySession` | 15.0 | 2–300 s |
| `constellation_period_seconds` | `EntitySession` | 180.0 | 60–3600 s |
| `max_history_events` | `EntitySession` | 64 | 8–1024 |
| `http_timeout_seconds` / `freshness_msec` | each bridge | 4.0/15000 (health, gateway), 20.0/300000 (constellation) | 1–30 s / 5000–300000 ms (health, gateway), 5–60 s / 60000–1800000 ms (constellation) |
| `min_refresh_msec` | `StudioConstellationBridge` | 120000 | 30000–1800000 ms |

Body caps (128KB health, 256KB projects, 8KB gateway) and the 50-project
admission cap are safety bounds, not tuning knobs — they stay constants.

### Visible presence

- `EntitySession.tscn` gains a `StatusReadout` `Label` (top-left, 16pt).
- `EntitySession.status_text()` returns the same four lines the label
  shows: phase/tick/actuator count; Studio state with mission counts and
  the thermal gate; gateway state; constellation state with project count
  and source age. Unknown/unavailable/stale states print honestly; the
  readout never invents a live state and carries no secrets.

### Review findings applied (from the independent review of #8)

- **Redirect following disabled** — all three bridges now set
  `HTTPRequest.max_redirects = 0` in `_ready()` (Godot's default is 8; a
  compromised local service could otherwise redirect the GET).
- **Defense-in-depth size cap in the parser** — `StudioHealthProjection`
  now rejects bodies over 131,072 chars before parsing (`health_response_too_large`),
  so the cap no longer lives only in the bridge.

### Doc

`docs/EMBODIED_ENTITY_STUDIO_BRIDGE.md` gains: Slice 1 and Slice 2
sections, a configuration table, a visible-presence section, a
**cultivation log** (real vs planned), the new test commands (including
the `GSV_GATEWAY_LIVE=1` canary), and the updated next-slice map with
Slices 0–3 marked done.

### Verification (queued)

- `tests/entity_config_presence_test.gd` follows the #8 pattern: asserts
  the floor and ceiling clamps on all three session settings, the honest
  readout text before observation (unknown states, `actuators 0`, no
  secrets), the 8-event bound after 12 injections, and that the scene
  carries a `StatusReadout` label with non-empty phase text. No live
  services needed. **gdparse passes on the VM.**
- Godot verification on the MSI is **queued behind Furyline Phase B**
  (single-flight + 2,500 MB RAM gate; Phase B signals completion via
  `~/workspace/colony-loop/furyline-verdict2/PHASE-B-DONE.md`). Run when
  the gate clears: `--headless --import`, then the test script, then the
  existing #8 + Slice 1 + Slice 2 tests for regression.

### Files

- `scripts/entity/EntitySession.gd` (config exports + `status_text()` + readout)
- `scenes/EntitySession.tscn` (`StatusReadout` label)
- `scripts/entity/StudioObservationBridge.gd` (config + `max_redirects = 0`)
- `scripts/entity/StudioConstellationBridge.gd` (config)
- `scripts/entity/GatewayObservationBridge.gd` (config)
- `scripts/entity/StudioHealthProjection.gd` (parser size guard)
- `tests/entity_config_presence_test.gd` (new)
- `docs/EMBODIED_ENTITY_STUDIO_BRIDGE.md` (extended)

Draft — no merge. Stacks: #8 → #9 (Slice 1) → #10 (Slice 2) → this.
