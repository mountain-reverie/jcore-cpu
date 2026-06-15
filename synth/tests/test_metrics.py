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
        # fixture's Total row ends in a percentage column (real OpenSTA format);
        # the wattage is the column before it: 1.257e-2 W -> 12.57 mW.
        got = metrics.parse_sta_report(read("sta_cpu.txt"), period_ns=20.0)
        self.assertAlmostEqual(got["power_mw"], 12.57, places=2)

    def test_power_total_without_percentage(self):
        # older OpenSTA omits the percentage column — last numeric is the watts.
        text = "Total   9.10e-03   3.30e-03   7.00e-05   1.257e-02\n"
        got = metrics.parse_sta_report(text, period_ns=20.0)
        self.assertAlmostEqual(got["power_mw"], 12.57, places=2)

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


class TestNextpnrIce40Log(unittest.TestCase):
    def test_utilisation_logic_cells_and_hardblocks(self):
        got = metrics.parse_nextpnr_ice40_log(read("nextpnr_ice40.log"))
        # ICESTORM_LC is the logic-cell count == the up5k "LUT4" budget figure
        self.assertEqual(got["util"]["ICESTORM_LC"], 6789)
        self.assertEqual(got["util"]["ICESTORM_RAM"], 4)
        self.assertEqual(got["util"]["ICESTORM_DSP"], 0)
        self.assertEqual(got["util"]["SB_IO"], 4)

    def test_fmax_keeps_lowest_post_route(self):
        got = metrics.parse_nextpnr_ice40_log(read("nextpnr_ice40.log"))
        self.assertAlmostEqual(got["fmax"]["clk"], 21.34)

    def test_empty_input_has_empty_util(self):
        self.assertEqual(metrics.parse_nextpnr_ice40_log(""), {"util": {}, "fmax": {}})


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
        self.assertEqual(names["cpu/WNS (relative)"]["dir"], "bigger")
        self.assertEqual(names["cpu/Fmax (relative)"]["unit"], "MHz")
        self.assertIn("cpu/power", names)

    def test_ecp5_metrics(self):
        util = metrics.parse_nextpnr_log(read("nextpnr_ecp5.log"))["util"]
        doc = metrics.build_ecp5(util, fmax_rep=42.86, fmax_bare=27.22,
                                 variant="direct-rom72", commit="abc123")
        self.assertEqual(doc["target"], "ecp5-lfe5u-85f")
        names = {x["name"]: x for x in doc["metrics"]}
        self.assertEqual(names["cpu/LUT4"]["value"], 6789)
        self.assertEqual(names["cpu/LUT4"]["dir"], "smaller")
        self.assertEqual(names["cpu/DP16KD"]["dir"], "smaller")
        self.assertEqual(names["cpu/Fmax (representative)"]["value"], 42.86)
        self.assertEqual(names["cpu/Fmax (representative)"]["dir"], "bigger")
        self.assertEqual(names["cpu/Fmax (IO-unconstrained)"]["value"], 27.22)

    def test_ecp5_omits_absent_fmax(self):
        doc = metrics.build_ecp5({"TRELLIS_COMB": 10}, fmax_rep=None,
                                 fmax_bare=None, variant="v", commit="c")
        names = [m["name"] for m in doc["metrics"]]
        self.assertEqual(names, ["cpu/LUT4"])  # no Fmax entries when unparsed

    def test_ice40_metrics_map_lc_to_lut4(self):
        util = metrics.parse_nextpnr_ice40_log(read("nextpnr_ice40.log"))["util"]
        doc = metrics.build_ice40(util, fmax_rep=21.34,
                                  variant="j1", commit="abc123")
        self.assertEqual(doc["target"], "ice40-up5k")
        self.assertEqual(doc["variant"], "j1")
        names = {x["name"]: x for x in doc["metrics"]}
        # ICESTORM_LC -> cpu/SB_LUT4 (the budget figure), smaller-is-better
        self.assertEqual(names["cpu/SB_LUT4"]["value"], 6789)
        self.assertEqual(names["cpu/SB_LUT4"]["dir"], "smaller")
        self.assertEqual(names["cpu/EBR"]["value"], 4)
        self.assertEqual(names["cpu/SB_MAC16"]["value"], 0)
        self.assertEqual(names["cpu/Fmax (representative)"]["value"], 21.34)
        self.assertEqual(names["cpu/Fmax (representative)"]["dir"], "bigger")

    def test_ice40_omits_absent_blocks_and_fmax(self):
        doc = metrics.build_ice40({"ICESTORM_LC": 4912}, fmax_rep=None,
                                  variant="j1", commit="c")
        names = [m["name"] for m in doc["metrics"]]
        self.assertEqual(names, ["cpu/SB_LUT4"])  # only what was parsed


class TestNextpnrFmax(unittest.TestCase):
    def test_takes_last_post_route_value(self):
        # same clock printed twice: early estimate then final post-route value;
        # the last line is the final one (matches the gate's tail -1).
        text = ("Info: Max frequency for clock 'clk': 29.26 MHz (FAIL at 50.00 MHz)\n"
                "Warning: Max frequency for clock 'clk': 42.86 MHz (FAIL at 50.00 MHz)\n")
        self.assertAlmostEqual(metrics.parse_nextpnr_fmax(text), 42.86)

    def test_none_when_absent(self):
        self.assertIsNone(metrics.parse_nextpnr_fmax("no frequency lines here\n"))


if __name__ == "__main__":
    unittest.main()
