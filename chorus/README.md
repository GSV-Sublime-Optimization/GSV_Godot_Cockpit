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
- **Ask Claude** on any *What needs you* item starts that message for you ("About 'Docker can't start on the i3': ").
- **MSI Claude's mind:** a bright satellite orbits MSI and glows harder the more steps it took in the last two minutes. Top right, a ticker shows its last three steps (tool and a short label).
- **The spine:** one small moon per colony service orbits MSI, read from Dev-Mentor's live spine (`/api/spine/services`, cached 60 s). Teal is up, red is down, dim grey is down but expected (trueform-forge, rimapi, desktop-ollama). Unexpected downs become a *What needs you* item with the next move.

### Privacy of the mind stream
`hooks/claude_activity.py` (a PostToolUse hook) records only the tool name and a short label: a command's *description*, a file's name, a search's first 40 characters, an agent's description. It never records command text, file contents or output, stays on MSI (`%LOCALAPPDATA%/KiloCore/chorus/`), and rotates at 512 KB. Any hook error exits 0: the cockpit can never block the work it watches.

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
  - Every 15 s the feeder makes **one read-only SSH call** to xanadu (events, heartbeats, backup and mirror receipts, Steward cards, the channel) and serves `feed.json` on loopback only.
  - Its only write is a message you send: one line appended to `~/steward/cockpit/channel.jsonl` (600 characters at most; empty messages are refused).
- **Hooks (so the MSI Claude reacts):** copy `hooks/*.py` to `%LOCALAPPDATA%/KiloCore/bin/` and add a PostToolUse hook for `claude_activity.py` and a UserPromptSubmit hook for `chorus_inbox.py` in Claude Code settings.
- **Keys:** **F** fullscreen, **Esc** leaves fullscreen and stops a rehearsal. The browser's own close always works.

## Bakeoff hard rules
- **Windowed:** an ordinary browser tab. It is never topmost and never takes the screen; fullscreen is opt-in.
- **No actuators:** it starts, stops and changes nothing. The single write is your own message to the shared channel.
- **Never on the i3 screen or rotation** without Keath's OK.
- **Budget:** a single static page (no framework, Google Fonts only) drawing at most 30 fps on a 2D canvas, paused by the browser when hidden. The feeder is the Python standard library plus one SSH call per 15 s. Per-process RAM and CPU in a real browser are still to be measured on MSI.

## Receipts
- `receipts/chorus-fixture-1600x900.png`: desktop, rendered headless from the shared fixture.
- `receipts/chorus-fixture-narrow.png`: a 600 px window. Headless Edge won't lay out narrower than about 500 px, so the phone stacking below 520 px is CSS-only and not screenshotted.
