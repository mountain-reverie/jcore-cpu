import os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import pnr_regression  # noqa: E402


def _hist(*points):
    # each point: list of (name, value)
    entries = []
    for i, pt in enumerate(points):
        entries.append({
            "commit": {"id": "c%d" % i},
            "date": i,
            "benches": [{"name": n, "value": v, "unit": "um2"} for n, v in pt],
        })
    return {"entries": {"synth-asic-pnr": entries}}


class TestFindRegressions(unittest.TestCase):
    def test_no_baseline_returns_empty(self):
        h = _hist([("a", 100.0)])
        self.assertEqual(pnr_regression.find_regressions(h), [])

    def test_detects_regression_over_threshold(self):
        h = _hist([("a", 100.0)], [("a", 120.0)])   # +20% > 110%
        r = pnr_regression.find_regressions(h)
        self.assertEqual(len(r), 1)
        self.assertEqual(r[0]["name"], "a")
        self.assertAlmostEqual(r[0]["ratio"], 1.2)
        self.assertEqual(r[0]["commit"], "c1")

    def test_within_threshold_is_not_flagged(self):
        h = _hist([("a", 100.0)], [("a", 105.0)])   # +5% < 110%
        self.assertEqual(pnr_regression.find_regressions(h), [])

    def test_improvement_not_flagged(self):
        h = _hist([("a", 100.0)], [("a", 80.0)])
        self.assertEqual(pnr_regression.find_regressions(h), [])
