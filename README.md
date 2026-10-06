# GSV Godot Cockpit

A Godot visual membrane for **GSV Sublime Optimization**.

> It is not the brain. It is the cockpit.

The project presents colony-facing information such as agents, services, quests, and receipts through a Godot UI. Those views are projections of external owners; the cockpit must not silently become the canonical store for the systems it displays.

## Status

A working personal tool, not a general-purpose product: no release and no packaged
export. It was built against one workstation's colony stack. On any other machine it
still opens and every tab renders, but most panels show offline or empty states. That is
deliberate: the cockpit shows unknown/offline rather than inventing data.

## Requirements

- Godot **4.7** (pinned by `config/features` in `project.godot`), GL Compatibility renderer.
- Windows. Panels shell out to PowerShell (`pwsh`, with `powershell` as a fallback) for
  HTTP probes and file reads.
- Optional: the colony services the panels look for. There is nothing else to install.

## Start

Open the project in Godot 4.7 and run the configured main scene:

```text
res://scenes/Main.tscn
```

The window is 1280×720 and resizable. Boot paints in well under a second; the first
status probe runs after the first frames, so a slow or missing service never blocks the UI.

## What is in it

| Tab | Shows | Reads from |
|---|---|---|
| Status | service probes, proof bundle | the PowerShell bridge (`BRIDGE` in `scripts/Main.gd`) |
| Events | tail of the colony event log | a local `events.jsonl` (`EventStream.gd`) |
| Git Log | recent commits across a fixed list of repos | `git` through `pwsh` (`GitLogPanel.gd`) |
| Dispatch | task queue | dispatch service, localhost HTTP (`DispatchQueuePanel.gd`) |
| Models | local model servers | Ollama and OpenAI-compatible endpoints on localhost (`ModelStatusPanel.gd`) |
| Agents | which agent CLIs are installed | PATH checks (`AgentMap.gd`) |
| CHUG | cycle status; the **Trigger** button POSTs to the service | localhost API (`CHUGPanel.gd`) |
| Quests | cultivation reports as a quest board | report files (`QuestBoard.gd`) |
| Receipts | latest sprint and receipt files | local files (`ReceiptViewer.gd`) |
| Terminal Depths | game health and depth | localhost API (`TDStatePanel.gd`) |
| Flight, Steer, Route | supervisor heartbeat; bounded actions and smoke test; natural-language routing | bridge modes in `Main.gd` |

The cockpit's own code makes one write call, the CHUG trigger. What the bridge script does
for the `proof`, `route` and `fcc-smoke` modes belongs to that script, not to this repo.
Every location (Windows paths, localhost ports) is a `const` at the top of the panel
script that uses it, hard-coded to the author's layout. To point the cockpit somewhere
else, edit those constants.

Tabs are built on first visit. Each panel probes with blocking `pwsh` calls, and building
all thirteen up front once froze the window for about 39 seconds.

## Tests

```sh
godot --headless --audio-driver Dummy --path . --import
godot --headless --audio-driver Dummy --path . --script res://tests/cockpit_boot_test.gd
```

The first line builds the import cache and is needed on a fresh clone. The second exits 0
on pass. It asserts the first frame lands within 8 s, the tab list is exactly the thirteen
above, and every tab gains content when shown. It takes about two minutes because the
panels' probes run for real. Always run headless Godot under a hard timeout: a failed
headless boot can hang instead of exiting.

## Validate

The repository-owned GSV proof contract is `.gsv/build.yaml`.

Its source gate requires:

```text
Godot headless resource import
+
explicit GDScript parse gate
```

A headless editor process merely exiting 0 is not enough evidence of valid scripts.

## Authority

The cockpit may own:

- its scenes;
- UI state;
- presentation adapters;
- interaction affordances specific to the cockpit.

It does not own the underlying agents, services, mission truth, receipts, policy, or product state it visualizes.

Read `START_HERE.md` before extending the project, and `CONTRIBUTING.md` before opening a PR.
