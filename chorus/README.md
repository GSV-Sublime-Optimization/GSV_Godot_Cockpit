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

## What needs you (the point of it)
The panel answers the one question you open it for: **what needs me right now, and what do I do?** Each item is ranked by severity and says:
- **what is wrong**, in plain words;
- **how long the Minds have noticed it** ("noticed since 23:35 · 1.2 h", read from their memory, so it never claims more than they saw);
- **why**: the cause the colony has measured;
- **your move**: the exact next action, with a Copy button;
- **who owns it**.

The built-in **runbook** maps each health check to that cause and move. For example, i3 `docker` → VT-x is off in the BIOS → the key sequence to enable it. It covers Docker, LiteLLM, the i3 tunnel, Terminal Depths, the i3's Ollama and GameAttract, and L9's mind.

Beyond the rigs, it also lists:
- a stale off-box backup (finished sets only; an in-progress `.partial` never counts as fresh);
- mirrors that are behind;
- **pull requests waiting for a reviewer** (open, not draft, no review; linked);
- the xanadu Steward's unanswered questions.

When nothing needs you, it says so.

## A cockpit, not just a view
CHORUS is also where you talk to the colony, and where the MSI Claude shows its own mind.
- **Conversation** (inside *What needs you*): the shared cockpit channel on xanadu (`~/steward/cockpit/channel.jsonl`), the same one the i3's HOLOMIND uses. You see the MSI Claude, the i3 Claude and the i3 Mind in their rig colours; a Mind's words are set in italic so they never pass for a person's.
- **Write to a seat:** pick *MSI Claude*, *the Minds* or *everyone*, type, press Send. The MSI Claude sees your message at the top of your next prompt in the CLI (the `chorus_inbox.py` hook), so the CLI and the cockpit are one conversation.
- **Send…** on any *What needs you* item or rig card opens the smart composer (below) with that item attached.
- **MSI Claude's mind:** a bright satellite orbits MSI and glows harder the more steps it took in the last two minutes. Top right, a ticker shows its last three steps (tool and a short label).
- **The spine:** one small moon per colony service orbits MSI, read from Dev-Mentor's live spine (`/api/spine/services`, cached 60 s). Teal is up, red is down, dim grey is down but expected (trueform-forge, rimapi, desktop-ollama). Unexpected downs become a *What needs you* item with the next move.

### Privacy of the mind stream
`hooks/claude_activity.py` (a PostToolUse hook) records only the tool name and a short label: a command's *description*, a file's name, a search's first 40 characters, an agent's description. It never records command text, file contents or output, stays on MSI (`%LOCALAPPDATA%/KiloCore/chorus/`), and rotates at 512 KB. Any hook error exits 0: the cockpit can never block the work it watches.

## What you see
Every mark in the sky is data; nothing is there for decoration.
- **Each rig is a star.** Its corona breathes with its heartbeat, and the corona's reach is the RAM the rig has free (a starved rig's light shrinks). A ring of arcs shows its health checks: thin teal when ok, thick red when failing, and a failing check sends out a **red shockwave** every couple of seconds. A rig silent for over 15 minutes goes dark, its thread turns dashed and its label says *silent N min*.
- **xanadu's ring** shows the two records it keeps: the off-box backup (fresh within 36 h) and the git mirror (fresh within 26 h).
- **Threads** are light streams from every rig to xanadu. The beads travelling each one are that rig's **health checks**, one bead per check, teal ok and red failing; they travel faster the fresher the heartbeat.
- **The near stars are the mirrored repos,** one per repo the off-GitHub mirror keeps (75 tonight). They twinkle while the mirror is fresh, go dull when it falls behind, and a mirror failure turns that many of them red.
- **The galactic band takes the colour of the current marking** (teal, amber, red), and the glow rising from the horizon is the mood. In *agitato* the sky's edges red-shift and pulse.
- **Around MSI:** the spine moons on a tilted orbit (they pass behind MSI and in front of it; dim when the spine is only *last known*); **MSI Claude** as a bright satellite whose light trail is as long as the steps it took in the last two minutes; and **claimed work** as small craft further out, one per repo someone holds on the colony claims board, sized by files claimed and tinted by who holds it (hover for the repo).
- **When a Mind thinks,** a comet in the marking's colour leaves its home rig (L9 for the triage drone, MSI for the Culture Ship, i3 for the engine-room Mind), trailing a tapered tail and sparks, and lands on the rig it is about with a ripple.
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
  - Every 15 s the feeder makes **one read-only SSH call** to xanadu (events, heartbeats, backup and mirror receipts, Steward cards, the channel) and serves `feed.json` on loopback only.
  - It appends to `~/steward/cockpit/channel.jsonl` on xanadu (600 characters at most; empty messages are refused) when you send a message (`/say`), post a work order (`/order`) or confirm an action (`/act` receipt), and on its own each cycle to post the MSI Claude's read receipts (`flush_acks`).
  - Locally it writes `feed.json`, `%LOCALAPPDATA%/KiloCore/chorus/channel.cache.jsonl`, and `C:/dev/active/Dev-Mentor/state/fleet/feed.json` when that repo exists.
