import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))  # import synth/metrics.py
import metrics  # noqa: E402

FIX = os.path.join(HERE, "fixtures")


def read(name):
    with open(os.path.join(FIX, name)) as f:
        return f.read()


class TestYosysStat(unittest.TestCase):
    def test_parses_per_module_cells_and_area(self):
        got = metrics.parse_yosys_stat(read("yosys_stat_asic.txt"))
        self.assertEqual(got["datapath"]["cells"], 2345)
        self.assertAlmostEqual(got["datapath"]["area"], 19880.0)
        self.assertEqual(got["mult"]["cells"], 820)
        self.assertAlmostEqual(got["register_file"]["area"], 6300.0)

    def test_top_uses_chip_area_for_top_module(self):
        got = metrics.parse_yosys_stat(read("yosys_stat_asic.txt"))
        self.assertEqual(got["cpu"]["cells"], 5678)
        self.assertAlmostEqual(got["cpu"]["area"], 48210.0)

    def test_empty_input_returns_empty(self):
        self.assertEqual(metrics.parse_yosys_stat(""), {})

    def test_module_without_liberty_area_has_cells_only(self):
        text = "=== foo ===\n   Number of cells:                 12\n"
        got = metrics.parse_yosys_stat(text)
        self.assertEqual(got["foo"]["cells"], 12)
        self.assertNotIn("area", got["foo"])


class TestStaReport(unittest.TestCase):
    def test_wns_tns(self):
        got = metrics.parse_sta_report(read("sta_cpu.txt"), period_ns=20.0)
        self.assertAlmostEqual(got["wns"], -4.83)
        self.assertAlmostEqual(got["tns"], -52.10)

    def test_fmax_from_critical_path(self):
        # critical path = period - wns = 20 - (-4.83) = 24.83 ns -> 40.27 MHz
        got = metrics.parse_sta_report(read("sta_cpu.txt"), period_ns=20.0)
        self.assertAlmostEqual(got["fmax_mhz"], 1000.0 / 24.83, places=2)

    def test_power_total_mw(self):
        got = metrics.parse_sta_report(read("sta_cpu.txt"), period_ns=20.0)
        self.assertAlmostEqual(got["power_mw"], 12.57, places=2)  # 1.257e-2 W

    def test_positive_slack_fmax(self):
        # timing met: wns=+1.50 at 20ns -> crit=18.50ns -> 54.05 MHz
        text = "wns max 1.50\ntns max 0.00\n"
        got = metrics.parse_sta_report(text, period_ns=20.0)
        self.assertAlmostEqual(got["wns"], 1.50)
        self.assertAlmostEqual(got["fmax_mhz"], 1000.0 / 18.50, places=2)


if __name__ == "__main__":
    unittest.main()
