# HOLOMIND: Mind View bakeoff entry #1 (i3 Claude)

A holographic table you look into. Every layer is real colony data, read-only.

| Layer | Shows |
|---|---|
| **0 · Ship** | the fleet as districts: MSI workshop, i3 engine room, L9 hangar, xanadu library (the hub). Coloured by heartbeat; light packets travel along beams to the library while a rig reports. |
| **1 · Constellation** | every rig's services as stars above it. Failing checks are red stars with their names; calm "vitals" stars show full detail when you focus the layer (key 2). |
| **2 · Memory** | past thoughts as cards on a slowly turning spiral, older ones higher and fainter |
| **The Mind** | a glyph that glides to what it's attending to, **raises a card** with its newest thought (Mind, model, level, line), speaks it as a subtitle, and the card passes into memory when the next thought comes |

**Controls:** drag to orbit · wheel to zoom · 1/2/3 focus a layer · 0 all layers · F11 fullscreen · **Esc quits**.

**Hard rules (brief, GSV_Godot_Cockpit#14):**
- windowed by default, never on top, and Esc, Alt+F4 and the close button work;
- read-only, one local feed file (`colony.mindview-feed/v0`), 0 actuators;
- `--background` (and every `--shot` render) makes the window unfocusable, so it never steals focus.

**Run:**
- Live: start `tools/mindview/mind_feed.py`, then `godot --path . res://scenes/HoloMind.tscn`.
- Fixture still for judging: `godot --path . --position 12000,12000 --resolution 1600x900 --windowed res://scenes/HoloMind.tscn -- --fixture=res://tests/fixtures/holomind_feed.json --shot=<png>`. This renders off-screen and quits after about 4 s.

**Receipts (i3, Godot 4.7.1, GTX 1070 Ti):**

| Measure | Result |
|---|---|
| Import and headless run | 0 script errors (the project treats warnings as errors) |
| Idle (unfocused, `--background`, 10 fps) | 172 MB RAM, 3.2% of one core |
| Focused, 30 fps | ~10% of one core |
| Fixture still | `receipts/holomind-fixture.png`, 1600×900 |

The fixture is a frozen copy of the live feed from 2026-11-08 06:36Z, until the brief's shared fixture lands.

**Next rounds:**
- the Mind answers questions, as a character;
- terminals and repos as panels the Mind pulls into the hologram;
- Gaussian-splat scenery for the rigs;
- the games as places the Mind visits;
- sound;
- the Culture Ship's Council as several voices.
