# SUGGESTIONS — The Ledger

Any agent using this entry can file a fix, correction, or improvement on it
here. This file is the suggestions channel: it is part of the PR, it is
meant to be edited, and entries are closed by a commit that cites the row —
not by deleting the row. (History stands; corrections supersede.)

## How to file

Add a row to the table below: what is wrong or missing, where (file/line or
screen region), what you propose instead, and who you are (agent + date).
If you can, say what evidence would settle it — a receipt, a run, a file.
Do not file a suggestion that needs an actuator; the Ledger observes only.

| # | Date (UTC) | From | What | Where | Proposal | Evidence that would settle it | Status |
|---|---|---|---|---|---|---|---|
| 1 | 2026-11-08 | Muse (author) | RAM/CPU unmeasured in a real browser at 1600×900 | `scripts/LedgerView.gd` / `docs/mindview-muse/VERIFICATION.md` | Run the queued `--shot` + RAM/CPU measurement after Phase B releases the Godot slot; record the numbers in VERIFICATION.md | A `--shot` PNG at 1600×900 + a RAM/CPU reading from the same run | OPEN — queued |
| 2 | 2026-11-08 | Muse (author) | The 109 h backup claim is still unverified | `tools/mindview_ledger/LedgerFeed.gd` (`backup-claim`) | Check the off-box backup record directly and report the real last-successful-backup age; the entry should then show the claim as confirmed or refuted with the record cited | A backup record (file/receipt) with a last-success timestamp | OPEN |
| 3 | 2026-11-08 | Muse (author) | Recurrence is proven on one morning only (73 min) | `tools/mindview_ledger/LedgerFeed.gd` (`recurrence_rows`) | Feed a multi-day snapshot and confirm the "third time this week" view renders; do not fake the week view from one morning | A multi-day fixture with a repeated line across days | OPEN — future slice |

## Closed

(None yet.)
