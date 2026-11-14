r"""bridge: carry dispatcher orders to the cloud seats on GitHub, where they actually work, and bring receipts back.

GPT-6, Codex and Muse never read the shared channel, but they do work on PRs. So when `dispatch.py assign --bridge`
gives one of them an order, it also posts ONE short comment on that PR: the agent by name (plain text, no mention),
the order id, the exact command, and how the order closes. Posted orders are recorded in a local state file and
never posted twice (nor twice for the same PR, head and kind under a new order id).

`reconcile` closes bridged orders from GitHub's own record:
  review     -> a gsv review marker at the PR's CURRENT head from an actor other than the author: done, from the
                seat that reviewed, with the review's link (the feeder then shows it verified);
  provenance -> the merge gate's provenance check passes: done;
  fix        -> the PR's head moved past the one the order named: done (the new head goes back to review);
  any        -> the PR is no longer open: declined, by the dispatcher.
It also closes the dispatcher's channel-only prerequisite orders (verify, provenance, ready) once the gate shows
them satisfied, and withdraws dispatcher orders to cloud seats that sat untaken and unbridged past EXPIRE_H hours
(those seats can't see them; the items return to the queue and go out through the bridge instead).
"""
import datetime as dt
import json

import gates

EXPIRE_H = 6
GSV_HINT = '`gsv.py` lives in GSV-Sublime-Optimization/dev at `tools/gsv/gsv.py`'


class BridgeRefused(RuntimeError):
    """gh refused to post (permission, auth, rate limit): stop the run and report, don't retry blindly."""


def iso(t):
    return t.strftime('%Y-%m-%dT%H:%M:%SZ')


def parse_at(s):
    try:
        return dt.datetime.fromisoformat(str(s).replace('Z', '+00:00'))
    except ValueError:
        return None


def comment_body(order, seat, agent, kind, repo, number, head, gate_name=''):
    """The one PR comment for a bridged order. No @mentions; never a gsv review marker (the feeder must not count it)."""
    actor = gates.CLOUD_ACTORS.get(seat, '<your actor>')
    sha12 = head[:12]
    lead = f"**GSV colony dispatcher** · order `{order}` for **{agent}** (seat `{seat}`, actor `{actor}`)."
    if kind == 'review':
        body = [lead, '',
                f"This PR passes every mechanical merge gate (ready, gsv verify, provenance) except a second review. "
                f"Please review head `{head}` and record your verdict:", '',
                '```',
                f"python tools/gsv/gsv.py review post {repo}#{number} --as {actor} --verdict approve|request-changes --head {head} --body-file review.md",
                '```',
                f"({GSV_HINT}.) The order closes automatically when a gsv review marker at head `{sha12}` from an actor "
                f"other than the author appears on this PR; no channel reply needed."]
    elif kind == 'provenance':
        body = [lead, '',
                f"The merge gate refuses this PR because its description has no `KILOCORE-PROVENANCE-V1` block, so it gets no "
                f"reviewer until it has one. Add the block (engineering actor `{actor}`; format in dev's "
                f"`docs/colony/AGENT_HANDSHAKE.md` and Kilo_Core's `validate_pr_provenance.py`).", '',
                f"The order closes automatically when `python tools/gsv/gsv.py merge {repo}#{number} --dry-run` shows provenance ok "
                f"({GSV_HINT})."]
    else:   # fix, gsv-red, ready, retarget: the author's own next step
        what = {'fix': 'A reviewer requested changes', 'gsv-red': 'gsv verify is red',
                'ready': 'This PR is still a draft', 'retarget': 'This PR is stacked on a branch with no open PR'}.get(gate_name or kind, 'This PR needs its author')
        body = [lead, '',
                f"{what} at head `{sha12}`. Please address it on this branch.", '',
                f"The order closes automatically when the PR's head moves past `{sha12}`; it then returns to review."]
    return '\n'.join(body)


def post_comment(runner, repo, number, body):
    rc, out, err = runner(['gh', 'pr', 'comment', str(number), '-R', repo, '--body', body])
    if rc != 0:
        raise BridgeRefused(f'gh pr comment {repo}#{number} refused (rc={rc}): {(err or out).strip()[-300:]}')
    url = next((w for w in (out or '').split() if w.startswith('https://')), '')
    return url


