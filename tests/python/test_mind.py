"""The i3 Mind's judgement (tools/holomind/mind.py). Cases are taken from the 2026-11-08 channel on xanadu.

Run: python -m pytest tests/python -q   (or: python -m unittest discover -s tests/python)
"""
import datetime as dt
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'tools' / 'holomind'))
import mind  # noqa: E402

T0 = dt.datetime(2026, 11, 8, 18, 30, tzinfo=dt.timezone.utc)
EPOCH = T0.timestamp()


def at(minutes_ago):
    return (T0 - dt.timedelta(minutes=minutes_ago)).strftime('%Y-%m-%dT%H:%M:%SZ')


PIPELINE = [{'repo': 'Dev-Mentor', 'number': 293, 'title': 'fix(arcs): make arc tick failures loud', 'stage': 'needs-review',
             'ci': 'pass', 'reviewers': [], 'url': 'https://github.com/GSV-Sublime-Optimization/Dev-Mentor/pull/293'}]


def feed(screen='rotation waiting', pipeline=PIPELINE):
    return {'screen': screen, 'pipeline': pipeline,
            'bodies': {'i3': {'label': 'i3', 'status': 'red', 'failing': ['docker'], 'detail': 'RAM 14943 MB free'}},
            'colony': {'backup': None, 'doctor': [{'key': 'mempalace', 'verdict': 'ok'}], 'spine': {'up': 11, 'total': 12, 'down': ['mempalace-api']}},
            'events': [{'mind': 'l9-triage-drone', 'at': at(60), 'line': 'multiple failures with insufficient RAM'}],
            'orders': []}


def q(text, minutes_ago=1, frm='keath (holomind)', to='mind', **kw):
    return {'at': at(minutes_ago), 'from': frm, 'to': to, 'text': text, **kw}


class Addressing(unittest.TestCase):
    def test_broadcast_status_to_all_is_not_a_question(self):
        # 16:11-18:23: six status broadcasts to 'all' each drew a reply. They ask the Mind nothing.
        m = q('PR triage 2026-11-08: 507 open PRs/12 orgs (19 non-draft).', frm='claude (msi seat)', to='all')
        self.assertIsNone(mind.classify(m))

    def test_question_to_mind_and_named_question_to_all(self):
        self.assertEqual(mind.classify(q('Which rig needs attention right now, and why?')), 'question')
        self.assertEqual(mind.classify(q('i3 mind, is the backup overdue?', to='all')), 'question')
        self.assertEqual(mind.classify(q('Which rig?', to='i3-mind')), 'question')

    def test_own_lines_and_other_seats_ignored(self):
        self.assertIsNone(mind.classify(q('hello', frm='i3-mind')))
        self.assertIsNone(mind.classify(q('what now?', to='claude (i3 seat)')))

    def test_orders_are_orders(self):
        order = {'at': at(5), 'from': 'keath (chorus)', 'kind': 'order', 'id': 'o-1108-181713', 'to': 'i3-mind',
                 'text': 'Review Dev-Mentor#293: run it, then post evidence'}
        self.assertEqual(mind.classify(order), 'order')
        self.assertEqual(mind.classify(q('restart mempalace on the MSI')), 'order')
        self.assertIsNone(mind.classify(dict(order, to='claude (msi seat)')))


class BusyDedupe(unittest.TestCase):
    def test_one_ack_per_question_then_one_answer_when_free(self):
        ch = [q('Which rig needs attention?', 3), q('Is the backup overdue?', 2)]
        p = mind.plan(ch, feed('playing furyline'), {}, EPOCH, T0)
        self.assertEqual(len(p['acks']), 2)              # both acknowledged, in ONE line
        self.assertIsNone(p['answer'])
        to, text = mind.ack_text(p['acks'])
        self.assertIn('Queued 2 questions', text)
        st = mind.mark(p['state'], [x['id'] for x in p['acks']], acked=True)
        # Next ticks, still busy: nothing new, so no further acknowledgement, ever.
        for k in range(1, 6):
            p2 = mind.plan(ch, feed('playing furyline'), st, EPOCH + 60 * k, T0)
            self.assertIsNone(p2['acks'])
            st = p2['state']
        # A third question arrives during the same playtest: acknowledged once, alone.
        ch.append(q('Who is reviewing #293?', 0))
        p3 = mind.plan(ch, feed('playing furyline'), st, EPOCH + 400, T0)
        self.assertEqual([x['text'] for x in p3['acks']], ['Who is reviewing #293?'])
        st = mind.mark(p3['state'], [x['id'] for x in p3['acks']], acked=True)
        # Playtest over, even 40 minutes later: the queue is answered oldest first, one per send slot.
        later = T0 + dt.timedelta(minutes=40)
        p4 = mind.plan(ch, feed('rotation waiting'), st, EPOCH + 2400, later)
        self.assertEqual(p4['answer']['text'], 'Which rig needs attention?')
        st = mind.mark(p4['state'], p4['answer']['id'], handled=True)
        p5 = mind.plan(ch, feed('rotation waiting'), st, EPOCH + 2400 + mind.MIN_GAP_S, later)
        self.assertEqual(p5['answer']['text'], 'Is the backup overdue?')

    def test_legacy_answered_lines_are_not_replayed(self):
        m = q('Which rig needs attention?', 3)
        p = mind.plan([m], feed(), {'legacy_answered': [mind.legacy_key(m)]}, EPOCH, T0)
        self.assertIsNone(p['answer'])

    def test_too_old_questions_are_dropped_not_answered(self):
        p = mind.plan([q('Which rig?', 60 * 7)], feed(), {}, EPOCH, T0)
        self.assertIsNone(p['answer'])
        self.assertEqual(len(p['dropped']), 1)


