# Living Colony Workstation: readable 3D + opt-in local tool atlas

[Msg⛛{GPT6-LIVING-COLONY-20261108}] [State⛛{SOURCE-BOUND|DRAFT|READ-ONLY-ATLAS}]

This is an additive slice on the existing GPT-6 workstation, not a rewrite of another bakeoff entrant and not a simulated fleet controller. Run `res://scenes/ColonyWorkstation.tscn`, select **HYPERSPACE**. The Studio-backed factory/mission flow, user approval and receipt gates remain unchanged.

## See the work, not a field of decorative balls

- **RIG / COMPUTE**: hardware chassis on the fleet deck, one per catalogue rig. A source-unknown body is grey; there is never an assumed live MSI, I3, L9, or Xanadu.
- **PROJECT / CODE**: hexagonal source vault on the upper deck. Its branch/path comes only from a qualified Studio projects scan.
- **MISSION / WORK**: faceted task crystal. A source-observed **RUNNING** mission pulses. If and only if it shares a verified repository identity with a visible project, a blue packet traverses the verified edge. A queued or awaiting-approval mission does not pulse.
- **SERVICE / INFRA**: antenna tower, reporting its source health, without implying the service is an agent.
- **LOCAL TOOL**: octagonal cartridge on the lower integration ring. Amber `source_present` means a local Git checkout was observed, NOT operational service availability, tool qualification, an authenticated connector or an executable agent.

Each object is deliberately **a different shape**; colors independently represent reported state. The always-on collection is a bounded source projection. Long labels appear only for fleet bodies and the selected node to keep 1280×720 legible; the text finder displays every visible object with its actual status.

**Navigation**: click a mesh or select any item in the **OBJECT FINDER**. Search, PREV, NEXT and FOCUS operate without an implicit Xanadu lock. Reset camera goes back to the overview. Domain/time filters hide unrelated lines and work packets. The inspector includes source, identity, verified relationships and state-specific nudges, never synthetic private model thoughts.

**Performance**: the Godot SubViewport redraws on actual camera/selection/data changes, not continuously at an unrestricted frame rate. A visible source-observed running mission enables a ~11 FPS animation update; idle, unavailable or filtered activity suspends the animation process. This is a qualitative resource reduction, **not** a benchmarked CPU/token claim.

## Optional source synchronization: Tool Atlas v1

Studio remains the owner of missions, project scans and service health. In addition, an *operator-triggered* stdlib Python collector can export a tiny local filesystem presence snapshot. It checks only the specified authorized root and explicitly supplied extra paths. It does not read private Obsidian notes, touch repositories, call provider APIs, enumerate secrets, invoke executors, authenticate GitNexus, or assert live connector state.

### MSI / Windows

From an isolated checkout of this branch, in PowerShell:

```powershell
$Root = 'C:\dev\active'
$Atlas = 'C:\dev\.colony\state\workstation\tool-atlas.json'
py -3 tools/workstation/collect_tool_atlas.py --root $Root --out $Atlas
$env:GSV_WORKSTATION_TOOL_ATLAS = $Atlas
& 'C:\dev\tools\godot\4.7.2\Godot_v4.7.2-stable_win64.exe' --path . --windowed res://scenes/ColonyWorkstation.tscn
```

Optional explicit paths for other apps (only when actually known):

```powershell
py -3 tools/workstation/collect_tool_atlas.py --root $Root --out $Atlas --extra "gitnexus=C:\actual\gitnexus\directory" --extra "obsidian=C:\actual\vault"
```

On another OS, specify an existing `--root /absolute/path/to/workspace`, `--out /absolute/path/tool-atlas.json`, and export `GSV_WORKSTATION_TOOL_ATLAS` before starting Godot.

### JSON contract

```json
{
  "schema": "gsv.workstation.tool-atlas.v1",
  "observed_at_unix": 1762590000,
  "tools": [
    {"id": "omnisynapse", "name": "OMNISYNAPSE", "state": "source_present", "path": "C:/dev/active/OMNISYNAPSE"}
  ]
}
```

Allowed states: `source_present` = local Git checkout, `directory_seen` = local directory with no visible Git marker, `not_found` = absent *at the configured path*. No state means an admitted executor. Malformed, duplicate, oversized (64 KiB), out-of-schema, future or >300s old observations fail closed. Invalid and stale files contribute **zero** current tool nodes. The file is local, opt-in and read-only from Godot. A fresh export is required to refresh presence; the cockpit never silently spawns a collector.

### What connects today vs what needs an owning source

| Source | Today | Correct next adapter |
|---|---|---|
| KiloCore Studio | Bounded loopback project/mission/bodies/health observations, real mission POST behind deliberate human submit | independently verified live mission, acceptance and artifact receipt |
| OMNISYNAPSE | Local checkout presence (when collector can see it) | owner-approved graph/cross-reference export; node IDs and provenance |
| GitNexus | Explicit-path presence only | approved index version, repo-anchored symbol/edge query; no fake graph |
| Obsidian second brain | Explicit vault-path presence only; **no notes read** | opt-in, scope-limited note references with per-item consent |
| GSV Sublime Optimization | Local steward/repo presence | exact-head check and receipt read-only adapter; source SHA mandatory |
| PU queue, plugins, skills, processes, agents and connectors | Studio's existing admitted observations where available; otherwise UNKNOWN | each owning service's authenticated read-only status and typed capability proofs |
| Games, playtests and tooling | Studio projects and missions only | owned runtime/gameplay receipts, screenshots, validators and environment stamps |

A future adapter must publish a versioned schema with source, timestamp/lease, stable ID, permission envelope, observed-vs-inferred state, error/stale representation, and strict limits. Cross-references must be source-verified and must never authorize execution or approval. Suggestion/edit actions should create a *draft* for the Studio policy and review path, not change canonical colony state directly.

## Tests and safety

The existing native Godot 4.7 import, UI, spatial, mission, and evidence gates stay in place. This slice adds `workstation_tool_atlas_test.gd`, `workstation_hyperspace_ui_test.gd` selection/visibility controls, and Python `test_collect_tool_atlas.py`. The GSV manifest includes both new contract gates.

**Unverified at this stage:** production Studio mission completion, credentialed GitNexus/Obsidian/OMNISYNAPSE adapters, GPU screenshot/readability at actual 1280×720, measured idle CPU and RAM. The tool atlas is a source discovery bridge, not a substitute for those proofs.

**Comparison and stewardship:** from the other bakeoff cockpits, preserve Muse's semantic slices and honest-state hologram, HOLOMIND's observation-focused depth, CHORUS's transparent fleet feedback, and Cognitive Loom's causal timelines without claiming their features have already been merged into this entry. This branch stays independent for comparison and review.
