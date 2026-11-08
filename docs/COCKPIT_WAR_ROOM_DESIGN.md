# Cockpit UI — war-room design, holographic form (Muse's bake-off entry)

**Date:** 2026-11-07 ~23:50 MST. **Status:** Slice 4 — first shippable entry.
**Supersedes in form, keeps in spirit:** `~/workspace/colony-loop/cockpit-design-20261107.md`
(the 2D war-room design) and `~/workspace/colony-loop/cockpit-war-room-direction-20261107.md`
(Keath's pick). **New form:** Keath's holographic brief, 2026-11-07 ~23:46 MST.
**Sources:** repo survey `~/workspace/cockpit-ui-survey-20261107.md` (Lane A) · live survey
2026-11-07 23:21–23:35 MST (Lane B) · bake-off hub issue #13.

## 0. The pivot: spirit and form

Keath's pick was the GROKBOT + JEV war room — embodied agents at desks in a shared
room, visibly doing their jobs, status cards on top, the spider showing its work.
Keath's holographic brief is the FORM that pick now takes: the cockpit is **not a 2D
UI with a rendering trick**. It is a 3D volume you look down into, and the interface
is the coordinate transformation between that volume and the screen.

- **War-room direction = the SPIRIT** (embodied agents, visible work, status cards).
- **Hologram = the FORM** (agents as companion bodies / layers in the volume, status
  cards as pull-up layers, the crawler's work as a sliceable layer).
- The room is the volume. The table the hologram floats above is the war-room floor.
  The companion body at its centre is the Mind, embodied. The desks ringing the table
  are the verified seats. The central monitor's web is the constellation.

## 1. What the surveys proved (and corrected)

| Assumption | Verified truth |
|---|---|
| Dev-Mentor :7337 lives on the i3 | **Live on the MSI itself** (`127.0.0.1:7337/`, 200 in 69 ms). The i3 side is unverified — `:7337` TCP connect fails from MSI and SSH hangs from session-0. |
| Spine snapshot (`/api/spine`) is the room's service map | **UNAVAILABLE.** Times out at 12 s on MSI localhost and 15 s to the i3. Any spine-derived data shows UNKNOWN, never fabricated. |
| Studio `/api/projects` is a slow-but-working feed | **Live endpoint, data UNAVAILABLE.** 200 in 15,036 ms, `state: UNKNOWN`, `count: null` — the server-side scan timed out after 15.0 s. The constellation layer shows `constellation_scan_unavailable`. |
| OpenClaw :18789 answers HTTP | **Process live, plain HTTP GET / times out at 8 s.** WebSocket/MCP gateway. A panel must never use `GET /` for this seat; liveness comes from the Studio feed + process presence. |
| Dev-Mentor `/api/health` is a fast 4 s sense | **Live but SLOW — 7,331 ms.** `{"ok":true,"uptime_s":23314,"game_engine":true,"active_game_sessions":290}`. A 4 s bridge timeout would false-negative it. Per-source timeout budgets are mandatory. |
| Skyclaw is a running service | **Scanner RUNNING but DEGRADED.** No `skyclaw` process; the scan loop runs via Dev-Mentor state but every cycle logs `process_sync failed: database is locked` and raises `endpoint_down` for ollama and terminal-depths — those probes use `host.docker.internal` hostnames while MSI-local Ollama IS serving and MSI-local :7337 IS up. Honest state: scanner running, degraded (DB locked). |
| Soul Claw / MetaClaw are colony seats | **NOT DETECTED.** Neither gets a creature — empty desks with "awaiting" signs. |
| Terminals are reachable | **No terminal broker exists.** MSI shell via mssh/scheduled-task lanes only; i3 and Xanadu SSH hang from session-0; L9 unreachable. All four terminal layers are honestly PLANNED. |

### 1.1 Live sources the room draws on (probed 2026-11-07 23:21–23:35 MST)

- **Studio `127.0.0.1:7340/api/health`** — 200 in 327 ms, schema
  `kilocore-studio.cockpit-health.v2`. Cards show only what the current projections
  admit (counts + thermal gate). Service-level cards need a projection extension —
  a named follow-up, not smuggled in.
- **Gateway `127.0.0.1:8001/health`** — 200 in 68 ms, `{"status":"ok"}`.
- **Gateway `127.0.0.1:8001/mcp`** — 200, `KiloCore Colony Gateway` v0.2.0, `tools: []`.
- **Dev-Mentor `127.0.0.1:7337/`** — 200 in 69 ms; **`/api/health`** — 200 in 7,331 ms.
- **NuSyQ-Hub `127.0.0.1:8000/`** — 200, operational. **Router `127.0.0.1:9001/`** — 200.
  **Dispatch `127.0.0.1:9002/`** — root 404, process live. **ChatDev `127.0.0.1:7338/`** —
  200, up 23,709 s, `ai_ok` + `redis_ok` true.

### 1.2 Verified seats (evidence standard: process, endpoint, repo, or doc)

| Seat | State | In the room |
|---|---|---|
| OpenClaw | REAL + LIVE (node PID 18788, :18789, Studio OBSERVED) | Working creature. See the §1.3 discrepancy note. |
| ChatDev | REAL + LIVE (:7338 200, `ai_ok` + `redis_ok`) | Working creature. |
| Claude | LIVE process — rate-limited, CLI OAuth expired | Creature at desk, dimmed. |
| Codex | LIVE (app-server daemon 0.167.0 + cloud exec-server) | Working creature. |
| Jev / OpenJev | LIVE (python PIDs 19884, 19960) | Working creature — the judge. |
| Serena | LIVE (`serena.exe` PID 4180 + wrappers) | Working creature. |
| Ollama | LIVE (`ollama serve` + app) | Working creature — the model shelf. |
| Dev-Mentor MCP server | LIVE (python PIDs 29392, 34392 + launcher) | Working creature. |
| Skyclaw | REAL, scanner RUNNING but DEGRADED (DB locked; false "down" verdicts) | Creature at a flickering desk (the spider). |
| Hermes | REAL as code/harness, NOT RUNNING | Empty chair — "harness installed, not running". |
| Gordon | NOT DETECTED running (docs + PR references only) | Empty chair — "docs only". |
| Aider / Goose | NOT DETECTED running (re-qualified 2026-10-28) | Empty chairs — "qualified, not running". |
| Copilot | NOT DETECTED running (quota exhausted 2026-10-22) | Empty chair — "quota exhausted". |
| Soul Claw / MetaClaw | NOT DETECTED | Empty desks with "awaiting" signs. No creature, no card. |

### 1.3 Known discrepancy: OpenClaw vs hub #13

Bake-off hub issue #13 still lists OpenClaw as UNVERIFIED ("no entry may list it as
real until proven"). Lane B's fresher probe found its process live (node PID 18788,
gateway :18789, started 17:58) and Studio's `colony_observation` feed lists it
OBSERVED. This entry follows the fresher Lane B evidence (source cited on the seat)
and flags the discrepancy here and in the PR body for the bake-off coordinator to
reconcile in #13. Soul Claw and MetaClaw stay NOT DETECTED under both readings.

## 2. The coordinate stack (Keath's brief — authoritative)

Four spaces; every interaction is a conversion:

- **World space:** the physical 3D scene — the companion's body, the "table" the
  hologram floats above, the origin. Information sits at p_world.
- **View space:** p_view = R⁻¹ · (p_world − t) from the camera's rigid transform.
  The view-space z of each layer is the depth-layering quantity.
- **Clip space:** p_clip = P · p_view with the standard perspective matrix
  (f = 1/tan(fov_y/2), aspect, near n, far f).
- **Screen space:** `Camera3D.unproject_position(world_point)` is the forward
  projection. The inverse is the ray: `project_ray_origin` / `project_ray_normal`.
  Every click, hover, and drag begins as that ray.

Implementation: `scripts/holo/HoloCoordinateStack.gd` — pure static functions, no
scene-tree state, unit-tested without a running scene
(`tests/holo_coordinate_stack_test.gd`). The live scene calls these with its real
Camera3D; the tests call them with a throwaway camera.

## 3. Layers: bringing a layer up, depth ordering, slicing, volumetric, gaze

**A layer is a plane** n̂·p = d (n̂ = camera forward, i.e. negative camera global
basis Z). Ray-plane intersection: t = (d − n̂·ray_origin)/(n̂·ray_dir),
p_hit = ray_origin + t·ray_dir (Godot: `Plane.intersects_ray`, null if
parallel/behind). Then p_local = layer_global_transform.affine_inverse() * p_hit,
tested against the layer's bounding rect — that is how a flat terminal, graph node,
or data card becomes clickable while floating in 3D. Implemented in
`HoloCoordinateStack.hit_layer`; driven by `HoloRoom.pointer_clicked`, which
depth-sorts layers first and toggles the first hit.

**Bringing a layer closer** is a continuous λ ∈ [0,1] interpolating the plane
distance d_i(λ) = d_i_base + λ·Δd and scale s_i(λ) = s_i_base·(1 + λ·κ) together —
you change the plane's d and its scale, not individual objects
(`HoloCoordinateStack.pull_distance` / `pull_scale`; `HoloLayer.update_frame`).

**Depth ordering:** sort layers by view-space z with a separation ε for equal
depths; stable sort on (z_i, render_priority_i, ε_i), closer (less negative z)
first (`HoloCoordinateStack.sort_layers_by_depth`).

**Slicing — the signature interaction.** A half-space clip: keep n̂_s·p − d_s ≥ 0;
in the shader, `if (dot(world_position, slice_normal) - slice_distance < 0.0) discard;`.
Animated `slice_distance` over a 14 s cycle. SEMANTIC: the slice axis is a data axis —
`time` cuts vertically (magnitude), `sense` cuts across the sense index (x), `age`
cuts across the age axis (z). The slice plane is the human's inquiry into a dataset
embedded in the volume. The slice cuts the VOLUME only; layer cards carry the no-cut
default plane, so a sweep never blanks the cards.

**Volumetric information.** A scalar density field ρ(p) rendered by ray marching:
C = Σ ρ(p_i)·T_i·c(p_i)·Δ, T_{i+1} = T_i·exp(−ρ(p_i)·Δ). Texture3D in a bounding-box
mesh, max_steps 64 (compiled bound), step_size 0.02 (uniform). For the companion,
the volumetric layer is the agent's internal state — the human looks down and sees
the shape of the machine's thought as a volume, not a text log.

**HONESTY RULE for ρ:** ρ is driven by the Mind's REAL senses (Studio health,
gateway health, constellation, fleet bodies) or by explicitly-marked simulated data.
Never a fabricated density field presented as live agent state. The field's axes are
data axes (x = sense index, y = magnitude, z = age); each live sense contributes one
Gaussian blob with amplitude = liveness (live 1.0, stale 0.5, unavailable/unknown
0.0). No live senses → an all-zero field labelled NO LIVE DENSITY. Simulated mode is
a local display toggle (default OFF) with a fixed demo pattern labelled SIMULATED in
full (`scripts/holo/HoloDensity.gd`).