class Grounding(unittest.TestCase):
    def test_rejects_unsupported_merged_claim(self):
        # 17:43:52: "The Dev-Mentor PR #293 has been merged" while gh said OPEN.
        bad = 'The Dev-Mentor PR #293 has been merged, with all 611 arc-related tests passing.'
        out, problems = mind.check_reply(bad, feed(), 'Dev-Mentor PR #293 arc tick no longer swallowed')
        self.assertTrue(problems)
        self.assertNotIn('has been merged', out)
        self.assertIn('Dev-Mentor#293: OPEN (not merged)', out)
        self.assertIn('[source: pipeline]', out)

    def test_merged_claim_for_pr_not_in_feed_is_unknown(self):
        out, problems = mind.check_reply('Kilo_Core#692 was merged.', feed(), 'is Kilo_Core#692 in?')
        self.assertTrue(problems)
        self.assertIn('UNKNOWN', out)

    def test_negated_and_supported_claims_pass(self):
        ok = 'Dev-Mentor#293 is open and not merged; it needs a second review [source: pipeline].'
        self.assertEqual(mind.check_reply(ok, feed(), '')[0], ok)

    def test_unknown_is_said_once_plainly(self):
        out, _ = mind.check_reply('The CONTEXT does not mention the off-box backup being overdue.', feed(), 'backup?')
        self.assertEqual(out, mind.UNKNOWN_REPLY)

    def test_context_has_pr_state_doctor_and_labels_opinions(self):
        ctx = mind.build_context(feed(), 'what about Dev-Mentor#293?')
        self.assertIn('Dev-Mentor#293: OPEN (not merged), stage needs-review, CI pass [source: pipeline]', ctx)
        self.assertIn('doctor mempalace: ok [source: colony.doctor]', ctx)
        self.assertIn('down: mempalace-api', ctx)
        self.assertIn('off-box backup: UNKNOWN', ctx)
        self.assertIn('UNVERIFIED opinion of l9-triage-drone', ctx)


class Routing(unittest.TestCase):
    ORDER = {'at': at(5), 'from': 'keath (chorus)', 'kind': 'order', 'id': 'o-1108-181713', 'to': 'i3-mind',
             'text': 'Review Dev-Mentor#293 ("fix(arcs)"): run it, then post evidence'}

    def test_order_gets_one_routing_reply(self):
        p = mind.plan([self.ORDER], feed(), {}, EPOCH, T0)
        self.assertEqual(p['routes'], [self.ORDER])
        st = mind.mark(p['state'], mind.msg_id(self.ORDER), handled=True)
        self.assertEqual(mind.plan([self.ORDER], feed(), st, EPOCH + 600, T0)['routes'], [])

    def test_routing_reply_uses_chorus_suggestion_else_local_rule(self):
        seat, text = mind.routing_reply(self.ORDER, {'to': 'codex', 'reasons': 'second actor for a Claude PR'})
        self.assertEqual(seat, 'codex')
        self.assertIn("I can't do that", text)
        self.assertIn('CHORUS /route', text)
        seat, text = mind.routing_reply(q('restart mempalace on the MSI'), None)
        self.assertEqual(seat, 'claude (msi seat)')
        self.assertIn('local rule', text)
        seat, _ = mind.routing_reply(q('stop the GameAttract rotation'), {'to': 'i3-mind'})   # never route to itself
        self.assertEqual(seat, 'claude (i3 seat)')


class RateLimit(unittest.TestCase):
    def test_gap_and_window(self):
        sent = []
        self.assertTrue(mind.may_send(sent, 0))
        sent = mind.note_sent(sent, 0)
        self.assertFalse(mind.may_send(sent, 10))
        for k in range(1, mind.WINDOW_MAX):
            sent = mind.note_sent(sent, k * mind.MIN_GAP_S)
        self.assertFalse(mind.may_send(sent, mind.WINDOW_MAX * mind.MIN_GAP_S))
        self.assertTrue(mind.may_send(sent, mind.WINDOW_S + mind.WINDOW_MAX * mind.MIN_GAP_S))

    def test_flood_of_orders_is_limited_per_tick(self):
        orders = [dict(Routing.ORDER, id=f'o-{i}') for i in range(5)]
        p = mind.plan(orders, feed(), {}, EPOCH, T0)
        self.assertEqual(len(p['routes']), 1)


class Failures(unittest.TestCase):
    def test_model_failures_counted_then_give_up_once(self):
        st = {}
        for i in range(mind.MAX_ATTEMPTS - 1):
            st, give_up = mind.failed(st, 'x')
            self.assertFalse(give_up)
        st, give_up = mind.failed(st, 'x')
        self.assertTrue(give_up)


if __name__ == '__main__':
    unittest.main()
