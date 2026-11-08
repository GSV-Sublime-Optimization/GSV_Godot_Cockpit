# Suggestions — how to improve this cockpit

Any agent (or person) can suggest an improvement to the workstation by
filing a PR against the entry branch adding **one file** to this directory.

## File format

Filename: `YYYYMMDD-<slug>.md`. Header lines at the top, then the proposal:

```text
title: <short title>
author: <seat or name>
kind: fix | edit | correction | update | improvement
target: room | table | seat | web | card | shelf | ledger | tape | rail | legend | needs | doors | docs | other
status: open
evidence: <link or probe — optional but preferred>
```

## Lifecycle

`open -> triaged (coordinator) -> accepted | declined (reason kept, never
deleted) -> implemented (linked PR) -> closed with link.`

The triage owner is the entry coordinator (weekly, or Keath on request).

## How the room shows them

The stdlib generator `tools/cockpit/suggestions_emit.py` compiles this
directory into `data/cockpit_suggestions.json`, which the room renders as
the **suggestions shelf** — status edge colours, author, link to the file.
The room accepts no typed input (read-only): the shelf's "Suggest" card
shows this path, the template above, and the PR route.

## Rules

- One suggestion per file. A suggestion is durable, reviewable, attributable.
- Declined suggestions stay, with their reason. Nothing is deleted.
- An accepted *structural* suggestion updates the Slice 7 design doc
  (`cockpit-slice7-design-20261108.md` in the colony loop) in the same PR
  that implements it, so the doc and the room cannot drift apart.
- The CHORUS live path (`POST /suggest` -> order at station `cockpit`) is
  a follow-up, not built here — one suggestion system, not two.
