# HYPERSPACE: capability-provenance and portable agent handoff

[Msg⛛{GPT6-HYPERSPACE-CAPABILITY-HANDOFF-20261108}]

## Purpose

An agent seat is useful when it can carry a selected, **real** task across interfaces without losing its owner, repo, risk, source freshness and validation rules. This edition extends the already-merged-into-PR-#20 Hyperspace spatial work graph rather than adding another 3D renderer, another mission database or a new execution authority.

### What works in this slice

- **3D capability orbit:** a fifth domain ring, distinguishable from Studio missions, projects, rigs and services. Select `CAPABILITY ATLAS` from the 3D domain filter. Capability nodes are **violet** even when the imported catalogue says `state=live`, because a static snapshot cannot establish current live connection or runtime authorization. The inspector exposes source, recorded machine, grade, cost class, purpose and evidence; there is deliberately no executable button for an unqualified plugin.
- **Local Atlas compatibility adapter:** schema `kilocore.capability-atlas.v1` interoperates with Muse's separate Atlas PR #19 (when incorporated) or an explicit provider export at `user://capability_atlas.json`. Load from user path first, otherwise `res://data/capability_atlas.json`. If neither is supplied, the UI says **NOT CONNECTED**, not 75 fictitiously alive capabilities. Reload is a deliberate button. No arbitrary path, executable command, OAuth token or plugin network request is accepted. The parser validates schema, size <=131072 bytes, <=128 rows, unique IDs, grades, machine IDs, kinds and cost/state classes. Visual rendering caps at 24 Atlas records and tells the user how many are omitted.
- **Portable agent handoff:** any source-selected rig/project/mission/service/capability can be exported as a bounded `gsv.hyperspace-agent-handoff.v1` JSON capsule. Press `EXPORT AGENT HANDOFF`. The operator explicitly copies it to the clipboard and writes `user://hyperspace-agent-handoff.json`. This is intended for real agents including GPT-6/ChatGPT, Claude, Codex, ChatDev, Goose, Pi, connected tools and MCP specialists to consume through the local agent's file/clipboard/connector interface.
- **What it contains:** owner-backed ID, title, risk/status, branch, source kind, observed flag, next owner route, precise responsible step, fleet summary and *candidate* integrations. It never includes the raw mission objective, log, secrets, terminal output or arbitrary commands. Permission, actor identity, agent attachment, R2 bypass and run status are all explicitly **false**. A receiving agent MUST inspect current owner observations, qualify any provider with Kilo_Core/gsv-steward and use Studio's real R0/R1/R2 approval and receipt chain before acting.
- **Two-way local contract:** `WorkbenchAgentCapsule.validate` can reject malformed/wrong-schema capsules, false permission grants, invalid project/branch or fake mission ID. External tool authors may write their own parser to the same schema, but **cannot treat the capsule as an authentication token**.

### Workflow

1. Launch the normal `res://scenes/ColonyWorkstation.tscn` and open the existing HYPERSPACE tab. The original Studio source-backed Godot mission flow remains intact and still works.
2. Ask your steward/agent for an approved export of its existing `kilocore.capability-atlas.v1` inventory to Godot's user data directory, file name `capability_atlas.json`; alternatively accept Muse's PR #19 source as `res://data/capability_atlas.json` when integrated. Do **not** copy private provider credentials.
3. Press `LOAD ATLAS`. Choose the outer violet orbit or domain filter. Select an actual capability card. The UI shows its declared grade, hardware, cost and source evidence; the buttons to execute and compose a source mission remain disabled for this static snapshot.
4. Press `EXPORT AGENT HANDOFF`. A real coding or planning agent reads the JSON from clipboard or local `user://` path, checks schema and identifies the owner route and missing admission. Use the owner system to decide what to do next.
5. For actual code work, use the Hyperspace project/mission nodes, Studio's exact project re-scan, acceptance criteria, R2 human approval when needed, source-backed logs and validators. No extra authorization was created by importing an Atlas or handoff.

### Verified Studio re-observation, beyond the capsule

The owner-backed read-only extension is documented in [HYPERSPACE_LIVE_OWNER_LOOP.md](HYPERSPACE_LIVE_OWNER_LOOP.md). A native Godot scene exported a real Studio-observed mission and the independent Python command `agent_handoff.py --observe-studio` successfully GET-read the exact owning mission record and returned receipt/acceptance/validator status without posting or claiming an authenticated terminal. This is a completed real-source read path, not a production R2 build.

### Real owner integration roadmap

Kilo_Core: capability admission and risk policy. KiloCore-Studio: mission owner. gsv-steward: Atlas search/probe/route with verified tool results. Dev-Mentor/Terminal Depths: typed game and agent sessions. GSV dev: build/check/review receipts. FleetBridge: machine eligibility and topology, not current uptime. ChatGPT and custom plugins: execute through their connected providers and consent rules, not through Godot-stored cloud secrets. This edition provides **a validated interchange and meaningful navigation**, not an already-functional connector to every named service.

### Tests / limitations

`tests/workstation_atlas_capsule_test.gd` verifies 30 entries -> 24 visible + 6 reported omitted, strict schema, no false live-green, 3D selection and filtering, that static capability cards cannot invoke or post work, valid exported handoffs, and rejection of forged grants and invalid IDs. It is added to the repository-owned `.gsv/build.yaml` exact-head check. Existing 3D Godot and Studio workflow gates must remain green.

**Cross-language interoperability proved on MSI:** `tests/workstation_agent_export_test.gd` invoked the actual native Hyperspace scene and exported its selected, explicitly marked fixture project to `user://hyperspace-agent-handoff.json` (`WORKSTATION_AGENT_EXPORT_PASS`, exit 0). Then the independent Python CLI `tools/workstation/agent_handoff.py --json <Godot-exported-file>` accepted the SAME file and emitted exact project `C:/dev/active/Furyline`, branch `main`, owner `KiloCore-Studio`, next action `compose_studio_r0_after_fresh_recheck`, and explicit `execution_admitted=false` / `permission_granted=false` / `session_attached=false`; exit 0. The project was a TEST FIXTURE, not live project discovery or a production Studio mission. `tools/workstation/tests/test_agent_handoff.py` adds eight negative-control/contract tests.

Headless source and scene tests **do not establish** a manually reviewed GPU screenshot, an actual production mission completion, an authenticated PTY, a real connected ChatGPT plugin invocation, auto-deployment or advertised productivity multiplier. Those remain separate acceptance requirements.
