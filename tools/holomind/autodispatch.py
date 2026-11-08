r"""autodispatch: one unattended pass of the colony dispatcher, safe to run every 30 minutes.

    python autodispatch.py [--max 3] [--no-bridge] [--dry-run]

1. `dispatch.py reconcile`: close bridged orders GitHub shows done (a review at the PR's current head from another
   actor), close prerequisites the merge gate now shows satisfied, withdraw cloud orders nobody could see.
2. `dispatch.py assign --max 3 --bridge`: gates before judgement, then one order per free seat; orders to cloud seats
   get ONE PR comment.
Re-running is harmless: a seat with an open order gets nothing new, a bridged order is never posted twice (state in
C:\Users\Public\colony\mindview\dispatch.state.json), and Keath-only items (decisions, merges, triage, anything that
needs hands on a machine) are never given to an agent. A lock file stops two passes overlapping.
--dry-run runs reconcile read-only and prints the plan instead of assigning.

Scheduled by autodispatch.cmd (see that file for the schtasks line). Log: autodispatch.log next to the state file.
"""
import argparse
import datetime as dt
import os
import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import bridge  # noqa: E402
import dispatch  # noqa: E402

LOCK_STALE_S = 25 * 60


def acquire(lock):
    try:
        fd = os.open(str(lock), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        if time.time() - lock.stat().st_mtime < LOCK_STALE_S:
            return False
        lock.unlink(missing_ok=True)
        fd = os.open(str(lock), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    os.write(fd, str(os.getpid()).encode())
    os.close(fd)
    return True


def run(argv=None, out=print, **io):
    a = argparse.ArgumentParser(description='One unattended dispatcher pass: reconcile, then assign with the GitHub bridge.')
    a.add_argument('--max', type=int, default=3)
    a.add_argument('--no-bridge', action='store_true')
    a.add_argument('--dry-run', action='store_true', help='reconcile without appending, and plan instead of assign')
    args = a.parse_args(argv)
    state_path = pathlib.Path(io.get('state_path') or dispatch.STATE)
    lock = state_path.with_suffix('.lock')
    state_path.parent.mkdir(parents=True, exist_ok=True)
    if not acquire(lock):
        out('autodispatch: another pass is running; skipped')
        return {'skipped': True}
    try:
        out(f"autodispatch {dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}")
        rio = dict(io)
        if args.dry_run:
            rio['append_fn'] = lambda line: out(f"  (dry run, not appended) {line.get('id')} {line.get('status')}")
        closed = dispatch.run(['reconcile'], out=out, **rio)
        if args.dry_run:
            # The plan must see the reconcile as if it had happened, or withdrawn seats would still look busy.
            lines = (io.get('lines_fn') or dispatch.cockpit.all_lines)() + list(closed)
            plan = dispatch.run(['plan', '--max', str(args.max)], out=out, **dict(io, lines_fn=lambda: lines))
            return {'closed': closed, 'plan': plan}
        cmd = ['assign', '--max', str(args.max)] + ([] if args.no_bridge else ['--bridge'])
        try:
            posted = dispatch.run(cmd, out=out, **io)
        except bridge.BridgeRefused as exc:
            out(f'autodispatch: STOPPED, GitHub refused the bridge comment: {exc}')
            return {'closed': closed, 'refused': str(exc)}
        return {'closed': closed, 'posted': posted}
    finally:
        lock.unlink(missing_ok=True)


if __name__ == '__main__':
    r = run()
    sys.exit(2 if r.get('refused') else 0)
