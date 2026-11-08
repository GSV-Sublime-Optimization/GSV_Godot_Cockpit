# ΞNuSyQ-Prime: The Cognitive Loom

**Entry:** GPT-6 / NuSyQ Prime in [Mind View bakeoff #14](https://github.com/GSV-Sublime-Optimization/GSV_Godot_Cockpit/issues/14).

## Different by design

Not a holographic tabletop or a plain colony log. **Cognitive Loom** treats
recorded Mind events as a navigable *evidence sequencer*. The central body is
a bounded rig-attention diagram; the bottom strip is an interactive thought
tape; the right-hand inspector exposes exactly the reported summary,
timestamp, model or deterministic observer, attention focus and stated
reasons. This is inspired by the *functional interaction grammar* of a DAW
(solo a Mind, scrub a tape, swap semantic lenses), **not** an audio sequencer
or a claim to read hidden model chain-of-thought.

This is a **read-only Godot 4.7.1 scene**, standalone from the existing
cockpit and from other contestants' Godot applications. The start scene and
other agents' game or Mind branches remain unchanged.

### Controls

| Control | Action |
| --- | --- |
| Mouse | Select a thought, Mind filter, rig or semantic lens |
| Left / Right | Scrub recorded thoughts |
| Space | Play/pause local replay of the *recorded* event tape |
| 1 / 2 / 3 | Pulse waveform / Stated reasons / Fleet vitals |
| M | Filter: all, model summaries, deterministic observer events, colony work |
| R | Reload local feed file |
| F1 or ? | Input and safety guide |
| F11 | Explicit fullscreen toggle |
| Esc, Alt+F4, window close | Close immediately, even with missing feed |

Default is **windowed, not topmost**. No automatic i3 screen launch, no
autonomous GameAttract registration, no production radio interactions.
There are **zero actuators**, no hidden shell and no remote SSH inside
Godot. A report marked `green` means the source *reported green*; it is
not independent authorization or a guarantee that a process is online.

### Identical fixture to the other entry

`tests/fixtures/prime_mind_feed.json` is an **exact copy of the
i3 Claude HOLOMIND fixture from its reviewed SHA
`3341c331117682defecdcd2e79114f3362aa18bd`**, originally
`tests/fixtures/holomind_feed.json`. This allows side-by-side evaluation
without changing event facts to flatter one entry. It is marked
`PINNED FIXTURE` on-screen even when its original producer was connected.
The dedicated bakeoff issue has not supplied an independent official common
fixture yet.

### Commands (MSI, Godot 4.7.1)

```powershell
# Do not change the default GSV cockpit entrypoint.
& 'C:\dev\tools\godot\4.7.1\Godot_v4.7.1-stable_win64.exe' --path . --windowed res://scenes/PrimeMind.tscn -- --fixture=res://tests/fixtures/prime_mind_feed.json

# Native negative controls and scene interactions:
& 'C:\dev\tools\godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --script res://tests/prime_mind_contract_test.gd
& 'C:\dev\tools\godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe' --headless --path . --script res://tests/prime_mind_scene_test.gd

# Noninteractive offscreen rendering, no focus:
& 'C:\dev\tools\godot\4.7.1\Godot_v4.7.1-stable_win64.exe' --path . --position 12000,12000 --resolution 1600x900 --windowed res://scenes/PrimeMind.tscn -- --fixture=res://tests/fixtures/prime_mind_feed.json --shot=C:\dev\.colony\scratch\prime-mind-fixture.png
```

### Optional honest live mode, manually supervised

The feeder needs the already-authenticated MSI SSH alias `xanadu`. It
performs exactly one **read-only** remote Python invocation, reading only
`~/steward/events/*.jsonl`, `~/steward/heartbeats/{msi,i3,l9}.json` and the
tail of `~/steward/cockpit/channel.jsonl`.
It writes **only** the operator-chosen local output file. No credentials,
port listeners or background agents are created on Xanadu.

```powershell
python tools/prime_mind/collect_once.py --output 'C:\dev\.colony\scratch\mindview-prime-live.json'
& 'C:\dev\tools\godot\4.7.1\Godot_v4.7.1-stable_win64.exe' --path . --windowed res://scenes/PrimeMind.tscn -- --feed=C:\dev\.colony\scratch\mindview-prime-live.json
```

Godot only polls that **local file** every 15 seconds, never SSH. If it
becomes old, unreadable, malformed or absent, show that honestly. A valid
read of Xanadu's archive doesn't certify radio service, heartbeat accuracy,
agent permissions or current remote tool health. No observer lines are
manufactured by the collector: `model=null` lines remain deterministic
reports from their original source.

### Engineering constraints and evidence

- Event data cap 192KiB, 80 entries, eight reasons per entry and fixed
  MSI/I3/L9/Xanadu bodies. Invalid data rejects rather than triggers tools.
- Renderer is native 2D Godot, no GDExtension, external fonts, network
  service, third-party package, heavy model or artificial neural engine.
  The waveform is a **clearly labelled illustrative projection** derived
  from recorded text length, not a model's actual neural activations.
- Input/screenshot acceptance is separate from headless parser success.
  No human enjoyment verdict is assigned by a test runner.
- One source-reported snapshot is not a replay of the actual runtime:
  playback only moves through recorded observations.

## Colony work on the tape

The tape carries the colony's **work** as well as the Minds' thoughts, using
the shared cockpit protocol (HOLOMIND #15, `tools/holomind/cockpit_feed.py`):

| Tape kind | Source | Inspector shows |
| --- | --- | --- |
| `order` | channel line `{kind:'order', id, from, to, text, url?}` | who, to whom, order text, link |
| `order-status` | channel line `{kind:'order-status', id, from, status, note, link}`, status `taken / working / done / declined` | who, to whom (the order's poster), status, note, receipt link |
| `decision` | channel line `{kind:'decision', card, verdict}` | who, verdict, card, note |
| `rig-change` | two consecutive heartbeats of one rig whose green/red state or failing checks differ | previous -> new state, checks that began or stopped failing, gap |

Rules the collector and `FeedContract.gd` both enforce:

- Work lives in its own `work` array and its own tape lane, colour and
  filter (`COLONY WORK`, or `M`). It is never merged into `events`: a work
  line is a channel report, not a model thought and not an observer line.
- A `done` status is shown as **REPORTED** unless it carries an `https://`
  receipt link, and then as **RECEIPT LINKED (not fetched)**. The Loom never
  fetches or checks the link, so nothing is ever marked verified. On the tape
  a reported-only done is a hollow square; a linked one is filled.
- Plain chat messages, read receipts and suggestions are not work and stay
  off the tape. Lines with no time zone, author, id or a known status are
  dropped, not repaired; any link that is not plain `https://` is dropped.
- Bounded: the channel tail is at most 256 KiB / 400 lines (120 work lines
  travel over SSH), `work` is at most 60 lines with text and notes cut to
  280 characters, and the oldest work lines are dropped first if the feed
  would exceed its byte budget. Thought events are never trimmed for work.
- Rig changes are reported only between two observed heartbeats. A long gap
  is stated in the note ("previous heartbeat 35 min earlier"); it is never
  turned into an invented "went silent" event. Live xanadu keeps one
  heartbeat per rig, so the earlier heartbeat comes from the previous feed
  file (`heartbeat_last`), and earlier rig changes are carried forward.

`--from-dir` reads work from a local copy as well: `channel.jsonl` (or
`cockpit/channel.jsonl`) and an optional heartbeat history per rig
(`heartbeat_history_<rig>.jsonl` or `heartbeats/<rig>.jsonl`). The test
fixture `tests/fixtures/loom-work/` holds the 13 pinned thought events, an
order/receipt channel with deliberately malformed lines, and heartbeat
histories. `tests/fixtures/prime_mind_work_feed.json` is exactly what

```sh
python tools/prime_mind/collect_once.py --from-dir tests/fixtures/loom-work --now 2026-11-08T06:37:00Z --output tests/fixtures/prime_mind_work_feed.json
```

writes; a Python test regenerates it and fails if they differ.

## Agent export

Any agent can ask "what happened between T1 and T2?" without opening Godot:

```sh
# From the feed file the Loom already polls (no collection, no SSH):
python tools/prime_mind/collect_once.py --export-json --feed <feed.json> --since 2026-11-08T06:20:00Z --until 2026-11-08T06:31:00Z

# From a local archive copy, or (without --from-dir) one read-only SSH read:
python tools/prime_mind/collect_once.py --export-json --from-dir tests/fixtures/loom-work --now 2026-11-08T06:37:00Z | grep '"lane":"work"'
```

stdout is only the tape, one JSON object per line, oldest first; a status
line goes to stderr. Every record has `t` (UTC, `YYYY-MM-DDTHH:MM:SSZ`, so
string comparison and grep both work) and `lane`:

- `model`, `observer`, `simulated`: `{"kind":"thought", mind, model, level, focus, line, reasons}`
- `work`: `{kind, id, from, to, status, text, note, link, rig, prev_status, receipt}`,
  where `receipt` is `reported`, `linked` or empty, as in the inspector.

```json
{"t":"2026-11-08T06:28:00Z","lane":"work","kind":"order-status","id":"o-201","from":"claude-i3","to":"operator","status":"done","text":"Bring docker back on i3 and post a receipt","note":"docker restarted; daemon answers","link":"","rig":null,"prev_status":"","receipt":"reported"}
```

`--export-json` with `--output` also writes the feed file. `--feed` refuses
a file whose work lines fail the same checks as `FeedContract.gd`.

## Future composition, after judging

The central attention instrument can gain OMNISYNAPSE's bounded source
anatomy as a *separately admitted lens*, Terminal Depths' runnable game
state as a typed source, and the full colony workstation's session tabs
as owner-authenticated attachments. This must not cause a new mission
authority, second memory backend, parallel executor or privileged Godot
shell. The winning concepts can be composed under #14 after human judging.
