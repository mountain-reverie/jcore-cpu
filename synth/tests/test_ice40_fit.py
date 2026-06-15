import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))  # import synth/ice40_fit.py
import ice40_fit  # noqa: E402


class TestWithinBudget(unittest.TestCase):
    def test_fits_when_all_within(self):
        self.assertTrue(ice40_fit.within_budget(
            {"SB_LUT4": 5000, "EBR": 10, "SB_MAC16": 0}))

    def test_over_lut4_fails(self):
        self.assertFalse(ice40_fit.within_budget(
            {"SB_LUT4": 5280, "EBR": 10, "SB_MAC16": 0}))

    def test_over_ebr_fails(self):
        self.assertFalse(ice40_fit.within_budget(
            {"SB_LUT4": 5000, "EBR": 31, "SB_MAC16": 0}))

    def test_over_dsp_fails(self):
        self.assertFalse(ice40_fit.within_budget(
            {"SB_LUT4": 5000, "EBR": 10, "SB_MAC16": 9}))

    def test_missing_key_fails(self):
        self.assertFalse(ice40_fit.within_budget({"SB_LUT4": 5000, "EBR": 10}))


class TestDecide(unittest.TestCase):
    FIT = {"SB_LUT4": 5000, "EBR": 10, "SB_MAC16": 0}
    OVER = {"SB_LUT4": 6789, "EBR": 4, "SB_MAC16": 0}

    def test_crossing_fires(self):
        self.assertTrue(ice40_fit.decide(self.FIT, True, self.OVER))

    def test_crossing_from_no_history_fires(self):
        self.assertTrue(ice40_fit.decide(self.FIT, True, {}))

    def test_still_over_does_not_fire(self):
        self.assertFalse(ice40_fit.decide(self.OVER, True, self.OVER))

    def test_already_fit_does_not_fire(self):
        self.assertFalse(ice40_fit.decide(self.FIT, True, self.FIT))

    def test_pnr_not_ok_does_not_fire(self):
        self.assertFalse(ice40_fit.decide(self.FIT, False, self.OVER))


class TestHistory(unittest.TestCase):
    def _hist(self, benches, date=2):
        return {"entries": {"synth-size": [
            {"date": 1, "benches": [
                {"name": "ice40-up5k · cpu/SB_LUT4 [j1]", "value": 9999}]},
            {"date": date, "benches": benches},
        ]}}

    def test_extracts_latest_j1_ice40(self):
        h = self._hist([
            {"name": "ice40-up5k · cpu/SB_LUT4 [j1]", "value": 6789},
            {"name": "ice40-up5k · cpu/EBR [j1]", "value": 4},
            {"name": "ice40-up5k · cpu/SB_MAC16 [j1]", "value": 0},
        ])
        got = ice40_fit.history_latest_j1(h)
        self.assertEqual(got["SB_LUT4"], 6789)
        self.assertEqual(got["EBR"], 4)
        self.assertEqual(got["SB_MAC16"], 0)

    def test_ignores_other_variants_and_targets(self):
        # Build a history with NO ice40 [j1] bench (don't use _hist, which injects
        # one): a bare name is J2, and the ecp5 [j1] is a different target.
        h = {"entries": {"synth-size": [{"date": 1, "benches": [
            {"name": "ice40-up5k · cpu/SB_LUT4", "value": 1},      # bare = j2
            {"name": "ecp5-lfe5u-85f · cpu/LUT4 [j1]", "value": 2},
        ]}]}}
        self.assertEqual(ice40_fit.history_latest_j1(h), {})

    def test_empty_history(self):
        self.assertEqual(ice40_fit.history_latest_j1({}), {})


class TestRender(unittest.TestCase):
    def test_contains_marker_numbers_and_delta(self):
        body = ice40_fit.render(
            {"SB_LUT4": 5000, "EBR": 10, "SB_MAC16": 0, "Fmax": 18.5},
            {"SB_LUT4": 6789, "EBR": 4, "SB_MAC16": 0},
            "https://owner.github.io/repo/")
        self.assertIn(ice40_fit.MARKER, body)
        self.assertIn("5000", body)
        self.assertIn("5280", body)        # budget shown
        self.assertIn("-1789", body)       # delta vs prior LUT4
        self.assertIn("18.5", body)        # Fmax
        self.assertIn("owner.github.io/repo", body)


if __name__ == "__main__":
    unittest.main()
