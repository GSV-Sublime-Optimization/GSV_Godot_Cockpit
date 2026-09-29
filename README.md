# GSV Godot Cockpit

A Godot visual membrane for **GSV Sublime Optimization**.

> It is not the brain. It is the cockpit.

The project presents colony-facing information such as agents, services, quests, and receipts through a Godot UI. Those views are projections of external owners; the cockpit must not silently become the canonical store for the systems it displays.

## Start

Open the project with a compatible Godot 4 editor and run the configured main scene:

```text
res://scenes/Main.tscn
```

The current project targets GL Compatibility and a 1280×720 resizable viewport.

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

Read `START_HERE.md` before extending the project.
