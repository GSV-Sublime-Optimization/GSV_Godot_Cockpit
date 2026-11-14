# Mind View, slice 0

What the colony's Minds see and think, made visible. Observation only: it reads one local feed file and changes nothing.

- `scenes/MindView.tscn` / `scripts/mindview/MindView.gd`: the view.
  - The **fleet map**: rigs coloured by heartbeat, packets flowing to xanadu while a rig reports, and an attention ring on whatever the latest thought is about.
  - The **latest thought**, large.
  - The **transcript**: time, Mind, model, level, line, reasons.
  - A header that always says "observation only, 0 actuators" and how old the feed is.
- `tools/mindview/mind_feed.py`: the feeder (Python stdlib, runs on the i3). Every 15 s, one SSH call to xanadu gathers the Minds' events (`~/steward/events/*.jsonl`, written by the L9 triage drone and future Minds) and every heartbeat (`~/steward/heartbeats/*.json`). It adds this rig's GameAttract state, and writes `C:\Users\Public\colony\mindview\feed.json` (`colony.mindview-feed/v0`). State *changes* become observer lines labelled `mind=observer, model=null`, so a deterministic line never pretends to be a model thinking.

Run: start `mind_feed.py`, then `godot --path . --fullscreen res://scenes/MindView.tscn` (or `-- --feed=<path>`).

Next slices (start small, go big):
- the Mind's own glyph moving between bodies as its attention shifts;
- click a body for its full heartbeat;
- a timeline scrubber;
- a slot in the i3's idle rotation;
- the same feed rendered inside OMNISYNAPSE, Terminal Depths (agents as NPCs) and the games;
- Cockpit #8's Studio observation as another sense.
