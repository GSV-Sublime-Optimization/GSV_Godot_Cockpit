r"""The i3 Mind's judgement: what to answer, what to queue, what to route, and what it may claim.

cockpit_feed.py owns the I/O (xanadu SSH, Ollama, the feed file). This module is pure so it can be tested:
  - addressed():     is this channel line for the Mind? Broadcasts to 'all' that ask nothing are news, not questions.
  - classify():      'question', 'order' (something to DO, which a read-only chat model cannot), or None.
  - plan():          one tick's decisions: queue while busy, one acknowledgement per question id, answers when free,
                     one routing reply per order id, all under a rate limit.
  - build_context(): the facts the model may use, each tagged with the feed field it came from.
  - check_reply():   the post-check. A reply that claims merged/fixed/done/deployed must be supported by the facts;
                     otherwise it is replaced by the measured fact or by a single 'unknown'.
Nothing here performs I/O.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import re

MIND = 'i3-mind'
MIND_NAMES = ('mind', 'i3-mind', 'i3 mind', 'engine room mind')
QUEUE_MAX_AGE_S = 6 * 3600        # a queued question older than this is dropped (logged), not answered stale
MIN_GAP_S = 30                    # at most one Mind line every 30 s ...
WINDOW_S, WINDOW_MAX = 600, 6     # ... and at most 6 in any 10 minutes
MAX_ATTEMPTS = 3                  # model failures before the Mind says once that it cannot answer

QUESTION = re.compile(r'\?|^\s*(who|what|which|why|when|where|how|is|are|can|could|does|do|did|should|will|has|have)\b', re.I)
IMPERATIVE = re.compile(r'^\s*(please\s+)?(review|run|restart|start|stop|kill|merge|close|reopen|deploy|install|fix|patch|'
                        r'push|commit|rebase|reboot|delete|remove|clean|prune|update|upgrade|open|post|file|investigate|'
                        r'check out|take|do|make|build|test)\b', re.I)
CLAIM = re.compile(r'\b(has been merged|was merged|is merged|merged|has been fixed|is fixed|was fixed|fixed|resolved|'
                   r'is done|completed|deployed|landed|is back up|has been closed|was closed)\b', re.I)
NEGATED = re.compile(r'\b(not|never|isn\'t|wasn\'t|hasn\'t|no longer|un)\s*$', re.I)
UNKNOWN = re.compile(r'(cannot see|can\'t see|does not (mention|say|show|include)|doesn\'t (mention|say|show)|'
                     r'not (mentioned|in the context|stated)|no information|context does not)', re.I)
PR_REF = re.compile(r'(?:github\.com/[\w.-]+/([\w.-]+)/pull/(\d+))|(?:\b([A-Za-z][\w.-]+)\s*(?:PR\s*)?#(\d+))|(?:\bPR\s*#?(\d+))', re.I)
BUSY_TEXT = 'playing'


def now():
    return dt.datetime.now(dt.timezone.utc)


def age_s(stamp, t=None):
    try:
        return (t or now()) - dt.datetime.fromisoformat(str(stamp).replace('Z', '+00:00'))
    except (TypeError, ValueError):
        return None


def secs(stamp, t=None):
    d = age_s(stamp, t)
    return None if d is None else int(d.total_seconds())


def msg_id(m: dict) -> str:
    """Stable id for a channel line: its own id (orders) or a hash of when/who/what."""
    if m.get('id'):
        return str(m['id'])
    return hashlib.sha1(f"{m.get('at')}|{m.get('from')}|{m.get('text')}".encode('utf-8')).hexdigest()[:16]


def legacy_key(m: dict) -> str:
    """The pre-fix 'answered' key, so a redeploy does not re-answer lines the old feeder already handled."""
    return f"{m.get('at')}|{m.get('from')}|{m.get('text')}"


def _to(m: dict) -> str:
    return str(m.get('to') or '').strip().lower()


def addressed(m: dict) -> bool:
    """Is this line for the Mind? Named to it, or a genuine question to everyone/no one. Never its own lines."""
    if str(m.get('from', '')).lower().endswith('mind'):
        return False
    to = _to(m)
    if to in MIND_NAMES:
        return True
    if to in ('', 'all'):
        text = str(m.get('text', ''))
        named = re.search(r'\b(i3[- ]?)?mind\b', text, re.I) is not None
        return named and bool(QUESTION.search(text) or IMPERATIVE.search(text))
    return False


def classify(m: dict) -> str | None:
    """'order' for work orders to the Mind (kind=order, or an imperative line), 'question' for questions, else None."""
    if m.get('kind') == 'order':
        return 'order' if _to(m) in MIND_NAMES else None
    if m.get('kind'):
        return None
    if not addressed(m):
        return None
    text = re.sub(r'^\s*@?(i3[- ]?)?mind[,:]?\s*', '', str(m.get('text', '')), flags=re.I)
    if IMPERATIVE.search(text) and not QUESTION.search(text):
        return 'order'
    return 'question'


def busy(feed: dict) -> bool:
    return BUSY_TEXT in str(feed.get('screen', ''))


# ---------------------------------------------------------------- rate limit

def may_send(sent_at: list, t: float) -> bool:
    recent = [s for s in sent_at if t - s < WINDOW_S]
    if recent and t - max(recent) < MIN_GAP_S:
        return False
    return len(recent) < WINDOW_MAX


def note_sent(sent_at: list, t: float) -> list:
    return [s for s in sent_at if t - s < WINDOW_S] + [t]


# ---------------------------------------------------------------- facts

def pr_refs(text: str) -> list:
    """(repo or None, number) pairs mentioned in a line."""
    out = []
    for m in PR_REF.finditer(text or ''):
        repo = m.group(1) or m.group(3)
        num = m.group(2) or m.group(4) or m.group(5)
        if num:
            ref = (repo if repo and repo.lower() != 'pr' else None, int(num))
            if ref not in out:
                out.append(ref)
    return out


def pr_fact(repo, number, pipeline: list) -> str:
    hits = [p for p in pipeline if p.get('number') == number and (repo is None or str(p.get('repo', '')).lower() == repo.lower())]
    if len(hits) == 1:
        p = hits[0]
        return (f"{p['repo']}#{p['number']}: OPEN (not merged), stage {p.get('stage')}, CI {p.get('ci')}"
                f"{', reviewed by ' + ', '.join(p['reviewers']) if p.get('reviewers') else ''} [source: pipeline]")
    if len(hits) > 1:
        return f"PR #{number}: ambiguous, open in {', '.join(p['repo'] for p in hits)} [source: pipeline]"
    name = f"{repo}#{number}" if repo else f"PR #{number}"
    return f"{name}: not in the open-PR list, so its state is UNKNOWN to me [source: pipeline]"


def build_context(feed: dict, question: str) -> str:
    """Every line is a fact with the feed field it came from. Opinions (other Minds) are labelled as unverified."""
    lines = []
    for b in (feed.get('bodies') or {}).values():
        f = f" failing {', '.join(b['failing'])}" if b.get('failing') else ''
        lines.append(f"rig {b.get('label')}: {b.get('status')}{f}; {b.get('detail') or 'no detail'} [source: bodies]")
    colony = feed.get('colony') or {}
    bk = colony.get('backup')
    if isinstance(bk, dict):
        lines.append(f"off-box backup: {', '.join(f'{k}={v}' for k, v in list(bk.items())[:5])} [source: colony.backup]")
    elif bk is None:
        lines.append('off-box backup: UNKNOWN (CHORUS did not report it) [source: colony.backup]')
    for d in (colony.get('doctor') or [])[:12]:
        lines.append(f"doctor {d.get('key')}: {d.get('verdict')} [source: colony.doctor]")
    down = ((colony.get('spine') or {}).get('down')) or []
    if colony.get('spine'):
        lines.append(f"MSI spine: {colony['spine'].get('up')}/{colony['spine'].get('total')} up; down: {', '.join(down) or 'none'} [source: colony.spine]")
    pipeline = feed.get('pipeline') or []
    for repo, num in pr_refs(question):
        lines.append(pr_fact(repo, num, pipeline))
    for p in pipeline[:10]:
        lines.append(f"{p['repo']}#{p['number']} OPEN {p.get('stage')} CI {p.get('ci')}: {p.get('title', '')[:60]} [source: pipeline]")
    for o in (feed.get('orders') or [])[-6:]:
        lines.append(f"order {o.get('id')} to {o.get('to')}: {o.get('status')}{' (verified)' if o.get('verified') else ''}: "
                     f"{str(o.get('text', ''))[:60]} [source: orders]")
    lines.append(f"i3 screen: {feed.get('screen') or 'unknown'} [source: screen]")
    for e in (feed.get('events') or [])[-3:]:
        lines.append(f"UNVERIFIED opinion of {e.get('mind')} at {e.get('at')}: {str(e.get('line', ''))[:140]} [source: events]")
    return '\n'.join(lines)


SYSTEM = ('You are the i3 Mind of the GSV colony: a small local model that only OBSERVES. You have no tools and cannot act on any '
          'machine. Answer the QUESTION in 1-2 short sentences using only FACTS. Rules: '
          '(1) Never say a PR is merged, or that anything is fixed, done, resolved or deployed, unless a FACT says exactly that. '
          'A PR listed as OPEN is not merged. '
          '(2) End every claim with the [source: ...] tag of the FACT it came from. '
          '(3) Lines marked UNVERIFIED are other models\' opinions: never repeat them as fact. '
          '(4) If the FACTS do not answer it, reply exactly: Unknown: my feed does not show that. '
          '(5) Do not restate the question or the facts; answer it.')


def prompt(feed: dict, question: str) -> list:
    return [{'role': 'system', 'content': SYSTEM},
            {'role': 'user', 'content': f'FACTS:\n{build_context(feed, question)}\n\nQUESTION: {question}'}]


UNKNOWN_REPLY = 'Unknown: my feed does not show that.'


def supported(stem: str, fact_lines: list) -> bool:
    """A completion word is supported only by a measured fact line that states it positively."""
    for line in fact_lines:
        if 'unverified' in line or 'unknown' in line:
            continue
        if re.search(r'\b' + re.escape(stem) + r'\b', line) and not re.search(r'\b(not|never|no longer)\s+' + re.escape(stem) + r'\b', line):
            return True
    return False


def check_reply(reply: str, feed: dict, question: str = '') -> tuple[str, list]:
    """Return (reply to post, problems found). Unsupported completion claims are rejected and replaced by the
    measured PR facts (when the reply names a PR) or by one plain 'unknown'."""
    reply = (reply or '').strip()
    problems = []
    if not reply:
        return UNKNOWN_REPLY, ['empty reply']
    facts = build_context(feed, question + ' ' + reply).lower().splitlines()
    for m in CLAIM.finditer(reply):
        if NEGATED.search(reply[:m.start()][-14:]):
            continue
        word = m.group(1).lower()
        if not supported(word.split()[-1], facts):
            problems.append(f'unsupported claim "{word}"')
    pipeline = feed.get('pipeline') or []
    refs = pr_refs(reply) or pr_refs(question)
    for repo, num in refs:
        open_now = any(p.get('number') == num and (repo is None or str(p.get('repo', '')).lower() == repo.lower()) for p in pipeline)
        if open_now and re.search(r'\bmerged\b', reply, re.I) and not re.search(r'not merged|isn\'t merged|unmerged', reply, re.I):
            problems.append(f'says merged but #{num} is OPEN in pipeline')
    if problems:
        facts_lines = [pr_fact(r, n, pipeline) for r, n in refs]
        return ('; '.join(facts_lines) if facts_lines else UNKNOWN_REPLY), problems
    if UNKNOWN.search(reply):
        return UNKNOWN_REPLY, ['normalised unknown']
    return reply, problems


# ---------------------------------------------------------------- routing

ROUTE_RULES = (
    (re.compile(r'\b(msi|mempalace|spine|chorus|litellm|docker desktop|k:\\deploy|workshop)\b', re.I), 'claude (msi seat)', 'it is about the MSI'),
    (re.compile(r'\b(i3|gameattract|rotation|playtest|director|holomind|engine room)\b', re.I), 'claude (i3 seat)', 'it is about the i3'),
    (re.compile(r'\b(xanadu|l9|steward|icecast)\b', re.I), 'claude (msi seat)', 'the MSI seat holds xanadu and L9'),
    (re.compile(r'\b(review|pr\b|#\d+|pull/\d+)', re.I), 'claude (msi seat)', 'a review needs a seat that can run the code'),
)


def route_locally(text: str) -> tuple[str, str]:
    for rx, seat, why in ROUTE_RULES:
        if rx.search(text or ''):
            return seat, why
    return 'claude (i3 seat)', 'the i3 seat owns the i3 Mind'


def routing_reply(m: dict, suggestion: dict | None) -> tuple[str, str]:
    """(seat, text) for an order the Mind cannot carry out. `suggestion` is CHORUS's POST /route answer, if any."""
    seat, why, src = None, '', 'local rule'
    if isinstance(suggestion, dict) and suggestion.get('to') and suggestion.get('to') not in (MIND, 'all'):
        seat, why, src = suggestion['to'], str(suggestion.get('reasons') or ''), 'CHORUS /route'
    if not seat:
        seat, why = route_locally(str(m.get('text', '')))
    text = (f"I can't do that: I'm a read-only chat model on the i3 with no tools. Routing it to {seat}"
            f"{' (' + why + ')' if why else ''} [route: {src}].")
    return seat, text