def bridge_order(state, line, seat, agent, kind, repo, number, head, runner, gate_name='', log=print):
    """Post the comment for one order unless already done. Returns the comment url ('' if none was needed)."""
    bridged = state.setdefault('bridged', {})
    if line['id'] in bridged:
        return bridged[line['id']].get('comment', '')
    pr_key = f'{repo}#{number}@{head}:{gate_name or kind}:{seat}'
    prior = next((b for b in bridged.values() if b.get('pr_key') == pr_key and b.get('comment')), None)
    rec = {'pr_key': pr_key, 'seat': seat, 'kind': kind, 'gate': gate_name, 'repo': repo, 'number': number, 'head': head,
           'author_actor': line.get('author_actor'), 'at': line['at'], 'comment': ''}
    if prior:
        rec['comment'] = prior['comment']
        rec['reused'] = True
        bridged[line['id']] = rec
        log(f"  bridge: {line['id']} reuses the comment already on {repo}#{number}: {prior['comment']}")
        return prior['comment']
    rec['state'] = 'posting'       # recorded BEFORE posting: a crash between the two can never cause a second post
    bridged[line['id']] = rec
    state['_dirty'] = True
    try:
        url = post_comment(runner, repo, number, comment_body(line['id'], seat, agent, kind, repo, number, head, gate_name))
    except BridgeRefused:
        del bridged[line['id']]    # nothing was posted
        raise
    rec.update(state='posted', comment=url)
    log(f"  bridge: posted {line['id']} for {agent} on {repo}#{number}: {url}")
    return url


def pr_view(runner, repo, number):
    rc, out, _ = runner(['gh', 'pr', 'view', str(number), '-R', repo, '--json', 'state,headRefOid,url,comments'])
    try:
        return json.loads(out) if rc == 0 else None
    except ValueError:
        return None


def reconcile(lines, state, runner, now, fold, seats, gate_fn=None, log=print):
    """Status lines to append (the caller appends them). `fold` folds channel lines into orders (fold_orders)."""
    orders = {o['id']: o for o in fold(lines)}
    out = []

    def close(oid, status, who, note, link=''):
        line = {'at': iso(now), 'from': who, 'kind': 'order-status', 'id': oid, 'status': status, 'note': note, 'link': link, 'via': 'reconcile'}
        out.append(line)
        log(f"  reconcile: {oid} {status} by {who}: {note} {link}".rstrip())

    bridged = state.get('bridged', {})
    for oid, b in bridged.items():
        o = orders.get(oid)
        if not o or o['status'] in ('done', 'declined') or b.get('state') == 'posting':
            continue
        v = pr_view(runner, b['repo'], b['number'])
        if v is None:
            continue
        if v.get('state') != 'OPEN':
            close(oid, 'declined', 'dispatcher', f"PR is {str(v.get('state')).lower()}: nothing left to do")
            continue
        head = v.get('headRefOid', '')
        if b['kind'] == 'review':
            revs = gates.reviews_at(v.get('comments'), head, exclude_actor=b.get('author_actor'))
            if revs:
                r = revs[-1]
                close(oid, 'done', gates.ACTOR_SEAT.get(r['actor'], r['actor']), f"{r['verdict']} at {head[:12]} by {r['actor']} (from GitHub)", r['url'])
        elif b['kind'] == 'provenance' and gate_fn:
            g = gate_fn(b['repo'], b['number'])
            if (g.get('checks') or {}).get('provenance', {}).get('ok'):
                close(oid, 'done', b['seat'], 'provenance block present (merge gate)', v.get('url', ''))
        elif head and head != b['head']:
            close(oid, 'done', b['seat'], f"pushed {head[:12]} (was {b['head'][:12]})")
    # Channel-only prerequisites the dispatcher issued: satisfied when the gate says so.
    if gate_fn:
        check_of = {'verify': 'gsv', 'provenance': 'provenance', 'ready': 'pr', 'retarget': 'pr'}
        for o in orders.values():
            ref = str(o.get('ref') or '')
            if o['id'] in bridged or o['status'] in ('done', 'declined') or o.get('from') != 'dispatcher' or not ref.startswith('prereq:'):
                continue
            _, name, rest = ref.split(':', 2)
            prref = rest.rsplit('@', 1)[0]
            repo, _, num = prref.rpartition('#')
            g = gate_fn(repo, num)
            chk = (g.get('checks') or {}).get(check_of.get(name, ''), {})
            if chk.get('ok'):
                close(o['id'], 'done', 'dispatcher', f"{name} satisfied: {chk.get('detail', '')[:90]} (merge gate)")
    # Dispatcher orders to cloud seats that nobody can see: withdraw, so the item can go out through the bridge.
    for o in orders.values():
        t = parse_at(o.get('at'))
        if (o.get('from') == 'dispatcher' and o['to'] in seats and o['status'] == 'posted' and o['id'] not in bridged
                and t and (now - t).total_seconds() > EXPIRE_H * 3600):
            close(o['id'], 'declined', 'dispatcher',
                  f"withdrawn after {int((now - t).total_seconds() // 3600)} h untaken: {o['to']} does not read the channel; re-queued for the GitHub bridge")
    return out
