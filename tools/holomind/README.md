# HOLOMIND: Mind View bakeoff entry #1 (i3 Claude)

A holographic table you look into. Every layer is real colony data, read-only.

| Layer | Shows |
|---|---|
| **0 · Ship** | the fleet as districts: MSI workshop, i3 engine room, L9 hangar, xanadu library (the hub). Coloured by heartbeat; light packets travel along beams to the library while a rig reports. |
| **1 · Constellation** | every rig's services as stars above it. Failing checks are red stars with their names; calm "vitals" stars show full detail when you focus the layer (key 2). |
| **2 · Memory** | past thoughts as cards on a slowly turning spiral, older ones higher and fainter |
| **The Mind** | a glyph that glides to what it's attending to, **raises a card** with its newest thought (Mind, model, level, line), speaks it as a subtitle, and the card passes into memory when the next thought comes. It also **brings up a holographic terminal** beside the rig it's watching (status, failing checks, last heartbeat, vitals), which folds away when its attention moves on. |

**Controls:** drag to orbit · wheel to zoom · 1/2/3 focus a layer · 0 all layers · F11 fullscreen · **Esc quits**.

**Hard rules (brief, GSV_Godot_Cockpit#14):**
- windowed by default, never on top, and Esc, Alt+F4 and the close button work;
- read-only, one local feed file (`colony.mindview-feed/v0`), 0 actuators;
- `--background` (and every `--shot` render) makes the window unfocusable, so it never steals focus.


## The cockpit (round 3): talk to it, see the agents, use it as an agent

- **Type to the colony.** The box at the bottom sends to the shared **cockpit channel** (`xanadu:~/steward/cockpit/channel.jsonl`). `@mind` is the default; `@claude`, `@msi`, `@muse` and the rest address an agent. It can only **talk**: nothing in the cockpit can run a command or change a system.
- **The Mind answers** messages addressed to it, using the i3's local model (qwen3:8b). It's grounded only on the feed (fleet, thoughts, agent activity), unloaded straight after (keep_alive 0), and **never runs while a game is playing**, because the GPU is shared. Every reply names its model.
- **The agents at work:** Claude, GPT-6, Codex, Muse, Gordon and others appear as avatars on the outer ring, or beside the rig they run on. Each shows its latest PR, from branch prefixes across the colony's busiest repos, and flares when there's new activity. Each one's latest words float above it as a speech bubble.
- **For agents:** `tools/holomind/cockpit.py say|read|ask`. Any Claude seat, Codex or script can talk in the same channel from a terminal, so HOLOMIND is a cockpit agents use, not just a view of them.
- **Feeder:** `tools/holomind/cockpit_feed.py` (stdlib). It replaces `mind_feed.py` for HOLOMIND, refreshes every 10 s, and reads GitHub every 3 min.


## The work queue (round 4): what needs doing, and who's on it

- **WORK WAITING** across the colony, in the header and as cards beside whoever it belongs to:
  - PRs waiting for a second review (open, not draft, no review decision), next to the agent whose PR it is;
  - red or silent rigs, over the rig;
  - the xanadu Steward's decision cards and the K: quarantine queue, by you;
  - channel messages nobody has answered yet.
- **`cockpit.py brief`** gives any agent on any rig the colony in one screen (rigs, agents at work, the work queue, the last messages), from `xanadu:~/steward/cockpit/brief.json`, which the feeder publishes every 10 s. Agents can start every task with it.
- The Mind's answers include the work queue in their context, so "what should I do next?" gets a grounded answer.

**Run:**
- Live: start `tools/holomind/cockpit_feed.py`, then `godot --path . res://scenes/HoloMind.tscn`.
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


## Running on other rigs

The Python tools read their per-rig settings from `tools/holomind/portable.py`. Every default is the i3's value, so nothing changes on the i3. Elsewhere, set:

| Env var | Default | Set it when |
|---|---|---|
| `HOLOMIND_DIR` | `C:\Users\Public\colony\mindview` on Windows; `$XDG_DATA_HOME/colony/mindview` (or `~/.local/share/...`) on Linux | you want the feed somewhere else. Then start Godot with `-- --feed=<HOLOMIND_DIR>/feed.json`. |
| `XANADU_SSH` | `xeno@100.74.243.72`; `local` when the hostname is `xanadu` | your rig reaches xanadu by another name or user |
| `OLLAMA_URL`, `OLLAMA_MODEL` | the i3's Ollama, `qwen3:8b` | the Mind should think somewhere else |
| `CHORUS_FEED_URL` | `http://127.0.0.1:8767/feed.json` on the MSI; unset elsewhere | you can reach CHORUS over HTTP. Unset means the i3's SSH hop: `CHORUS_MSI_SSH` and `CHORUS_MSI_KEY`. |
| `COLONY_QUARANTINE_QUEUE` | `K:\quarantine\QUEUE.md` | the queue lives elsewhere; a missing file is skipped |
| `COLONY_RIG` | from the hostname | the hostname guess is wrong |
| `GODOT`, `PYTHON`, `BAKEOFF_WORKTREES`, `COLONY_PORTS` | the i3's paths (`godot` and this Python off Windows) | you run `gallery.py` on another rig |

What still needs a specific rig:
- **The feeder** needs `gh` (logged in) and SSH to xanadu. The colony facts it shows (backup, mirror, spine) come from the MSI's CHORUS.
- **The scene** writes typed messages to `C:/Users/Public/colony/mindview/outbox.jsonl`, a constant in `HoloMind.gd`. Off Windows the feed is read through `--feed=`, but the chat box cannot send.

Tests: `python tools/holomind/test_portable.py` runs on Windows and Linux. It uses only the standard library and needs no network.
