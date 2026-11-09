## Slice 2 — Gateway health sensor (colony routing layer)

Stacked on Slice 1 (base `muse/mind-slice1-constellation-20261107`).
Wires the Mind to the routing layer with a second read-only sense.
**No authority change, no actuators (0 stays), no POST, no secrets,
no arbitrary URLs, no remote peers.**

### What it senses

- `GatewayHealthProjection` — schema-pinned parser for gateway `/health`
  (`{"status":"ok"}`). Admits only the `status` string (bounded, 64 chars).
  `ok` is `live`; any other non-empty status is an honest `unavailable`
  with the fixed reason `gateway_not_ok`. Malformed JSON, missing or
  non-string status, and oversized bodies (4,096-char cap) are rejected
  closed.
- `GatewayObservationBridge` — async GET only to hardcoded
  `http://127.0.0.1:8001/health`; 4s timeout; 8KB body cap; one request in
  flight; `max_redirects = 0`; 15s freshness; the same
  unknown/unavailable/live/stale state machine as the Studio sensors.
- `EntitySession` observes the gateway on the same 15s tick as Studio
  health (both are fast senses), records `gateway_health_observation`
  events in the bounded history, and gains a `gateway` key plus a
  `gateway.health.read` capability (`mutation: false`).

The gateway `/mcp` surface is **not** sensed here — it is a POST-based
JSON-RPC API, and this slice reads health only. Verified live 2026-11-07:
`/health` 200 (`{"status":"ok"}`), `/mcp` 200 (discovery doc, version
0.2.0), `/agents` 404 (public mode).

### Verification (queued)

- `tests/gateway_health_test.gd` follows the #8 pattern: negative controls
  (malformed JSON, missing/non-string status, `gateway_not_ok`, oversized
  body, one-in-flight guard) + an opt-in live canary
  (`GSV_GATEWAY_LIVE=1`, accepts live OR honest unavailable, never
  fabricated live). **gdparse passes on the VM.**
- Godot verification on the MSI is **queued behind Furyline Phase B**
  (single-flight + 2,500 MB RAM gate; Phase B signals completion via
  `~/workspace/colony-loop/furyline-verdict2/PHASE-B-DONE.md`). Run when
  the gate clears: `--headless --import`, then the test script, then the
  existing #8 + Slice 1 tests for regression.

### Files

- `scripts/entity/GatewayHealthProjection.gd` (new)
- `scripts/entity/GatewayObservationBridge.gd` (new)
- `scripts/entity/EntitySession.gd` (gateway sensor on the 15s tick)
- `tests/gateway_health_test.gd` (new)

Draft — no merge. Stacks: #8 → #9 (Slice 1) → this → Slice 3 (config +
visible presence + doc).
