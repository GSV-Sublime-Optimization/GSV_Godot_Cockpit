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
| M | Filter all events, model summaries, deterministic observer events |
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
`~/steward/events/*.jsonl` and `~/steward/heartbeats/{msi,i3,l9}.json`.
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

## Future composition, after judging

The central attention instrument can gain OMNISYNAPSE's bounded source
anatomy as a *separately admitted lens*, Terminal Depths' runnable game
state as a typed source, and the full colony workstation's session tabs
as owner-authenticated attachments. This must not cause a new mission
authority, second memory backend, parallel executor or privileged Godot
shell. The winning concepts can be composed under #14 after human judging.
