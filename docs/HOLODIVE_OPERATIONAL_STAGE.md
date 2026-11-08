# HOLO DIVE / Operational Holographic Theatre

[Msg⛛{GPT6-HOLODIVE-20261108}] Source-only evolution of GPT-6 Workstation PR #20

## What changed

The cockpit now BOOTS INTO THE NATIVE 3D THEATRE, not the conventional Fleet table. Existing Fleet, Studio Factory, sessions, service list, games and library are preserved. Conventional operational docks return when an operator leaves HYPERSPACE. Ctrl+K still opens workspace tools. Neither Godot nor this geometry becomes the source of policy.

The world uses native Godot 4.7 Camera3D/SubViewport and emissive 3D geometry: spatial witness pillars, altitude-separated domain rings, an observation anchor, labelled source objects, selection halos and focus beams. Four rig pedestals, hexagonal project spires, mission crystals and service obelisks have distinct silhouettes. Game spires have an extra gold ring ONLY when the owning Studio Project Constellation returned a Git repo matching a catalogue game; static lore does not make a living node.

The domain stage is geometry, NOT a simulated AI brain. Rotating rings and cinematic orbit are presentation only. State colours originate in the owning Studio source projection. The centre says ZERO LOCAL EXECUTION RIGHTS.

## Operate

- Start at res://scenes/ColonyWorkstation.tscn. Immersive HOLO DIVE is first paint.
- DRAG over the viewport to orbit. WHEEL changes distance. CLICK selects. F / DIVE moves focus near the selected object. TAB cycles visible sources. Keyboard 1–6 selects all, rigs, projects, missions, services and observed games.
- 4D / SOURCE-TIME SHEAR enables a 1–168-hour time-slice slider for missions with authentic Studio updated_at timestamps. Undated missions are excluded. This is NOT a reconstructed historical snapshot.
- R / RE-OBSERVE requests bounded read-only Studio health, bodies, projects and missions. It does not run builds, restart services or attach agents.
- OPEN SOURCE / EVIDENCE navigates to verified Studio mission log/results, observed project, rig or services. Receipts and log reads retain their source and permission checks.
- PREPARE STUDIO DIAGNOSIS transports source-observed project/mission context into an R0 draft. Studio must rescan the project and an operator must submit. R2 editing remains independently approval gated.
- RECALL ORBIT restores the wide theatre. CINEMATIC ORBIT is optional camera motion, not evidence of active agents. Source labels are level-of-detail filtered; full names and numbers are in the inspector.

## Ownership, actual wiring, and gaps

FleetBridge owns local physical observations. Studio owns project scans, missions, approvals, worktrees and receipts. Kilo_Core owns execution admission, identity and policy. Holo Dive creates NO SSH commands, PTYs, SDK tokens, OS subprocesses, self-approval, merges, deployments or arbitrary HTTP endpoints.

Reported_fresh is an UNATTESTED OS report, never execution admission. Resource readings in the selected rig inspector appear only when Studio actually supplies them. Only exact, source-verified project-to-mission repository identities create a 3D beam. Filtering either source hides the beam.

Read-only MSI verification on 2026-11-08: the INSTALLED Studio health endpoint answered HTTP 200 and its missions index returned eight records. Its /api/entity/bodies endpoint was unavailable despite source PR #56 having merged. No production restart/redeployment was performed. The 3D body feed must remain UNKNOWN until the owning Studio deployment validates that endpoint.

No qualified PTY, live autonomous plugin wiring, production game launcher, gameplay renderer, full R2 change-to-artifact canary, or screenshot/VRAM quality gate is claimed. These require owner adapters and distinct evidence.

## Test contract

In a clean isolated worktree with Godot 4.7.2 and Dummy audio, run tests/workstation_spatial_test.gd, tests/workstation_hyperspace_ui_test.gd, and tests/workstation_holodive_contract_test.gd with Godot --headless --audio-driver Dummy --script. Repository-owned .gsv/build.yaml includes the new exact-source Holo Dive contract plus the mission, evidence, import, parse and UI gates.

Optional GPU-only fixture: tests/workstation_holodive_capture_fixture.gd. Its output receipts/holodive-visual-fixture.png is watermarked SYNTHETIC VISUAL FIXTURE and must NEVER be interpreted as real fleet telemetry. Do not ship fixture receipts as operational status.

## Before release

1. Independent actor review and 720p/1440p physical click/accessibility QA.
2. Measured FPS, GPU/VRAM and CPU under a genuine source load; downshift graphics before any i3 deployment.
3. Qualified Studio deployment of the four-body endpoint with strict UNKNOWN/stale semantics.
4. A complete authorized developer loop: observed repo, submitted mission, admitted executor and isolated worktree, tests and receipts, playable artifact, and guarded PR promotion.
