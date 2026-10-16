# GSV Cockpit offline acceptance and portable read-only panels

Run the repository-owned strict verification gate after Godot import:

```sh
godot --headless --path . --import
python tests/godot_smoke_gate.py --godot godot --project . --receipt cockpit-smoke.json
python -m unittest discover -s tests -p 'test_godot_smoke_gate.py'
```

The gate requires the existing 13-tab boot test and a portable fixture test to pass.
It rejects script/engine error diagnostics even when Godot exits zero and the
boot test prints PASS. The optional JSON receipt is local evidence; it is not
a canonical colony witness.

Read-only path overrides for the Quests and Receipts panels:

| Variable | Purpose |
| --- | --- |
| GSV_KILOCORE_REPORTS_DIR | Cultivation report directory |
| GSV_SPRINTS_DIR | Sprint directory with index.json |
| GSV_SPRINT_CURRENT_DIR | Sprint receipts directory |
| GSV_SPRINT_INDEX | Path to latest.json; otherwise derived from sprint current dir |

On Windows, unset variables preserve workstation defaults. On other platforms,
unset paths result in honest empty states. Quests render both .md and .txt
reports, and Receipts can read JSONL files from the configured directory.
Dispatch and Models use curl for read-only HTTP probes outside Windows.

Acceptance evidence on the recovered Sprite (Godot 4.3):
- Original unpatched boot test printed PASS while Godot logged JSON parsing and
  missing-directory ERROR diagnostics.
- Patched strict smoke gate: 2/2 headless suites PASS, zero engine errors.
- Negative-control unit tests: 4/4 PASS.
- Target application declares Godot 4.7, so release validation must also
  execute on the declared 4.7 toolchain before production merge.
