# Start Here — GSV Godot Cockpit

This repository is **cockpit #2**, a Godot presentation membrane over GSV Sublime Optimization.

## Read first

1. `.gsv/project.yaml`
2. `README.md`
3. `.gsv/build.yaml`
4. `project.godot`
5. the scene/script being changed

## Ownership rule

Presentation may consume external state. Presentation must not quietly become the owner of external state.

If a screen displays:

- an agent;
- a service;
- a quest/mission;
- a receipt;
- fleet/runtime state;

identify the source contract and preserve unknown/stale/offline states rather than hard-coding a prettier fiction.

## Verify

Use the GSV build contract:

```text
Godot resource import
GDScript parse gate
```

Run a real editor/player interaction before claiming layout, input, rendering, or animation behavior.

## Cross-lattice rule

Prefer typed/projected data from the owning system. Do not read sibling source trees directly merely because they are nearby on the same workstation.
