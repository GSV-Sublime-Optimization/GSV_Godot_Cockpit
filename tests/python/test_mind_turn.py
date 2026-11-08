"""cockpit_feed.mind_turn wiring: ids are marked only after the channel write succeeds, errors are logged not posted."""
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'tools' / 'holomind'))
import cockpit_feed as cf  # noqa: E402
from test_mind import feed, q  # noqa: E402


class MindTurn(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.err = pathlib.Path(self.tmp.name) / 'cockpit.err.txt'
        self.sent = []
        patches = [mock.patch.object(cf, 'ERR', self.err),
                   mock.patch.object(cf, 'chorus_route', lambda text: None),
                   mock.patch.object(cf, 'append_lines', self.fake_append)]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        self.ok = True

    def tearDown(self):
        self.tmp.cleanup()

    def fake_append(self, lines):
        if self.ok:
            self.sent.extend(lines)
        return self.ok

    def test_unsupported_merged_answer_is_rewritten_and_logged(self):
        with mock.patch.object(cf, 'ask_mind', lambda qt, f: cf.mind.check_reply('Dev-Mentor#293 has been merged.', f, qt)):
            cf.mind_turn({}, [q('Is Dev-Mentor#293 merged?')], feed())
        self.assertEqual(len(self.sent), 1)
        self.assertIn('OPEN (not merged)', self.sent[0]['text'])
        self.assertIn('post-check rewrote', self.err.read_text(encoding='utf-8'))

    def test_failed_write_is_retried_not_forgotten(self):
        state = {}
        self.ok = False
        with mock.patch.object(cf, 'ask_mind', lambda qt, f: ('i3 is red [source: bodies]', [])):
            cf.mind_turn(state, [q('Which rig?')], feed())
            self.assertEqual(len(state['mind']['queue']), 1)
            self.ok = True
            state['mind']['sent_at'] = []
            cf.mind_turn(state, [q('Which rig?')], feed())
        self.assertEqual(len(self.sent), 1)
        self.assertEqual(state['mind']['queue'], {})

    def test_model_error_is_logged_not_posted(self):
        def boom(qt, f):
            raise TimeoutError('ollama timed out')
        state = {}
        with mock.patch.object(cf, 'ask_mind', boom):
            cf.mind_turn(state, [q('Which rig?')], feed())
        self.assertEqual(self.sent, [])
        self.assertIn('ollama timed out', self.err.read_text(encoding='utf-8'))
        self.assertFalse(state['mind_ok'])

    def test_order_gets_reply_and_declined_status(self):
        order = {'at': q('x')['at'], 'from': 'keath (chorus)', 'kind': 'order', 'id': 'o-1', 'to': 'i3-mind',
                 'text': 'restart mempalace on the MSI'}
        state = {}
        cf.mind_turn(state, [order], feed())
        self.assertEqual([l.get('kind') for l in self.sent], [None, 'order-status'])
        self.assertEqual(self.sent[1]['status'], 'declined')
        self.assertIn('claude (msi seat)', self.sent[0]['text'])
        cf.mind_turn(state, [order], feed())
        self.assertEqual(len(self.sent), 2)            # once, never again


if __name__ == '__main__':
    unittest.main()
