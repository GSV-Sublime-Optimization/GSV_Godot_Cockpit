r"""What the i3 Mind may claim, and how often it may speak. Pure, so it can be tested; mind_worker.py owns the I/O.

Carried from PR #40 (02e9832, MSI seat), which traced the false "Dev-Mentor PR #293 has been merged" reply of
2026-11-08 17:43 UTC. The worker's tools-first design replaced #40's queue, addressing and routing, so only these parts
are kept:
  - build_context(): the feed's facts, each tagged with the field it came from.
  - check_reply():   a model reply claiming merged/fixed/done/deployed must be supported by those facts; otherwise it is
                     replaced by the measured PR fact or by one plain 'unknown'.
  - may_send():      at most one Mind line per 30 s and 6 per 10 minutes.
"""
from __future__ import annotations

import re

MIN_GAP_S = 30
WINDOW_S, WINDOW_MAX = 600, 6

CLAIM = re.compile(r'\b(has been merged|was merged|is merged|merged|has been fixed|is fixed|was fixed|fixed|resolved|'
                   r'is done|completed|deployed|landed|is back up|has been closed|was closed)\b', re.I)
NEGATED = re.compile(r'\b(not|never|isn\'t|wasn\'t|hasn\'t|no longer|un)\s*$', re.I)
UNKNOWN = re.compile(r'(cannot see|can\'t see|does not (mention|say|show|include)|doesn\'t (mention|say|show)|'
                     r'not (mentioned|in the context|stated)|no information|context does not)', re.I)
PR_REF = re.compile(r'(?:github\.com/[\w.-]+/([\w.-]+)/pull/(\d+))|(?:\b([A-Za-z][\w.-]+)\s*(?:PR\s*)?#(\d+))|(?:\bPR\s*#?(\d+))', re.I)
UNKNOWN_REPLY = 'Unknown: my feed does not show that.'


def may_send(sent_at: list, t: float) -> bool:
    recent = [s for s in sent_at if t - s < WINDOW_S]
    if recent and t - max(recent) < MIN_GAP_S:
        return False
    return len(recent) < WINDOW_MAX


def note_sent(sent_at: list, t: float) -> list:
    return [s for s in sent_at if t - s < WINDOW_S] + [t]


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
