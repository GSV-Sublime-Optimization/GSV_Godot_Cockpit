# Software Factory Seat: source-backed Godot → KiloCore Studio

[Msg⛛{GSV-COCKPIT-GPT6-FACTORY-SEAT-20261108}]

## Mission

The cockpit must help a real developer or agent complete the software lifecycle, not just browse decoration. This branch introduces the **first real outbound handoff** from Godot to the existing Studio MissionApi, and the **inbound proof viewer** that lets an operator inspect result evidence.

This is a *client* of Studio. It is not a new runner, alternate mission database, fleet controller, permission service, credential store, terminal broker, or merger.

## Seat flow

1. Open `res://scenes/ColonyWorkstation.tscn` in Godot 4.7.1 or compatible project-pinned 4.7.
2. Click **BUILD SOFTWARE** or **Software factory / build** in the library (also command palette Ctrl+K).
3. Click **SCAN PROJECTS** if necessary. The desk sends one bounded GET to `http://127.0.0.1:7340/api/projects`. Only `kilocore-studio.projects-scan.v2` with `state=OBSERVED` and Git repositories carrying branch + path can be selected. No first-project default. No posting after the 45-second source lease expires.
4. **Explicitly select the target repository**, enter a real title, objective and at least one testable acceptance criterion; choose R0 read-only, R1 docs-only, or R2 code/config edits.
5. Click **SUBMIT TO STUDIO**. Only then does Godot POST `/api/missions` to localhost. Body uses the observed `repo` and `base_branch`, objective, acceptance[], risk and `posted_by=godot-workstation`. Unknown/stale selection, malformed requirements and transport error block submission. R3 remains proposal-only in Studio and is not posted from this desk.
6. Only an actual **201 response** with a valid `msn_` ID, lifecycle state, matching repo and risk is presented as **ACKNOWLEDGED**. Anything else becomes **NOT ACKNOWLEDGED**. The desk now enforces a one-shot submission latch: a valid 201 **disables another POST of the same draft**, and the operator must choose **START A NEW MISSION DRAFT** to clear the fields and select a new observed repo. Ambiguous HTTP failures, timeouts, oversized or malformed replies **quarantine the draft without deleting it**. The Submit button cannot POST again until the operator checks the canonical mission index in Studio, then consciously chooses **CHECK STUDIO, THEN AUTHORIZE RETRY (DUPLICATE RISK)**. This does not claim server-side idempotency: Studio may already have persisted the mission, and manual cross-check remains essential.
7. Studio independently validates the repository and controls R0/R1 admission, R2 human approval, worktree isolation, runner/tool permissions, budget, validator and receipts. **Use Open Studio** to review an R2 approval. The cockpit does not approve, start agents, trigger a merge, or deploy.
8. Click **Observed missions**, choose the mission. Its read-only tab can **READ LOG TAIL** from Studio and **INSPECT RECEIPT / TESTS** using a bounded GET `/api/missions/{id}`. Only identity-matching, allowlisted fields are displayed: lifecycle/risk, review/merge eligibility, receipt ID, validator result, acceptance count, commit IDs, changed paths. No raw tool transcript, objective, secrets, prompts or chain-of-thought is reproduced.
9. A passing validator *does not* by itself prove interactive Godot visuals or independent review. Merge and publication remain Studio/owning-repository decisions.

## Control/authority diagram

```text
GODOT Workstation  →  observed Project Constellation via Studio GET
    ↓ explicit human project selection, goal, R2 risk, acceptance
GODOT Mission Desk →  Studio MissionApi POST /api/missions (201 or not-acknowledged)
    ↓ Studio MissionStore / runner / policy / human approval
    ↓ dedicated worktree → toolchain → validator → receipt
GODOT mission tab ←  Studio GET mission log + result/receipt identifiers
    ↓ human review in owning systems
GSV exact-head check → independent review → manual promotion
```

The *agent list* on the left is catalogue metadata, **not** proof that 11 different runtimes are available. The only currently documented admitted Studio executor is `claude-code`; choosing an agent seat does not invent an attachable PTY or tool invocation. Other executors must first be installed, callable, qualified and admitted through their owners.

## Constraints and negative controls

- Local loopback only. Env `GSV_STUDIO_ENTITY_PORT` may change the **port**, never hostname. No redirects, no arbitrary URL, no shell/process launch from Godot.
- Independent bounded HTTPRequests for project GET, mission POST and mission evidence GET. Requests time out. No background dispatches.
- No stale, UNKNOWN or static catalogue data can authorize sending a mission. No automatic repo selection. No automatic code approvals.
- Display full outbound text only in the local composer; no user prompt is copied to a shared UI event log. The source evidence reader whitelists data and never displays raw `result`.
- Existing 13-tab legacy cockpit, other agents' bakeoff branches, Studio owner APIs and physical fleet services are untouched.

## Tests

In a **clean isolated worktree** (never a shared active checkout):

```powershell
$Godot = 'C:\dev\tools\godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe'
& $Godot --headless --audio-driver Dummy --path . --editor --quit
& $Godot --headless --audio-driver Dummy --path . --script res://tests/workstation_mission_test.gd
& $Godot --headless --audio-driver Dummy --path . --script res://tests/workstation_evidence_test.gd
& $Godot --headless --audio-driver Dummy --path . --script res://tests/workstation_ui_test.gd
$env:GODOT_EXE=$Godot
py -3 tests/studio_mission_transport_smoke.py
```

The Python stdlib smoke binds an **ephemeral 127.0.0.1-only fake Studio** and verifies a real Godot HTTP POST body/201 acknowledgement. It **does not touch production Studio or create a live mission**. The GDScript negative controls cover forbidden R3, unknown/stale project selection, duplicate sources, cross-mission evidence spoofing, unverified receipts and failed validators.

### Not yet proven

A native onscreen visual/layout/accessibility pass; Studio's *real* project discovery and R2 mission submission from the Godot UI under an operator's explicit choice; real agent execution and a produced artifact using this particular UI; independent code review, and a default-branch merge. Until those are demonstrated, classify this slice as **functional local transport proven; live build acceptance open**. It is not complete end-to-end AI software autonomy.
