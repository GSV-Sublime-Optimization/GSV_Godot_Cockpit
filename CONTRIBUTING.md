# Contributing to GSV Godot Cockpit

The cockpit is a visual membrane over GSV Sublime Optimization: it projects state owned by
other systems and must not become the owner of that state. Read `README.md` (what it is),
`START_HERE.md` and `AGENTS.md` (the ownership rules) first.

## Setup

1. Install **Godot 4.7** (the version pinned in `project.godot`) on Windows.
2. Clone, then build the import cache once:
   `godot --headless --audio-driver Dummy --path . --import`
3. Open the project in the editor, or run `res://scenes/Main.tscn`.

Most panels need local colony services to show live data. Without them they show offline
states, which is expected. You can develop layout and wiring with nothing running.

## Test before you push

```sh
godot --headless --audio-driver Dummy --path . --script res://tests/cockpit_boot_test.gd
```

Exit 0 means PASS (about two minutes). Use a hard timeout: a failed headless boot can
hang. If you changed layout, input or rendering, also run the project in a real window;
a headless run cannot prove those.

## Adding or changing a panel

1. Put the panel in `scripts/<Name>.gd` and register it in `Main.gd` with
   `_add_tab("Title", _panel_filler("res://scripts/<Name>.gd"))`.
2. Update `EXPECTED_TABS` in `tests/cockpit_boot_test.gd`. The test fails if the two differ.
3. Keep probes out of `_ready()`/`_build_ui()`. Tabs build on first visit for a reason
   (see `CLAUDE.md`).
4. Show source, freshness and unknown/offline honestly. Never draw a healthy-looking
   default when a probe failed.
5. Commit the `.gd.uid` file Godot generates next to the script.

## Rules for this public repo

- No secrets, tokens, private hostnames or new hard-coded workstation paths in code, docs
  or commit messages. Put locations in a `const` at the top of the script.
- No new write or mutation call without an issue first.
- GDScript is Godot 4 syntax only.

## Branches, commits, pull requests

- Branch from `master`: `feat/<topic>`, `fix/<topic>` or `docs/<topic>`.
- Commit messages follow the existing history: `feat(cockpit): ...`, `fix(godot4): ...`,
  `perf(cockpit): ...`, `docs: ...`. Explain the cause, not only the change.
- Open a PR against `master`. Say what you ran (the test command and its exit code) and,
  for visual changes, what you saw in a real window.

## Done means

The boot test passes, the tab list and test agree, new scripts have their `.uid` files, no
new local paths or secrets were added, and the PR states what was and was not verified.
