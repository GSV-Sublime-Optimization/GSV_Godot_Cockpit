## Slice 1 — Constellation sensor (Studio `GET /api/projects`)

Stacked on #8 (base `agent/chatgpt-gpt6/studio-embodied-readonly-20261107`).
Adds a second read-only sense: the project constellation, in the same bridge
pattern as the Slice 0 health sensor. **No authority change, no actuators
(0 stays), no POST, no secrets, no arbitrary URLs, no remote peers.**

### Why cached, not polled

The Studio `/api/projects` scan is slow: its backend runs
`project_constellation.py` and times out after 15s, so the endpoint answers
in ~15s with a graceful `UNKNOWN` envelope
(`kilocore-studio.projects-scan.v2`, `count: null`, `projects: null`) when
the scan does not finish — verified live 2026-11-07 (15,097 ms, HTTP 200).
A 4s timeout would fail every time, and polling on the 15s sensory tick
would stack slow requests. So this sensor is **bounded and cached**:

- `StudioConstellationBridge` — async GET only to hardcoded
  `http://127.0.0.1:7340/api/projects`; **20s timeout**; 256KB body cap;
  one request in flight; `max_redirects = 0`; **120s minimum refresh**
  (`observe()` is a no-op inside the window unless forced); 300s freshness.
  The observation carries `age_ms` so the consumer always knows how old
  the cached constellation is.
- `StudioProjectsProjection` — schema-pinned parser for
  `kilocore-studio.projects-scan.v2`. Admits only schema, scan state/source,
  `generated_at`, a bounded project count (0..1,000,000), and at most **50**
  project name/status pairs (malformed entries are skipped and counted,
  never fatal; 262,144-char body cap in the parser). A well-formed envelope
  whose scan produced no constellation (null count / null projects) is an
  honest `unavailable` with the fixed reason
  `constellation_scan_unavailable` — never a fabricated `live`. No project
  bodies, paths, prompts, secrets, or tokens cross.
- `EntitySession` observes the constellation on its own slow cadence (180s
  by default, separate from the 15s health tick), records
  `constellation_observation` events in the same bounded 64-event history,
  and gains a `constellation` key plus a `studio.projects.read` capability
  (`mutation: false`) in the self-model.

### Verification (queued)

- `tests/studio_constellation_test.gd` follows the #8 pattern: negative
  controls (malformed JSON, unknown schema, null count/projects,
  oversized body, malformed project entries, 50-project cap, one-in-flight
  guard, minimum-refresh guard) + an opt-in live canary
  (`GSV_STUDIO_LIVE=1`, accepts live OR honest unavailable, never
  fabricated live). **gdparse passes on the VM.**
- Godot verification on the MSI is **queued behind Furyline Phase B**
  (single-flight + 2,500 MB RAM gate; Phase B signals completion via
  `~/workspace/colony-loop/furyline-verdict2/PHASE-B-DONE.md`). Run when
  the gate clears: `--headless --import`, then the test script, then the
  existing #8 tests for regression.

### Files

- `scripts/entity/StudioProjectsProjection.gd` (new)
- `scripts/entity/StudioConstellationBridge.gd` (new)
- `scripts/entity/EntitySession.gd` (constellation sensor on the 180s cadence)
- `tests/studio_constellation_test.gd` (new)

Draft — no merge. Stacks: #8 → this → Slice 2 (gateway health) → Slice 3
(config + visible presence + doc).
