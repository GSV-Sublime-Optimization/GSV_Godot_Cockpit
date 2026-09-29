# AGENTS.md — GSV Godot Cockpit

Read `START_HERE.md` first.

## Mission

Keep the Godot cockpit a useful **visual membrane**, not a shadow control plane.

## Rules

- scenes and presentation logic may project external facts;
- preserve provenance/evidence quality on displayed facts;
- unknown/offline/stale must remain distinguishable;
- do not hard-code sibling paths or duplicate backend policy;
- gameplay/UI convenience does not grant mutation authority;
- new GDScript must clear the explicit parse gate;
- visual claims require a real Godot run, not only headless parsing.

## Before editing

Name:

1. the UI surface;
2. the external owner of any displayed state;
3. the adapter/projection boundary;
4. the narrow parse/import test;
5. whether a real visual/input smoke is required.

## Verification

Run the commands represented by `.gsv/build.yaml`, then a real player/editor smoke for changes whose correctness is visual or interactive.
