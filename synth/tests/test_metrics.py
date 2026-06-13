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


class TestNextpnrLog(unittest.TestCase):
    def test_utilisation_and_hardblocks(self):
        got = metrics.parse_nextpnr_log(read("nextpnr_ecp5.log"))
        self.assertEqual(got["util"]["TRELLIS_COMB"], 6789)
        self.assertEqual(got["util"]["TRELLIS_FF"], 1234)
        self.assertEqual(got["util"]["DP16KD"], 2)
        self.assertEqual(got["util"]["MULT18X18D"], 1)
        self.assertEqual(got["util"]["TRELLIS_IO"], 42)

    def test_fmax_per_clock_from_fixture(self):
        got = metrics.parse_nextpnr_log(read("nextpnr_ecp5.log"))
        # bare '$glbnet$clk' is the canonical clock; cleaned name is "clk"
        self.assertAlmostEqual(got["fmax"]["clk"], 38.90)

    def test_fmax_keeps_lowest_on_name_collision(self):
        # two lines cleaning to the same name 'clk' -> keep the binding (lowest)
        text = ("Info: Max frequency for clock '$glbnet$clk': 55.00 MHz\n"
                "Info: Max frequency for clock '$net$clk': 40.00 MHz\n")
        got = metrics.parse_nextpnr_log(text)
        self.assertAlmostEqual(got["fmax"]["clk"], 40.00)


class TestBuildCanonical(unittest.TestCase):
    def test_asic_metrics_have_names_units_dirs(self):
        stat = metrics.parse_yosys_stat(read("yosys_stat_asic.txt"))
        sta = metrics.parse_sta_report(read("sta_cpu.txt"), period_ns=20.0)
        doc = metrics.build_asic(stat, sta, variant="direct-rom72", commit="abc123")
        self.assertEqual(doc["target"], "asic-nangate45")
        self.assertEqual(doc["variant"], "direct-rom72")
        names = {x["name"]: x for x in doc["metrics"]}
        self.assertEqual(names["cpu/area"]["unit"], "um2")
        self.assertEqual(names["cpu/area"]["dir"], "smaller")
        self.assertEqual(names["datapath/area"]["value"], 19880.0)
        self.assertEqual(names["cpu/WNS"]["dir"], "bigger")
        self.assertEqual(names["cpu/Fmax"]["unit"], "MHz")
        self.assertIn("cpu/power", names)

    def test_ecp5_metrics(self):
        npr = metrics.parse_nextpnr_log(read("nextpnr_ecp5.log"))
        doc = metrics.build_ecp5(npr, variant="direct-rom72", commit="abc123")
        self.assertEqual(doc["target"], "ecp5-lfe5u-85f")
        names = {x["name"]: x for x in doc["metrics"]}
        self.assertEqual(names["cpu/LUT4"]["value"], 6789)
        self.assertEqual(names["cpu/LUT4"]["dir"], "smaller")
        self.assertEqual(names["cpu/DP16KD"]["dir"], "smaller")
        self.assertEqual(names["clk/Fmax"]["dir"], "bigger")


if __name__ == "__main__":
    unittest.main()
