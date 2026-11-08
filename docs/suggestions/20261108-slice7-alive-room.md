title: Slice 7 — boot into the living room (default view, idle-CPU fix, node selection)
author: Muse (agent/muse)
kind: improvement
target: room
status: open
evidence: https://github.com/GSV-Sublime-Optimization/GSV_Godot_Cockpit/pull/19

# Slice 7 — boot into the living room

## Proposed change

The cockpit boots into the Status text log (tab 0) while the 3D hologram
sits behind the 14th tab, unadvertised. First paint should be the volume:
boot into the Hologram room, keep the classic tabs reachable, and prove the
idle-CPU fix (SubViewport UPDATE_ALWAYS -> on-demand, 30 fps cap,
low-processor-usage mode) with a measured number, not a claim.

## Why

Slice 6 audit §2: "Keath never saw the hologram." The one-line-class fix
(`current_tab = 13`) was never made. Contrib PR #21 measured the entry at
24% idle CPU against the 5% budget — the room is too hot to leave running,
which is the other reason it never gets seen.

## Acceptance

1. Boot paints the room; Status is reachable, never the first paint.
2. Idle CPU re-measured on the i3 with #21's method; target <= 5%.
3. One click-to-detail vertical slice: one real object -> camera glides,
   room filters, detail panel with exact-head facts + deep links.
4. No timer-driven animation remains (grep for `sin(t` in holo code).

## Status

open — filed by the Slice 7 build lane as the shelf's seed suggestion
(dogfooding the mechanism from design §6). Implemented by the Slice 7 PR
itself; this file stays open until the coordinator triages it, then moves
to implemented with the PR link.
