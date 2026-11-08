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

## How to verify

A source-only test uses fake *data*, not a fake service, to exercise negative
controls. The separately opt-in real test requires Studio to be running
locally. Use the repository's Godot 4.7 engine and standard project import.

```powershell
# Source/parse and fail-closed contract checks
& godot --headless --path . --import
& godot --headless --path . --script res://tests/studio_entity_bridge_test.gd

# Actual same-host Studio HTTP handshake, not a fabricated response
$env:GSV_STUDIO_LIVE = "1"
& godot --headless --path . --script res://tests/studio_entity_bridge_test.gd
Remove-Item Env:GSV_STUDIO_LIVE
```

The live test counts as an **R0 sensor canary**, not ML intelligence, mission
execution, agent identity, or productive fleet work. Run it from an isolated
clone so imports and user data cannot affect occupied agent worktrees.

## Next slices, each independently gated

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
