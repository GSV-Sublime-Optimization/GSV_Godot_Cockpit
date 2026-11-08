# CHORUS: the colony's minds, seen and heard

**Mind View bakeoff entry from the MSI Claude seat** (GSV_Godot_Cockpit#14).

The fleet is drawn as a night sky. Each rig is a star with its own colour and its own note:

| Rig | Role | Colour | Note |
|---|---|---|---|
| MSI | workshop | brass | C |
| i3 | engine room | ember | E |
| L9 | drone | glacier | G |
| xanadu | librarian | lilac | B |

Together the four notes make a Cmaj7 chord: the whole fleet in tune.

## What you see
- **Each star breathes** with its heartbeat. A ring of arcs around it shows its health checks: thin teal when a check is ok, thick red when it fails. A rig whose heartbeat is older than 15 minutes dims, its thread to xanadu goes dashed, and its label says *silent N min*.
- **Threads** carry heartbeats from every rig to xanadu, which keeps the record. A small pulse travels each thread.
- **When a Mind thinks,** a comet leaves its home rig (L9 for the triage drone, MSI for the Culture Ship, i3 for the engine-room Mind) and lands on the rig it is about, with a ripple.
- **The thought is engraved bottom-centre like a score marking:**
  - *tranquillo* (routine, teal);
  - *attento* (notable, amber);
  - *agitato* (alarm, red; the sky's glow pulses).
- Under the thought: which Mind said it, the model, how long it took to think, and its **reasons** as chips. The chips are the facts behind the words.
- **Memory** along the foot holds every past thought as a coloured drop on a time axis; click one to replay it.

## What you hear (opt-in: press **Sound**)
- *tranquillo*: a soft Cmaj7 pad, every rig's note at once.
- *attento*: a suspended chord that wants to resolve.
- *agitato*: the root and the tritone, trembling.
- The rig in focus sings its own note on top, so with practice you can tell which rig a thought is about without looking.

## Honesty
- It shows only what the data says. A Mind's words are shown as said (the 05:35 alarm still says "insufficient RAM", which the reasons don't support). The reason chips beside them let you check.
- Stale data looks stale: silent rigs dim, and every thought shows its age.
- **Rehearse** plays five clearly labelled demo thoughts, including a silent MSI and the Culture Ship speaking. They show in the marking as *rehearsal* and are never added to Memory.

## Run it
- **Snapshot (no network to the fleet):** open `chorus/index.html` in any browser. It uses the shared bakeoff fixture, frozen 2026-11-08 06:48 UTC (`tests/fixtures/mindview-20261108/`).
- **Live:** `python chorus/mindview_feed.py`, then open http://127.0.0.1:8767/.
  - Every 15 s the feeder makes **one read-only SSH call** to xanadu (`~/steward/events/*.jsonl` and `~/steward/heartbeats/*.json`) and serves `feed.json` on loopback only.
  - It never writes to xanadu.
- **Keys:** **F** fullscreen, **Esc** leaves fullscreen and stops a rehearsal. The browser's own close always works.

## Bakeoff hard rules
- **Windowed:** an ordinary browser tab. It is never topmost and never takes the screen; fullscreen is opt-in.
- **Read-only:** zero actuators, and no writes anywhere.
- **Never on the i3 screen or rotation** without Keath's OK.
- **Budget:** a single static page (no framework, Google Fonts only) drawing at most 30 fps on a 2D canvas, paused by the browser when hidden. The feeder is the Python standard library plus one SSH call per 15 s. Per-process RAM and CPU in a real browser are still to be measured on MSI.

## Receipts
- `receipts/chorus-fixture-1600x900.png`: desktop, rendered headless from the shared fixture.
- `receipts/chorus-fixture-narrow.png`: a 600 px window. Headless Edge won't lay out narrower than about 500 px, so the phone stacking below 520 px is CSS-only and not screenshotted.
