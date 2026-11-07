# GSV Cockpit offline acceptance and portable read-only panels

Run the repository-owned strict verification gate after Godot import:

```sh
godot --headless --audio-driver Dummy --path . --import
python tests/godot_smoke_gate.py --godot godot --project . --receipt cockpit-smoke.json
python -m unittest discover -s tests -p 'test_godot_smoke_gate.py'
```

The gate requires error-free resource import, the existing 13-tab boot test,
and a portable fixture test to pass.
It rejects script/engine error diagnostics even when Godot exits zero and the
boot test prints PASS. The final test PASS marker must occupy its own line:
an intermediate per-assertion PASS cannot mask a missing final verdict.
It launches with Dummy audio and kills only its spawned process tree on timeout.
The GSV manifest now requires **Godot 4.7** and passes the same resolved binary
through resource import, GDScript parse and strict smoke. On the MSI, set
`GODOT_EXE` to the full path of the approved 4.7.x console executable before
running `gsv verify`. A legacy local shim named `godot4.7.cmd` was observed
pointing to 4.6.2; the 4.7 manifest pin prevents this from receiving a green
version-mismatched receipt. Do not alter an occupied/shared shim mid-playtest.
Missing or unreadable quest/receipt sources say *unavailable*, while a readable
source with zero entries says *empty*. The portable fixture tests both states.
The optional JSON receipt is local evidence; it is not a canonical colony witness.

Read-only path overrides for the Quests and Receipts panels:

| Variable | Purpose |
| --- | --- |
| GSV_KILOCORE_REPORTS_DIR | Cultivation report directory |
| GSV_SPRINTS_DIR | Sprint directory with index.json |
| GSV_SPRINT_CURRENT_DIR | Sprint receipts directory |
| GSV_SPRINT_INDEX | Path to latest.json; otherwise derived from sprint current dir |

On Windows, unset variables preserve workstation defaults. On other platforms,
unset paths render explicit unavailable states rather than pretending that
missing sources contain no records. Quests render both .md and .txt reports;
Receipts can read JSONL files from the configured directory.
Dispatch and Models use curl for read-only HTTP probes outside Windows.

Acceptance evidence on the recovered Sprite (Godot 4.3):
- Original unpatched boot test printed PASS while Godot logged JSON parsing and
  missing-directory ERROR diagnostics.
- Patched strict smoke gate: 3/3 phases PASS (import, boot, fixture), zero engine errors.
- Negative-control unit tests: 5/5 PASS, including import-error false-green.
- Also verified with the declared Godot 4.7-stable release: SHA512 checked
  against the official release manifest, import exit 0 with no engine errors,
  strict smoke gate 2/2 PASS with zero engine errors. Ubuntu Sprite runtime
  dependencies were extracted into a user-local overlay; no system changes.
- A November 7, 2026 MSI rerun of the hardened gate proved boot and
  portable fixture phases PASS on both Godot 4.7.1 and 4.7.2 (exit 0,
  zero engine errors), but **not** the overall import gate: 4.7.1 import
  exited 3221225477 (Windows access violation); 4.7.2 import exited 0
  but emitted `ERROR: Parameter "singleton" is null.` The strict gate
  correctly marked both runs FAIL. These are observed import failures, not
  proven to be caused by these code changes.
- The same November 7 MSI run was then repeated using Godot 4.7.2 and a
  warmed project cache: all three strict phases PASS, zero engine diagnostics.
  A **separate fresh detached worktree** at source head `72ebec0` also
  completed its **first** Godot 4.7.2 import with exit 0 and zero engine
  diagnostics. Earlier failures remain recorded because one successful cold
  run does not establish reliability across all machines or concurrent loads.
- Promotion still requires an exact-head full GSV proof with the corrected
  4.7.x manifest/toolchain mapping and fresh independent review. A dry-run
  receipt only proves command planning, never actual test execution.
- Live PowerShell bridge paths remain unverified and need a scoped check.
