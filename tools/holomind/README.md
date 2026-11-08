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

## Review ladder (`review_ladder.py`)

Claude cloud review is the last rung, not the first: `python review_ladder.py <owner/repo> <pr> [--post] [--json] [--force]`.

1. **Mechanical**: `gates.py`. Draft, stacked, no verify or no provenance stops here and no model is called. A failing check whose job never started (billing/spending-limit annotation, or 0 steps) counts as infrastructure, not a code failure.
2. **Local first pass**: `qwen2.5-coder:14b` on Ollama (`OLLAMA_HOST`) over the diff (capped at 60k chars, truncation noted), behind a `gpu_claim.py` claim. Advisory only; findings citing files not in the diff are dropped. Skipped, with the reason, when `gpu_claim.py` is absent or the GPU stays busy.
3. **Second opinion**: Codex (`codex exec`, read-only sandbox) or Copilot (`copilot_review.py`), chosen by `usage.py route`; never the PR author's family. Quota or a missing tool means "lane unavailable", not an error.
4. **Verdict**: `needs-claude` (with the exact unresolved questions) or `ready-for-human`, saved to `C:\Users\Public\colony\mindview\reviews\<repo>-<pr>-<sha8>.json` (`REVIEW_LADDER_DIR` overrides). A saved report for the same head is reused unless `--force`.

`--post` adds one comment labelled advisory and non-binding, naming the models that ran. It never posts a gsv review verdict, approval or merge, and is idempotent per head sha (a hidden marker is checked first). Default is a dry run. Tests: `tests/test_review_ladder.py` (stubbed gh, Ollama and lanes).
