# VERIFICATION — queued, NOT yet run

Furyline Phase B holds the single Godot flight slot + the 2,500 MB RAM gate
at the time this PR was filed, so **no Godot run was performed for this PR,
on any machine**. The commands below are the queued verification, in order.
Run them on the MSI in `C:\dev\work\mindview-muse` once the slot is free.
Record the results here (append a dated run log) — do not claim them before
they exist.

## 0. Preconditions

- Godot 4.7.1 on the MSI; the Phase B slot released.
- Branch `bakeoff/mindview-muse`, head as filed (see the PR).
- Work in `C:\dev\work\mindview-muse` (never `C:\dev\active\*`).

## 1. Headless import (proves the project imports clean)

```cmd
godot --headless --path C:\dev\work\mindview-muse --import --quit
```

Expect: exit 0, no script errors. Record the full log.

## 2. Tests (the #8 pattern — SceneTree scripts, exit 0 = pass)

```cmd
godot --headless --path C:\dev\work\mindview-muse --script res://tests/ledger_feed_test.gd
godot --headless --path C:\dev\work\mindview-muse --script res://tests/ledger_scene_test.gd
godot --headless --path C:\dev\work\mindview-muse --script res://tests/ledger_render_test.gd
```

Expect, in order: `LEDGER_FEED_PASS`, `LEDGER_SCENE_PASS`,
`LEDGER_HEADLESS_DRAW_PASS`. Any `LEDGER_*_FAIL` line fails the run.

## 3. Real render receipt — `--shot` PNG at 1600×900

```cmd
godot --path C:\dev\work\mindview-muse res://scenes/LedgerView.tscn -- --shot=C:\dev\scratch\ledger-1600x900.png
```

Expect: `LEDGER_SHOT_PASS: C:\dev\scratch\ledger-1600x900.png`, exit 0.
Then a human looks at the PNG and confirms: header inside the frame, no
overlapping labels, river towers legible, latest-thought card readable at a
glance, footer present. File the PNG as the render receipt (it replaces the
mockup as the entry's visual evidence; the mockup stays labelled as a
mockup).

## 4. RAM / CPU measurement (same run as §3)

While the `--shot` run is up (or a plain interactive run at 1600×900),
record from Task Manager / Performance Monitor: working-set RAM and CPU %
at rest (focused) and after 60 s. The entry's budget claim is "cheap":
30 fps focused / 10 fps backgrounded, one `Control`, custom `_draw()`.
Record the numbers; do not assert a budget that was not measured.

## 5. Exit discipline (interactive, 2 minutes)

- Launch windowed; confirm it opens windowed, not fullscreen, not topmost.
- Press Esc → closes immediately.
- Relaunch; press F11 → fullscreen; press F11 → windowed; press Esc → closes.
- Relaunch with a missing feed (`--feed=C:\dev\scratch\no-such-dir`);
  confirm the error state draws and Esc still closes.

## 6. What is already verified (this PR)

- `gdparse` green on all five `.gd` files (gdtoolkit 4.5.0, VM, 2026-11-08).
- Shared fixture byte-identical between the #15 and #16 branches (`fc`,
  2026-11-08) — the entry reads the same files both entries were measured
  against.
- Mockup drawn from the real fixture text (PIL, 1600×900), labelled
  `MOCKUP — NOT A RENDER` in the image.

## Run log

(None yet — append dated results here.)
