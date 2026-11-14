# mindview_ledger — The Ledger feed reader

`LedgerFeed.gd` reads the **shared fixture directory directly** (never a
copy) and normalises it to schema `colony.mindview-feed/v0` so Mind View
entries stay comparable:

```
tests/fixtures/mindview-20261108/
  events.jsonl          one event per line (4 in the frozen fixture)
  heartbeat_msi.json    colony.heartbeat/v1
  heartbeat_i3.json     colony.heartbeat/v1
  heartbeat_l9.json     colony.heartbeat/v1
  (no heartbeat_xanadu.json — absence is recorded, never faked)
```

## What it proves (see `tests/ledger_feed_test.gd`)

- 4 events, 1 mind (`l9-triage-drone`), 1 model (`qwen3:4b-l9fast`),
  0 routine — the calm state never occurs in the fixture.
- Headline recurrence: **"i3 failing: docker" — 4× in 61 min**
  (`recurrence_rows()`).
- Heartbeats: MSI green, i3 green:false (docker FAIL), L9 green via
  observer msi; xanadu missing.
- Disk pressure: MSI C: 8.5% free, i3 C: 9.5% free.
- `needs_you_items()` derives "What needs you" from fixture data only;
  the Mind's "backups 109 h old" claim is carried as `UNVERIFIED CLAIM`
  because no backup record exists in the fixture.
- `outcome_rows()` ages the 05:35 alarm against the 06:45 MSI green
  heartbeat (AGED) and leaves i3 docker UNRESOLVED at 06:46.
- `unexercised_states()` lists what the fixture never shows, never fakes.

## Rules

- Fail-closed: one bad line rejects the file; unknown levels, rigs, or
  schemas are rejected; oversize input is rejected before parsing.
- Observation only: local file reads. No HTTP, no shell, no writes, no
  tasks, no containers. **Zero actuators.**
- Pure `RefCounted` statics — testable without a scene or a Godot run
  beyond the test scripts themselves.