**Gaze and parallax.** The companion's gaze ĝ = normalize(p_cam − p_holo).
Billboarding rotates a flat card so its normal aligns with ĝ (minimal rotation;
`Basis.looking_at(..., use_model_front=true)` since QuadMesh faces +Z). Parallax:
offset_i = k·(z_i − z_ref)·(p_cam − p_ref) — the human's head movement becomes a
query. The live room implements parallax as a small camera drift from the mouse
position; the pure formula is tested alongside.

**The unified object:** H(p,t) = {ρ_k(p,t), σ_k(p,t)} per layer k. The interface is:
Screen → Ray → Plane/Volume Intersection → Layer Local Coordinates → Content Query.
Every interaction (hover, click, slice, pull, expand) modifies parameters of H: plane
distance d, slice offset d_s, visibility σ, scale λ. What makes it a companion rather
than a visualization is that ρ is the agent's own state, updated every frame.

## 4. Module catalog + wiring map (Slice 4 ships the bold rows)

| Layer | Source | Honest state (Slice 4) | Cadence / timeout |
|---|---|---|---|
| **Studio health** | Mind Slice 0 (`:7340/api/health`) | LIVE — counts 0, thermal gate open | 15 s tick / 4 s |
| **Gateway health** | Mind Slice 2 (`:8001/health`) | LIVE — `ok` | 15 s tick / 4 s |
| **Constellation** | Mind Slice 1 (`:7340/api/projects`) | UNAVAILABLE (`constellation_scan_unavailable`) | 180 s / 20 s, 120 s min-refresh, age_ms |
| **Fleet bodies** | Mind (Keath 2026-11-07) | LIVE — 4 bodies reported fresh | 15 s tick / 4 s |
| **Dev-Mentor · game** | `:7337/api/health` (MSI) | LIVE but SLOW — 10 s+ async timeout; spine UNKNOWN | 30 s / 12 s async |
| **War-room floor** | Registry + the three senses | LIVE (room renders; creatures per §1.2) | 15 s tick |
| **Status cards** | Registry + senses | LIVE for sensed data; UNKNOWN for spine-derived data | per source |
| **Terminal layers (MSI / i3 / L9 / Xanadu)** | Broker — DOES NOT EXIST | PLANNED — "broker needed", never fake output | n/a |
| **Agent-seat registry** | §1.2 verdicts | LIVE / degraded / away / awaiting per seat | per source |
| **Rig · MSI** | Fleet snapshot (CIM + services + tasks) | LIVE — RAM free, CPU, 9 services, 4 tasks | snapshot 5 min / reader 30 s |
| **Rig · i3** | Fleet snapshot (LAN SSH) | LIVE — RAM free, seats (Claude ×4, Ollama) | snapshot 5 min / reader 30 s |
| **Rig · L9** | Fleet snapshot (LAN SSH) | LIVE — RAM free (CIM) | snapshot 5 min / reader 30 s |
| **Rig · Xanadu** | Fleet snapshot (Icecast HTTP only) | LIVE — Icecast 2.4.4 | snapshot 5 min / reader 30 s |
| **Ledger** | Mind status + layer states + fleet age | LIVE (bounded, escaped via #5) | on observation |
| **Mind View (#12)** | PR #12 fleet map + transcript | INCOMING — desk marked, not built | n/a |

Per-source timeout budgets: fast senses 4 s; slow senses (Dev-Mentor health) 12 s
async; constellation 20 s cached. One request in flight per source, everywhere.
Caps in bridge AND parser. `max_redirects = 0`.

## 5. Terminal-broker contract (future slice, not Slice 4)

A real interactive terminal tab needs a broker that provides, at minimum:

- **PTY allocation** per tab, per machine, with a named session and a bounded
  scrollback; **streaming** of output to the cockpit as append-only text frames;
  **input** from the cockpit as keystrokes, gated by an explicit per-tab
  "input enabled" state; **auth** — the broker authenticates to each machine with
  the colony's existing lanes (mssh, scheduled tasks), and the cockpit never holds
  credentials; **honest transport state** (connecting / live / stalled / closed /
  broker unavailable) with age; **kill policy** — the broker owns its children and
  reaps them on tab close.
- **The broker must never:** execute a command the cockpit did not explicitly send
  through an operator-confirmed channel; run a shell from Godot; expose secrets or
  tokens to the scene tree; fake output (a closed session shows "closed", never a
  replayed transcript presented as live); or bypass the R0–R3 gates. Command
  execution stays with the existing brokered lanes (mssh, scheduled tasks) until a
  later owner-approved slice under R0–R3 defines and proves this contract.
- **Borrowed patterns (Dev-Mentor #215):** per-tab snapshot/restore
  (`{id, label, html, scrollTop, history, histIdx}`); persisted history decoupled
  from view history (cap 500); Ctrl+T new · Ctrl+W close · Ctrl+1–5 switch, "+"
  button, never close the last tab; **Ctrl+B reserved for panel cycling**.

## 6. What is real vs wired vs planned

- **Real (proven 2026-11-07):** the three Mind senses (with constellation data
  unavailable); gateway + Studio + Hub + router + ChatDev endpoints; the
  verified-live seats in §1.2; the existing 13-tab cockpit; Dev-Mentor's
  terminal-tab patterns; Ash's JSONL contract.
- **Wired in Slice 4:** the holographic room + layer registry; the Mind's three
  senses + fleet bodies as layers; the Dev-Mentor game sense; the terminal-layer
  shells (honest PLANNED state); the agent-seat registry (verified seats only);
  the density field from real senses; the semantic slice; the ledger; the
  fleet-telemetry snapshot reader + four rig layers (MSI / i3 / L9 / Xanadu).
- **Wired in Slice 5:** the Capability Atlas shelf (§9) — the static graded
  atlas file + the fleet-snapshot live overlay + the slice/pull layer under
  HoloRoom; the "Atlas" slice button on the HoloTab bar.
- **Planned (not Slice 4):** the terminal broker (§5); the Ash JSONL game-session
  client; service-level cards from an extended Studio projection; the Mind View
  (#12) layer; layout persistence beyond presets; harness adapters (Serena, Hermes,
  OpenClaw behind the broker — per the Mind doc's next-slice map).

## 7. Constraints the build respects

1. **Mount, don't fork.** `EntitySession` is mounted from `scenes/EntitySession.tscn`
   into the room; no copied sensor code. The Mind View (#12) is not duplicated.
2. **Stack tip, not master.** This entry consolidates, on its own branch: #8 at
   `a4c379ce` (Keath's three commits: FleetBodies + console + four-body receipts)
   with #9/#10/#11 cherry-picked onto it (union resolutions in `EntitySession.gd`,
   recorded in the branch history), plus the #4–#6 classic-panel stack merged in.
   #9 was CONFLICTING against the new #8 head; the conflict is resolved here, on
   the entry line only — the #9/#10/#11 branches themselves are untouched.
3. **Reuse #5/#6.** All external text through `escape_event_text` — on BBCode
   surfaces (the ledger). Label3D renders literally, so cards are set raw and the
   escaping rule lives on the ledger (documented in `HoloLayer`). Any new operator
   POST follows #6's truth-gate; UNKNOWN, never zero (#4).
4. **Read-only by default.** Only existing writes are the operator-clicked CHUG
   trigger and Route-via-bridge. No shell from Godot; no secrets in the scene tree.
   The Slice 4 buttons (slice axis, density toggle, pull-all) are local display
   controls only.
5. **Slow sources get the constellation treatment** (cached, min-refresh, `age_ms`).
6. **Tests follow the #8 pattern:** negative controls on fake data + env-gated
   live canary (live OR honest unavailable, never fabricated live); boot test
   extended (13 → 14 tabs); strict smoke gate (zero engine ERROR/SCRIPT ERROR on
   exit 0); new `holo` case in `tests/godot_smoke_gate.py`.
7. **No Godot on the MSI while Furyline Phase B runs** — single-flight + 2,500 MB
   RAM gate; PHASE-B-DONE.md is the signal. Screenshot + FPS are queued behind it.

## 8. Fleet telemetry — the competitive edge (full send, 2026-11-08 ~00:04 MST)

Keath's full-send brief: the entry wires REAL fleet-wide observation data into
the volume — the thing other entries cannot do from a single machine. The volume
is the real fleet, live.

**Pattern (the honest way):** the cockpit runs NO shell and holds NO credentials.
A probe script on the MSI (`tools/fleet_feed/fleet_feed.ps1`, via mssh or the
`MuseFleetFeed` scheduled task, every 5 min) writes ONE typed JSON snapshot
(`C:\GSV\state\fleet-telemetry.json`, schema `kilocore.fleet-telemetry.v1`). The
cockpit reads that file with caps (64 KB) + schema checks + age — the same pattern
as Mind View's `mind_feed.py`. States: unknown / unavailable / live (age < 300 s) /
stale (age ≥ 300 s). A rig with no live source is `unavailable`/`unknown` with a
reason, never faked live.

**Sources wired (verified at build time, 2026-11-08 ~00:09–00:11 MST — two probe
runs; flapping is real and reported honestly):**

| Rig / service | Source | Live state at build |
|---|---|---|
| MSI RAM/CPU | CIM `Win32_OperatingSystem` / `Win32_Processor` | LIVE — free 4,527–5,592 / 32,472 MB (13.9–17.2%), CPU 2–9% |
| MSI services | HTTP GETs (3 s) + TCP :18789 | LIVE — Studio, gateway, Hub, router, dispatch, ChatDev, Ollama, OpenClaw up. **Studio flapped**: up at 07:09Z, `unknown` at 07:11Z (3 s probe timeout). **Dev-Mentor flapped**: `unknown` at 07:09Z (root timed out at 10 s in a separate check), up at 07:11Z. The entry reports each run honestly. |
| MSI scheduled tasks | `Get-ScheduledTask` | LIVE — KiloCore-Public-Gateway Running; Studio-Backend, Mirror-Sync, Heartbeat-MSI Ready |
| i3 | LAN SSH alias `i3` (10.0.0.193, user `studio cuckoo`), tailscale fallback | LIVE — RAM free 14,986 / 24,524 MB; seats: Claude ×4, Ollama. **Lesson:** the first probe failed (`ssh_empty_output`) because the remote command contained a pipe and the remote default shell is cmd — remote commands now contain NO shell metacharacters. Tailscale SSH hangs from session-0; LAN works. GameAttract director: no known endpoint — recorded as not-yet-probed. Dev-Mentor :7337 on i3: TCP unreachable (matches survey). |
| L9 | LAN SSH alias `kilodesktop` (10.0.0.197, user `jacob`) via Git's bundled ssh.exe | LIVE — RAM free 5,993 / 16,329 MB (CIM — L9 is Windows). MSI Windows OpenSSH returns exit 255; Git's ssh.exe works. Off tailnet, LAN only. |
| Xanadu | Icecast `status-json.xsl` on :8000, HTTP ONLY | LIVE — Icecast 2.4.4, started Sun, 08 Nov 2026 02:53:24 +0000. **Never SSH — the pause stands.** |

**What full send does NOT change:** no merges (tap naming the item still required);
no Godot runs while Furyline Phase B runs (single-flight + 2,500 MB RAM gate);
no authority / actuators / secrets / POST / shell-from-Godot (fleet access is
observation data, not command); Xanadu SSH pause still stands; never touch Keath's
live session processes or live editor; never fake data.

## 9. Capability Atlas — Slice 5 (full send, 2026-11-08)

**What it shows.** A "what can do what, where" shelf in the volume: one node
per graded capability (75 entries at build time), each carrying its machine
(MSI / i3 / L9 / Xanadu), its D/I/C/Q/U/M grade, its cost class
(tokenless / cloud / mixed), and its honest live state (live / unavailable /
planned / not_detected / degraded, with age). At rest the layer is its header
card (counts + current slice); pulling it up (λ, the entry's pull-up) expands
the shelf. The HoloTab "Atlas" button cycles the slice; "Pull all" pulls the
atlas with the other layers; clicking the header toggles it. The shelf is a
scene node under HoloRoom (`CapabilityAtlasLayer`), NOT a registry layer — the
registry counts stay 14.

**Slice axes (semantic, per Keath's brief).** Machine (msi / i3 / l9 / xanadu —
one rig's bench); cost class (tokenless / cloud / mixed — the tokenless bench
vs the cloud bench); grade (proven = Q/U/M — only the proven seats;
unverified = D — the explicitly-unverified nodes). Slicing filters
visibility; hidden entries still exist as nodes and return when the slice
changes — the slice is a filter, never a deletion.

**Data contract.** Static graded file `data/capability_atlas.json`, schema
`kilocore.capability-atlas.v1` (entries: id, name, kind, machine, grade,
cost_class, state, evidence, can_do; optional discrepancy + telemetry
mapping), generated from the Slice 5 synthesis
(`CAPABILITY-ATLAS-20261108.md` §1 + §5) — the file is the grade snapshot,
never a live claim. Live-state overlay reuses the §8 fleet-feed pattern: the
reader (`CapabilityAtlasReader`) reads the same
`C:\GSV\state\fleet-telemetry.json` and, only while the snapshot is fresh
(< 300 s), promotes a mapped entry to live (service "up", or its process name
in the rig's seats list) or demotes it to unavailable (service "down");
anything else keeps the static honest state. 13 entries carry a telemetry
mapping. The parser (`CapabilityAtlasProjection`) is schema-pinned: exact
schema string, ≤ 128 entries, bounded strings, rejects malformed /
oversized / wrong-schema / unknown-grade-or-cost with fixed reasons — the
StudioHealthProjection discipline. The reader is two bounded file reads, one
read in flight (60 s poll), no HTTP (no redirect surface), no POST, no shell,
no secrets.

**Routing discipline (one paragraph).** Cheapest capable first, tokenless
local before expensive cloud, always: a local model, a loopback service, a
local CLI, or a stdlib script answers first, and cloud is the last resort,
justified only by a proven capability gap, a measured local failure, sole
access, or Keath explicitly asking. "Cheapest" means the lowest-cost seat
that is qualified (grade Q or better, measured on the task) — a D-grade seat
is not cheap, it is unproven, so a cloud seat at grade U beats a local seat
at grade D; every route names its seat, grade, machine, and cost class, and
a route that cannot name its cost is a guess. The full discipline — shared
vs independent responsibilities, the rules, and how the atlas stays current
(re-grade on change, never on a schedule) — lives in the synthesis §6, and
the atlas's evidence column IS the receipt: never pay twice for the same
answer.

**What is real vs simulated.** Real: the grades + evidence (fresh probes
2026-11-08, synthesis §1); the live-probe overlay (fleet snapshot, ≤ 5 min
old, 13 mapped entries). Static: the grades themselves — a grade is a
snapshot dated 2026-11-08, not a live claim; an entry with no live probe
shows its static state. Unverified stays unverified: oh-my-pi (D, not
installed), wrapper (D, ambiguous — 8 candidates, Keath to disambiguate),
Soul Claw / MetaClaw (not detected — no nodes, no cards), and every
synthesis §5 item appear as explicitly-unverified nodes (dimmed, labelled
UNVERIFIED), never omitted, never dressed as live. The OpenClaw entry
carries its discrepancy flag (both sides: hub #13 UNVERIFIED vs Lane B LIVE;
entry follows Lane B — see §1.3). Nothing in this layer is simulated; there
is no simulated mode for the atlas.

**Slice 5 bar.** 1. The shelf renders 75 entry nodes + header under HoloRoom;
header counts match the file. 2. Pull-up, slice cycling, and header click
work (tests). 3. The overlay promotes/demotes only on fresh probes (tests).
4. `gdparse` + headless tests at exact head (new `atlas` case in the smoke
gate). 5. No Godot verification until Phase B writes PHASE-B-DONE.md — the
same gate as Slice 4.

## 10. Decisions Keath still owes

1. **Terminal broker** — approve the §5 contract as a later R0–R3 slice, or keep
   terminals brokered-only via mssh/scheduled-task lanes.
2. **Which seats are real** — Lane B's verdicts are evidence, not rulings; Soul
   Claw / MetaClaw stay "not detected" until Keath or a seat proves otherwise.
   OpenClaw's hub-#13 discrepancy (§1.3) needs his or the coordinator's ruling.
3. **Layout presets** — which simple/standard/deep presets ship first (2D sense;
   the hologram's equivalents are camera presets — TBD).
4. **Mind View (#12)** — a layer in this room, a separate tab, or its own entry.
5. **Next modules after the first room** — Ash game-session client vs service-level
   cards vs harness adapters.
6. **Bake-off bar** — the sibling bake-off coordinator owns the hub issue, registry,
   rules, and invitations; this entry's first-shippable bar is §11.

## 11. Slice 4 — first-shippable bar (Muse's bake-off entry)

1. The room renders: the volume, the table, the companion, the layer stack (Mind's
   three senses + fleet bodies + game + terminals + Mind View desk + four rig
   layers), the war-room floor with one creature per verified seat (§1.2), the
   central monitor's web, the bottom ledger.
2. Every creature, card, and desk maps to a real source with an honest state
   (live / unavailable / planned / not detected). Nothing fabricated. ρ is real
   senses or explicitly SIMULATED.
3. Clicking a layer pulls it up (ray-plane hit + λ interpolation); the terminal
   layers honestly report transport state (broker needed).
4. Built on the existing `Main.gd` tab structure (new lazy "Hologram" tab, 14th)
   plus a new `HoloRoom` scene; the Mind is mounted, not forked; #4–#6 patterns
   reused; base is the consolidated current tip, expecting rebases.
5. `gdparse` + headless tests at exact head, following the #8 pattern.
6. No Godot verification until Phase B writes PHASE-B-DONE.md. Screenshot + FPS
   queued behind it.

## 12. Agent workstation contribution (i3, 2026-11-08)

A contribution on top of Slice 5 (and #21's fixes) that makes the room
usable by agents and keeps it inside the bake-off idle budget.

**Budget (≤ 5 % of one core idle).** `HoloBudget`: `Engine.max_fps` 30
focused / 10 unfocused, `OS.low_processor_usage_mode`, the HoloTab
SubViewport renders `UPDATE_WHEN_VISIBLE`, and the hologram surface shader no
longer scrolls its scanlines with `TIME`. `HoloRoom._process` runs only while
something moves and stops itself when everything has settled. Keath's rule —
motion = real events only: a pull, a pointer move, a slice-axis change, or an
observation whose honest state *changed* (one 3 s slice sweep + a 2 s pulse
of degraded cards). Re-reads that only refresh ages move nothing. The
continuous 14 s sweep and the always-on Skyclaw flicker are gone.

**Exits.** Esc quits from anywhere (Main.gd and the standalone war room).
`scenes/HoloWarRoom.tscn` is the war room on its own:
`godot --path . res://scenes/HoloWarRoom.tscn -- [--offscreen] [--shot=PATH] [--quit-after=SECONDS]`.
`--shot` renders the HoloRoom to a PNG and quits (exit 2 under `--headless`:
no renderer). `--offscreen` sets windowed mode, then
`DisplayServer.window_set_position(12000, 12000)` from code and prints where
the window went (this Godot build ignores `--position`).

**Honesty.** Seat verdicts are one dated MSI probe (2026-11-07): every seat
now renders "seen 11-07 (not live)", dimmed, unless a fresh fleet snapshot
lists its process (`probe_seat`; today Claude and Ollama carry one). The web's
CHATDEV / OLLAMA / SKYCLAW nodes follow the same rule. The atlas header says
"N graded · M live", and counts as live only entries a fresh telemetry probe
observed up (overlay `live_probe`); with no fresh snapshot it says "0 live
(no fresh probe: telemetry …)". The ledger's status block is replaced in
place; only order events are kept below it (bounded, 6).

**Assign to seat (the war room's one write — local, fail-closed).** Pulling up
a seat, a rig card, or an atlas entry offers "Assign to seat". It appends one
line to a local outbox JSONL (`GSV_WAR_ROOM_OUTBOX_PATH`; the conventional
place is next to the fleet snapshot, e.g. `<state dir>/war-room-outbox.jsonl`):

    {"at","from":"keath","kind":"order","id":"o-<ms>-<hex>","to":SEAT,"text":CARD_TITLE,"via":"muse-war-room"}

The colony's feeder relays outbox lines to the shared channel — Godot never
writes remotely, never POSTs, never runs a shell. URLs, UNC shares, `res://`,
relative paths and non-`.jsonl` files are refused; a full outbox (1 MB, feeder
not draining) disables the action. No outbox configured → the button is
disabled and says why. When `GSV_WAR_ROOM_CHANNEL_PATH` points at a local copy
of `channel.jsonl`, the room shows the order's status (pending → relayed →
the latest matching `order-status` line), polled every 10 s only while an
order is outstanding.

**Tests.** `tests/war_room_agents_test.gd` (smoke-gate case `war-room`), and
an opt-in `--shot PATH` render case in `tests/godot_smoke_gate.py` (GPU
session; PNG signature + size checked by `assess_shot`).