# ---------------------------------------------------------------- one tick's plan

def plan(channel: list, feed: dict, mstate: dict, t_epoch: float, t_now=None) -> dict:
    """Decide what the Mind does this tick. Mutates nothing it is given; returns the new mind-state and actions.

    mstate keys: handled (ids fully dealt with), acked (ids acknowledged while busy), queue ({id: line}),
    attempts ({id: n}), sent_at ([epoch]). Actions: 'acks' (one coalesced line per tick, never twice for an id),
    'answer' (at most one question id to send to the model), 'routes' ([(line, ...)]), 'dropped' ([ids])."""
    t_now = t_now or now()
    handled = set(mstate.get('handled', []))
    legacy = set(mstate.get('legacy_answered', []))
    acked = set(mstate.get('acked', []))
    queue = dict(mstate.get('queue', {}))
    dropped = []
    routes = []
    for m in channel:
        kind = classify(m)
        if not kind:
            continue
        mid = msg_id(m)
        if mid in handled or legacy_key(m) in legacy:
            continue
        a = secs(m.get('at'), t_now)
        if a is not None and a > QUEUE_MAX_AGE_S:
            handled.add(mid)
            dropped.append(mid)
            continue
        if kind == 'order':
            routes.append(m)
        else:
            queue.setdefault(mid, {'at': m.get('at'), 'from': m.get('from'), 'text': m.get('text', ''), 'id': mid})
    for mid, q in list(queue.items()):
        a = secs(q.get('at'), t_now)
        if a is not None and a > QUEUE_MAX_AGE_S:
            queue.pop(mid)
            handled.add(mid)
            dropped.append(mid)
    out = {'routes': [], 'acks': None, 'answer': None, 'dropped': dropped}
    sent_at = list(mstate.get('sent_at', []))
    for m in routes:                       # orders first: a routing reply unblocks a person
        if not may_send(sent_at, t_epoch):
            break
        out['routes'].append(m)
        sent_at = note_sent(sent_at, t_epoch)
    if busy(feed):
        new = [q for mid, q in queue.items() if mid not in acked]
        if new and may_send(sent_at, t_epoch):
            out['acks'] = new
            sent_at = note_sent(sent_at, t_epoch)
    elif queue and may_send(sent_at, t_epoch):
        out['answer'] = sorted(queue.values(), key=lambda q: str(q.get('at')))[0]
    out['state'] = {'handled': sorted(handled)[-400:], 'acked': sorted(acked)[-400:], 'queue': queue,
                    'attempts': dict(mstate.get('attempts', {})), 'sent_at': sent_at,
                    'legacy_answered': sorted(legacy)[-200:]}
    return out