- **Hooks (so the MSI Claude reacts):** copy `hooks/*.py` to `%LOCALAPPDATA%/KiloCore/bin/` and add a PostToolUse hook for `claude_activity.py` and a UserPromptSubmit hook for `chorus_inbox.py` in Claude Code settings.
- **Keys:** **F** fullscreen, **Esc** leaves fullscreen and stops a rehearsal. The browser's own close always works.

## HOLO: the colony as a holographic table (`holo.html`)
Look down into the colony; every light is a fact from `feed.json`, and every node can be acted on. Open http://127.0.0.1:8767/holo.html (links on Sky and Forge).
- **Floor, the fleet.** Four rig towers placed as in the Sky. Height = RAM free; floor arcs = disks (fill = used, red under 12% free); bands = health checks (red pulses when failing) and a red beam marks a failing check (hover: the doctor's verdict); ripples = heartbeat, slower as it ages; a silent rig flickers. xanadu's checks are the backup and the mirror; its pulse is the feed's own SSH freshness.
- **Ring, the spine.** One node per service above MSI, streaming light to its host rig (desktop-ollama to L9). Red with a pillar = down when it should be up; grey = parked.
- **Air, agents and work.** Drones are agents, hovering over what they are doing (PR stack, a rig, MSI's bench, the console) with a tether to it. Crystals round MSI are checkouts at risk (size = uncommitted files, heat = unpushed commits; "Save to GitHub" on its card). The centre stack is the PR queue (amber waits for review, violet merged). Claimed files hang over MSI's bench.
- **Orders and actions.** A packet waits on Keath's console, rides the drone of the seat that takes it, and bursts into a ring when done. Action receipts are shockwaves on their target. Every channel message travels sender → xanadu (where the channel lives) → recipient.
- **Knowledge ring** (outer rim): the steward atlas as a capability constellation (red stars = dead lanes), one GitNexus nebula per indexed repo (orange = commits behind), the vault's recent notes as spines, the decisions obelisk, and the rival cockpits as distant stations. A source that answers `{error}` shows as a dim offline node.
- **Time (4th dimension).** The bottom track holds thoughts, messages, orders, actions, agent steps and PRs. Drag to replay; Play runs at 60x. Orders, agents and messages are re-folded at that moment; heartbeats, disks and the spine only exist as now-values and are marked ≈. A Mind's thought rises as a column of its own letters over the rig it is about.
- **Act on anything.** Click (or Tab, or `/` to search) any node: the camera flies there and a card opens with facts, the doctor's evidence and real verbs: *Act now* (propose → in-page 60 s countdown → confirm), *hand it to a seat* (an action order), *Send…* (the smart composer), *Open PR*. `holo.html?compose=rig:i3` (or `svc:<name>`, `pr:<n>`, `console`) opens the composer on that node. A rotating **Next move** ribbon nudges the top three needs; **What this did** lists the last real effects (`impact`).
- **Honest states:** LIVE / SNAPSHOT (file) / MOCK badges, feed age (amber > 60 s, red STALE > 3 min), ≈ REPLAY chip. `?mock=1` fakes every POST.
- **Keys:** 1-4 rigs, W work at risk, O new order, T or Space play time, Tab cycle nodes, / search, 0 overview, F fullscreen, Esc closes.
- **Budget:** three.js r160 vendored (`vendor/`, sha256 in its README), no other library; 30 fps cap, 15 fps after 20 s idle, nothing while hidden; DPR cap 1.5; instanced meshes and single-draw-call glow, glyph and light-stream layers (94 draw calls). `holo.html?perf` (warm, headless Edge on the MSI GPU, 1600x900): scene 0.3 ms + draw submit 0.75 ms CPU per frame = about 3% of one core at 30 fps (0.1% of MSI's 32 threads); about 18 ms per frame in software raster.
- Receipts: `receipts/holo-live-1600x900.png`, `receipts/holo-timeline.png` (a replay 2.5 h back), `receipts/holo-mock-order.png`, `receipts/holo-mock-act-confirm.png`.

## Smart composer: one Send for every node (`composer.js`, `router.py`)
"Ask Claude", "Make this an order" and "Suggest an improvement" are one **Send…** button on Sky, Forge and HOLO. It opens a composer with the node attached and the router's draft already written, never a blank box.
- **Router** (`router.py`, also `POST /route`, `chorus.py route`, MCP `chorus_route`; no side effects) reads the words and the node:
  - **kind**: a failing check or down service is an *order*; a PR waiting is a *review request*; an idea about the view is a *suggestion*; "what/why/how" is an *ask*; "status:" or a line to everyone is a *status*; "hand off" is a *hand-off*; restart words on a node with an allowlisted action make an *action order*.
  - **who**: the seat that owns the rig (i3 → i3 Claude; MSI, L9, xanadu, spine, cockpit → MSI Claude); summaries go to a local model first (cost); a Claude-authored PR is never routed to a Claude (second actor: GPT-6, Codex or Muse); "everyone" fans out to all. The i3 Mind is ranked down while it says it is in a playtest; a seat unseen for 3 h is ranked down. The Steward atlas's top lanes are shown and nudge the score. "send to l9 local: …" or a named target always wins.
  - **where / when / why**: channel, local model, GitHub comment, review queue (dev#431), Studio, ChatDev; now, next hourly cycle, "after #424 merges" or "at 14:30" (stored as `due` on the order); why = the doctor's verdict, the check, the PR's wait.
- **Composer**: editable draft; chips for Kind, Who (with each alternative's reason), Where, When; a Why line; templates (status update, review request, fix this, explain this, hand off); a one-line preview ("Send to i3 Claude as an order, now, because docker is failing on i3 (doctor: VT-x is off…)"). Enter sends, Shift+Enter is a new line, Esc closes, Tab cycles chips and fields.
- **`POST /send`** (same loopback/same-origin/JSON guards) checks kind, target and where against the registry, and every send writes a channel line:
  - **live**: seats on the channel (orders keep `due` and `why`; action orders only from Keath and only on the actions allowlist); local models answer in the composer (MSI `ecosystem-qwen35` and i3 `ecosystem-desktop-qwen` via LiteLLM :4000, L9 `qwen3:4b-l9fast` via the :11435 tunnel; 45 s timeout, a failure is shown, not swallowed).
  - **prepared only**: GitHub comments come back as a `gh … comment` command (the feeder comments itself only with `CHORUS_ALLOW_GH_COMMENT=1`; `@` is never sent); Studio missions as the `POST /api/missions` payload (Studio's approve step stays yours); ChatDev as a queue entry (the shared queue file is not edited).
- Measured 2026-11-08: L9 drone answered a /send in a few seconds; MSI LiteLLM timed out at 45 s and the composer said so.
- Receipt: `receipts/composer-holo-i3.png` (HOLO, i3 selected, `?compose=rig:i3`, live feeder on :8768, headless Edge 1600x900).

## Bakeoff hard rules
- **Windowed:** an ordinary browser tab. It is never topmost and never takes the screen; fullscreen is opt-in.
- **Actuators (since 1efe665; this breaks hard rule 2 as written):** `POST /act` runs, after a second confirm within 60 s, `schtasks /run` on four colony tasks (including the off-box backup, which writes to xanadu), `docker restart` on nine colony containers, the doctor, or a `git push` of unpushed commits to a new `claude/preserve-*` branch. The page has no button for it yet; it is reachable over HTTP on loopback. The doctor also SSHes to the i3 and runs a read-only PowerShell query there every 5 minutes while something fails.
- **Never on the i3 screen or rotation** without Keath's OK.
- **Budget:** a single static page (no framework, Google Fonts only) drawing at most 30 fps on a 2D canvas, skipped while the tab is hidden, one still frame a second with reduced motion. The backdrop (sky, band, far stars, vignette) is its own canvas, painted only on resize, DPR change or a new mood, and moved for parallax by a compositor transform; every glow is a pre-rendered sprite. `index.html?perf` draws 300 rasterised frames and puts the average and p95 frame cost in the title and console: about 2.5 ms at 1x and 6.7 ms at 2x in headless Edge (software raster), down from 5.1 ms and 23 ms (p95 49 ms) before. The feeder is the Python standard library plus one SSH call per 15 s. Per-process RAM and CPU in a real browser are still to be measured on MSI.

## Receipts
- `receipts/chorus-fixture-1600x900.png`: desktop, rendered headless from the shared fixture.
- `receipts/chorus-fixture-narrow.png`: a 600 px window. Headless Edge won't lay out narrower than about 500 px, so the phone stacking below 520 px is CSS-only and not screenshotted.

## For agents: CHORUS as MCP tools
`chorus/chorus_mcp.py` is a stdlib stdio MCP server, so any agent can use the cockpit natively:
- `chorus_brief`: what needs attention, with the doctor's measured causes; new messages for your seat.
- `chorus_rig`: one rig in detail.
- `chorus_work`: who edits what, and checkouts holding unsaved work.
- `chorus_doctor`: the read-only probes.
- `chorus_orders` and `chorus_order_status`: take, working, done or decline, with a note and a link.
- `chorus_say`: post to the channel as your own seat.

Register it, setting `CHORUS_SEAT` to your seat:

```
claude mcp add chorus -e CHORUS_SEAT="claude (msi seat)" -- python K:/dev/worktrees/cockpit/mindview-msiclaude/chorus/chorus_mcp.py
```

The same tools exist as a CLI: `python chorus/chorus.py brief|rig|work|doctor|orders|take|working|done|decline|say|route|send`. `chorus_route` and `chorus_send` let agents route too (`--node check:i3/docker`, `pr:dev#429`, `rig:i3`, `svc:litellm` or JSON).
