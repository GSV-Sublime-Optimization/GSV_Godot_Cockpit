# The Ledger — Muse's Mind View entry (bake-off)

**Branch:** `bakeoff/mindview-muse` · **Status:** draft, slice 0 (mockup + code; render receipt queued)
**Form:** Godot 4.7.1, 2D `Control`, custom `_draw()` · **Scene:** `scenes/LedgerView.tscn`
**Feed:** the shared fixture directory, read directly — never a copy:
`tests/fixtures/mindview-20261108/`

## 1. What it is

A watch-ledger of what the colony's Minds noticed. The differentiator none
of the three other entries has is **continuity across time — recurrence and
outcomes.**

- HOLOMIND (#15) is **space**: a 3D world you walk through.
- CHORUS (#16) is **space**: a 2D night sky you look up at.
- The Cognitive Loom (#18) is **sequence**: a tape of thoughts in order.
- The Ledger is **time + memory**: the colony's noticing over time — what
  keeps coming back, what got fixed, what a Mind proposed and what came of
  it.

Ship Minds (`docs/fleet/SHIP_MINDS_2026-11-07.md`, dev #419) §9 says a Mind's
value is its ledger — "this is the third time this week". The Ledger makes
that visible. It is the only entry whose headline is a number, not a vibe:
**"i3 failing: docker — 4× in 61 min."**

## 2. What slice 0 shows (one screen, 1600×900)

| Region | Content |
|---|---|
| **Time-river** (top left) | x-axis is time, 05:35 → 06:48 freeze. One lane per rig (MSI / i3 / L9 / xanadu). Thoughts are marks on the river (alarm red tall, notable amber, routine teal — none in the fixture, and the entry says so). Recurrences stack into towers. Heartbeats are diamonds on their lane. The xanadu lane honestly shows "no heartbeat in fixture". |
| **Latest-thought card** (top right) | The 06:36 "i3 failing: docker" — large and legible at a glance, with mind / model / think time (16,578 ms) / stated reasons / recurrence context ("4th of 4 noticings"). |
| **What needs you** (bottom left) | Derived ONLY from fixture data. Each item: what / measured cause / copyable next move / owner. |
| **Outcomes** (bottom right) | Each item carries what happened next, aged against later fixture facts. An alarm that ages out is kept, not deleted. |
| **Footer** | Unexercised states, listed never faked; provenance; the suggestions pointer. |

Header badges, always on screen: `SHARED FIXTURE · frozen 2026-11-08 06:48 UTC`
· `OBSERVATION ONLY · 0 ACTUATORS` · `ESC EXIT · F11 FULLSCREEN`.

## 3. The fixture, inventoried (frozen 2026-11-08 06:48 UTC)

Source of every number below: `tests/fixtures/mindview-20261108/` —
`events.jsonl` (4 lines) + `heartbeat_msi.json` + `heartbeat_i3.json` +
`heartbeat_l9.json`. Verified byte-identical between the #15 and #16
branches before this entry was built.

- **4 events, 1 mind, 1 model.** All `l9-triage-drone` / `qwen3:4b-l9fast`,
  05:35–06:36 UTC. Levels: 1 alarm, 3 notable, **0 routine**. The calm state
  never occurs in fixture data.
- **The story is recurrence.** "i3 failing: docker" appears in the reasons
  of all 4 events across 61 minutes (05:35, 06:16, 06:21, 06:36). The 05:35
  alarm's line is longer ("Critical backups overdue (109h old) and multiple
  system failures…", 3,055 ms think time); the three notables are the bare
  line (1,794 / 1,711 / 16,578 ms).
- **3 heartbeats.** MSI 06:45:03Z green (dev-mentor ok, 15 ms; docker ok,
  24 containers). i3 06:46:42Z green:false — docker FAIL: `docker info`
  timed out after 20 seconds. L9 06:36:20Z green, via observer msi.
  **No xanadu heartbeat.**
- **Disk pressure is in the data and no entry surfaces it.** MSI C: 8.5%
  free (78.2 GB); i3 C: 9.5% free (22.1 GB). Both under the 10% alarm
  threshold. The Ledger surfaces it as needs-you item #2.
- **The backup claim is a claim, not a fact.** The 05:35 alarm's reasons
  include "off-box backup 109 h old (alarm > 36 h)". No backup or mirror
  record exists anywhere in the fixture. The Ledger lists it as
  `UNVERIFIED CLAIM` and the copyable move is to check the real record.

### Outcomes (aging, first-class)

- The 05:35 alarm said "msi failing: dev-mentor". MSI's 06:45 heartbeat is
  green and dev-mentor answers in 15 ms. **Outcome: AGED** — the alarm's MSI
  half did not survive the morning. Shown, not deleted.
- i3 docker was named 05:35, 06:16, 06:21, 06:36 — and the 06:46 heartbeat
  still shows docker FAIL. **Outcome: UNRESOLVED** — four noticings, no fix
  recorded in the fixture.

### Unexercised states (footer, never faked)

Routine / calm · xanadu heartbeat · silent rig (i3 is red-with-cause, not
silent) · backup / mirror records.

## 4. How it differs — the comparison

| | HOLOMIND #15 | CHORUS #16 | Loom #18 | **The Ledger (Muse)** |
|---|---|---|---|---|
| Core metaphor | 3D world, Mind as participant | 2D night sky | Attention field + thought tape | **Time-river + ledger** |
| Differentiator | Presence: the Mind glides, speaks, opens terminals | "What needs you" panel; doctor re-measurement | Source honesty is structural; exit discipline | **Recurrence + outcomes: what keeps coming back, what happened next** |
| Fixture use | Renders shared fixture but not the default; committed feed lacks keys its headline features read | Embedded fixture drifts from the files (drops floor/simulated/disks); snapshot stitches two time bases | Fixture copy already drifts; no PNG receipts | **Reads the shared fixture directory directly, default; byte-verified against #15/#16 copies** |
| Legibility | Weakest point: clipped header, label pile-up, table ~40% | Narrow receipt stale; panel occludes sky | Text-and-diagram, not a world | **Legibility is the design bar: header inside the frame, no overlapping labels, one screen** |
| Actuators | — | **Breaks hard rule 2**: POST endpoint runs tasks, restarts containers, pushes branches | Zero | **Zero, in code and in fact — no POST, no /act, no writes** |
| Exit discipline | — | — | Correct (windowed, Esc, F11-only) | **Copied from the Loom, plus a unit-tested pure key dispatch** |
| Disk pressure | In its data, unsurfaced | In its data, unsurfaced | In its data, unsurfaced | **Surfaced as needs-you item #2** |
| Outcomes / aging | — | Doctor re-checks a claim | — | **First-class outcomes column** |
| Suggestions channel | — | `/suggest` endpoint | — | **`SUGGESTIONS.md` in the PR + footer pointer** |

Kept from the #12 baseline (head `5cd14adf`): the fleet-map + transcript +
large latest thought is the most Keath-legible layout, and the feeder
narrates change. Not kept: the trap — #12's README says `--fullscreen` and
`MindView.gd` contains zero input handling and zero exit path. The Ledger's
hard rule, verified by test: **escapable by keyboard alone, in every state,
including with a missing/bad feed.**

## 5. Hard rules (enforced in code, checked in tests)

1. **Windowed by default, never topmost.** `Engine.max_fps` 30 focused,
   10 backgrounded/minimised. F11 alone toggles fullscreen.
2. **Esc quits immediately** — the handler lives in `LedgerView.gd` itself
   and dispatches through a pure `_key_action()` function, so the exit
   contract is unit-tested without quitting (`tests/ledger_scene_test.gd`).
   It works with a missing or malformed feed: the error state still draws
   and still quits.
3. **Zero actuators.** The feed reader opens local files for reading only.
   No HTTP, no shell, no writes, no tasks, no containers. The next step is
   a copyable move + owner; the action happens elsewhere, by an agent.
4. **No fake data.** The fixture is the data; it is labelled fixture, never
   live. Missing data renders as absence ("no heartbeat in fixture"). A
   Mind's unsupported claim renders as `UNVERIFIED CLAIM`. Mockups are
   labelled `MOCKUP — NOT A RENDER` in the image itself.
5. **One screen, legible.** Header inside the frame, no overlapping labels,
   everything at 1600×900 with a small-window guard below 930×540.

## 6. Token-saving statement

The entry is a cheap shared source of truth, and slice 0 says so concretely:

- **It reads the fixture / local snapshot and nothing else.** No LLM calls,
  no re-probing, no network. Opening the Ledger costs zero model tokens
  and zero fleet probes — the noticing it shows was already paid for when
  the Mind ran.
- **It answers the "what keeps coming back?" question without a re-read.**
  Recurrence (4× in 61 min) and aging (alarm superseded by a green
  heartbeat) are computed from the frozen files, so a reviewer does not
  have to re-derive them by re-reading four events and three heartbeats —
  or by asking a model to.
- **It stops the most expensive failure mode: acting on a stale claim.**
  The 109 h backup claim and the 05:35 "msi failing" alarm are both shown
  with their later facts attached, so no agent burns a session (or a
  human burns an evening) chasing a failure that already aged out.
- **It is cheap to run.** Custom `_draw()` on one `Control`, 30 fps
  focused / 10 fps backgrounded, no 3D scene, no per-frame allocation
  beyond the redraw throttle. The render cost is a static picture that
  refreshes ~10×/s at most.

## 7. Files

```
docs/mindview-muse/DESIGN.md            this document
docs/mindview-muse/SUGGESTIONS.md       the suggestions channel
docs/mindview-muse/VERIFICATION.md      queued verification (NOT yet run)
docs/mindview-muse/mockup-1600x900.png  MOCKUP — NOT A RENDER
tools/mindview_ledger/LedgerFeed.gd     feed reader (RefCounted, no scene needed)
tools/mindview_ledger/README.md
scripts/LedgerView.gd                  the scene script (exit handler lives here)
scenes/LedgerView.tscn
tests/ledger_feed_test.gd              contract test (real fixture + fail-closed)
tests/ledger_scene_test.gd             scene + exit-contract test
tests/ledger_render_test.gd            1600x900 draw smoke
```

Run: `godot --path . res://scenes/LedgerView.tscn`
Shot: `godot --path . res://scenes/LedgerView.tscn -- --shot=<png>`
(`--fixture=<dir>` / `--feed=<dir>` override the source; `--background`
and `--no-animate` are accepted; remote URLs are refused as a data source.)

## 8. Verification status

- `gdparse` green on all five `.gd` files (gdtoolkit 4.5.0, this VM).
- **NOT yet run (queued behind Furyline Phase B, which holds the single
  Godot flight slot + 2,500 MB RAM gate):** headless import, the three
  test scripts, the `--shot` PNG at 1600×900, and RAM/CPU measurement.
  Exact commands: `docs/mindview-muse/VERIFICATION.md`. No Godot run was
  performed for this PR, on any machine.
- The mockup in this PR is drawn from the real fixture text by hand
  (PIL, 1600×900) and labelled `MOCKUP — NOT A RENDER` in the image. A
  mockup is a valid first entry per the brief.

## 9. What slice 0 does not do (future slices)

- Live feed: a `--feed=<dir>` path exists and re-reads on R, but no live
  collector is wired; the Loom's `collect_once.py` pattern is the model.
- Recurrence across days ("third time this week") needs a multi-day feed;
  the fixture covers 73 minutes, so slice 0 proves the mechanism on one
  morning, not the week view.
- No sound, no 3D, no second brain, no Forge. The Ledger's bet is that
  time + memory beats more space.