def ack_text(new: list) -> tuple[str, str]:
    """One acknowledgement for the questions newly queued this tick: (to, text)."""
    askers = sorted({str(q.get('from')) for q in new})
    n = len(new)
    return (askers[0] if len(askers) == 1 else 'all',
            f"Queued {n} question{'s' if n > 1 else ''} from {', '.join(askers)}: the i3 GPU is busy with a playtest. "
            f"I'll answer {'each' if n > 1 else 'it'} once, when the playtest ends.")


def mark(mstate: dict, ids, *, acked=False, handled=False) -> dict:
    """Record what was actually sent (call only after the channel write succeeded). Returns a new mind-state."""
    new = dict(mstate)
    ids = [ids] if isinstance(ids, str) else list(ids)
    if acked:
        new['acked'] = sorted(set(new.get('acked', [])) | set(ids))[-400:]
    if handled:
        new['handled'] = sorted(set(new.get('handled', [])) | set(ids))[-400:]
        new['queue'] = {k: v for k, v in new.get('queue', {}).items() if k not in ids}
        new['attempts'] = {k: v for k, v in new.get('attempts', {}).items() if k not in ids}
    return new


def failed(mstate: dict, mid: str) -> tuple[dict, bool]:
    """Count a model failure for a queued question. Returns (new state, give_up)."""
    new = dict(mstate)
    att = dict(new.get('attempts', {}))
    att[mid] = att.get(mid, 0) + 1
    new['attempts'] = att
    return new, att[mid] >= MAX_ATTEMPTS
