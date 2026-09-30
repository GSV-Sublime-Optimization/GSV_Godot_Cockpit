# GSV_Godot_Cockpit — Local Summary

**Role:** Godot 4.7 desktop cockpit for GSV Sublime Optimization. Thirteen tabs project
colony state (services, agents, events, receipts, quests, models). Presentation only: it
owns none of the state it shows.

**Architecture:** Godot 4 GDScript UI (GL Compatibility, 2D Control nodes). One panel script
per tab in `scripts/`, registered in `scripts/Main.gd`. Panels get data by shelling out to
PowerShell and by local HTTP probes.

**Cold-start entry points:**
- README.md (what it is, requirements, tabs, tests)
- START_HERE.md, AGENTS.md, CLAUDE.md, CONTRIBUTING.md
- project.godot, scenes/Main.tscn, scripts/Main.gd

**Key paths:**
- scripts/: `Main.gd` plus one panel script per tab
- scenes/Main.tscn: the single main scene
- tests/cockpit_boot_test.gd: boot budget and tab-wiring check

**Critical gotchas:**
- Windows only (`pwsh` calls); data locations are hard-coded `const`s in each panel script.
- The tab list in the test must match `Main.gd`.
- Run headless with `--audio-driver Dummy` and a hard timeout.

**Last verified:** 2026-09-30
