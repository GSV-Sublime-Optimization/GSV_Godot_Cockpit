"""actions._checkout must only accept checkouts really inside ROOTS.

Reproduction before the fix: _checkout("<root>/../elsewhere") and _checkout("<root>-x/repo") passed
the plain str.startswith test, so `preserve` could push from any repo on the disk. No git runs here.
"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import actions  # noqa: E402


class CheckoutTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.root = base / "active"
        for repo in (self.root / "good", base / "elsewhere", base / "active-x" / "repo"):
            (repo / ".git").mkdir(parents=True)
        self._roots, actions.ROOTS = actions.ROOTS, [self.root]

    def tearDown(self):
        actions.ROOTS = self._roots
        self.tmp.cleanup()

    def test_inside_root(self):
        self.assertIsNotNone(actions._checkout(str(self.root / "good")))

    def test_dotdot_escape_refused(self):
        self.assertIsNone(actions._checkout(str(self.root / ".." / "elsewhere")))

    def test_sibling_prefix_refused(self):
        self.assertIsNone(actions._checkout(str(self.root.parent / "active-x" / "repo")))


if __name__ == "__main__":
    unittest.main()
