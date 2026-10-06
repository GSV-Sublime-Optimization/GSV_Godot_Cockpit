# CLAUDE.md — GSV Godot Cockpit

Claude Code loads this file, not `AGENTS.md`, so the shared rules are imported:

@AGENTS.md
@START_HERE.md

Below is only what those files do not say. The commands were run on 2026-09-30
with Godot 4.7.1 (headless, dummy audio, hard timeout). This repo is **public**.

## Commands

```sh
godot --headless --audio-driver Dummy --path . --import                                   # once per fresh clone or worktree
godot --headless --audio-driver Dummy --path . --script res://tests/cockpit_boot_test.gd  # exit 0 = PASS, ~2 min
```

- Both flags are required together: `--headless` alone still opens an audio device on
  some machines. Wrap every run in a hard timeout, because a failed headless boot can hang
  instead of exiting.
- Without the `--import` step a fresh checkout has no import cache and the test cannot
  load the scene.
- `.gsv/build.yaml` adds a GDScript parse gate (`godot_parse_gate.py`) that lives in the
  colony's own tooling, not in this repo. Godot exiting 0 does not prove the scripts parse.

## Things that bite

- **The test is a contract on the tab list.** `EXPECTED_TABS` in
  `tests/cockpit_boot_test.gd` must match the `_add_tab(...)` calls in `Main.gd` exactly,
  in order. Adding, renaming or reordering a tab means editing both.
- **Never do blocking work in `_ready()` or `_build_ui()`.** Panels probe with
  `OS.execute("pwsh", ...)`, which blocks the main thread. Register the panel with
  `_panel_filler(...)` so it is built on first visit, and keep probes out of boot
  (commit 25f5ea6 cut first paint from 39 s to under a second).
- **Godot 4 only.** Past breakage from a half-finished 3-to-4 port: `use_bbcode` is now
  `bbcode_enabled`, and `var x := max(...)` infers Variant, which this project treats as
  an error; use `maxi()`/`mini()` (commit 1f60756).
- **Commit `.gd.uid` files** next to every new script; they are tracked. Do not commit
  `.godot/` (only `.godot/.gdignore` is tracked).
- **Header comment in `Main.gd` lists 7 panels; there are 13 tabs.** The tab list in the
  README and the test are current; the comment is stale.
- **Windows-only by construction** (`pwsh` calls, `C:/` paths). Do not "fix" that in an
  unrelated change.
- **Public repo:** do not add local paths, hostnames, tokens or private service names to
  code, docs or commit messages. The panels already hard-code some workstation paths;
  new code should read from a constant you can override, not add more.
- **CHUG's Trigger button is the only write call.** Do not add another without asking;
  the cockpit is a membrane, not a control plane (see `AGENTS.md`).
