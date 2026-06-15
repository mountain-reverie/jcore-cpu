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
        # Faithful parse: keyed by the RAW GHDL-mangled module names yosys emits
        # under `synth -top cpu` (no -flatten).
        got = metrics.parse_yosys_stat(read("yosys_stat_asic.txt"))
        self.assertEqual(got["datapath_Bstru"]["cells"], 2345)
        self.assertAlmostEqual(got["datapath_Bstru"]["area"], 19880.0)
        self.assertEqual(got["mult_Bstru"]["cells"], 820)
        self.assertAlmostEqual(got["register_file_Btwo_bank_5_21_32"]["area"], 6300.0)

    def test_top_uses_chip_area_for_top_module(self):
        got = metrics.parse_yosys_stat(read("yosys_stat_asic.txt"))
        # raw cpu module is the thin top-level glue (3 cells); its area is the
        # 'top module' recursive total (48210), not the 30 glue-only area.
        self.assertEqual(got["cpu"]["cells"], 3)
        self.assertAlmostEqual(got["cpu"]["area"], 48210.0)

    def test_design_hierarchy_total_does_not_bleed(self):
        # '=== design hierarchy ===' is the LAST section; its 5547-cell recursive
        # total must NOT overwrite the preceding real module (shifter_Bcomb=329).
        got = metrics.parse_yosys_stat(read("yosys_stat_asic.txt"))
        self.assertEqual(got["shifter_Bcomb"]["cells"], 329)
        self.assertEqual(got["design hierarchy"]["cells"], 5547)

    def test_empty_input_returns_empty(self):
        self.assertEqual(metrics.parse_yosys_stat(""), {})

    def test_module_without_liberty_area_has_cells_only(self):
        text = "=== foo ===\n   Number of cells:                 12\n"
        got = metrics.parse_yosys_stat(text)
        self.assertEqual(got["foo"]["cells"], 12)
        self.assertNotIn("area", got["foo"])


class TestAggregateBlocks(unittest.TestCase):
    def setUp(self):
        self.agg = metrics.aggregate_blocks(
            metrics.parse_yosys_stat(read("yosys_stat_asic.txt")))

    def test_strips_arch_suffix_to_bare_block(self):
        self.assertEqual(self.agg["datapath"]["cells"], 2345)
        self.assertEqual(self.agg["mult"]["cells"], 820)
        self.assertAlmostEqual(self.agg["register_file"]["area"], 6300.0)

    def test_shifter_is_its_own_block(self):
        self.assertEqual(self.agg["shifter"]["cells"], 329)
        self.assertAlmostEqual(self.agg["shifter"]["area"], 2600.0)

    def test_decode_rolls_up_submodules(self):
        # decode_Barch + decode_core_* + decode_table_* all fold into decode
        self.assertEqual(self.agg["decode"]["cells"], 200 + 210 + 1000)
        self.assertAlmostEqual(self.agg["decode"]["area"], 1500.0 + 1600.0 + 7920.0)

    def test_cpu_is_whole_design_total_not_top_glue(self):
        self.assertEqual(self.agg["cpu"]["cells"], 5547)   # design-hierarchy total
        self.assertAlmostEqual(self.agg["cpu"]["area"], 48210.0)

    def test_blocks_partition_the_design(self):
        attributed = sum(self.agg[b]["cells"] for b in
                         ["datapath", "decode", "mult", "register_file", "shifter"])
        # whole-design total minus the 3-cell top-level glue
        self.assertEqual(attributed, 5547 - 3)

    def test_falls_back_to_cell_sum_without_design_hierarchy(self):
        stat = {"cpu": {"cells": 3}, "datapath_Bstru": {"cells": 100},
                "shifter_Bcomb": {"cells": 50}}
        agg = metrics.aggregate_blocks(stat)
        self.assertEqual(agg["cpu"]["cells"], 153)  # 3 + 100 + 50


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
        self.assertEqual(names["cpu/area"]["value"], 48210.0)
        self.assertEqual(names["cpu/cells"]["value"], 5547)
        self.assertEqual(names["datapath/area"]["value"], 19880.0)
        # the extracted shifter is surfaced as its own block
        self.assertEqual(names["shifter/cells"]["value"], 329)
        self.assertAlmostEqual(names["shifter/area"]["value"], 2600.0)
        # decode rolls up its sub-modules rather than reporting only the wrapper
        self.assertEqual(names["decode/cells"]["value"], 1410)
        self.assertEqual(names["cpu/WNS (relative)"]["dir"], "bigger")
        self.assertEqual(names["cpu/Fmax (relative)"]["unit"], "MHz")
        self.assertIn("cpu/power", names)

    def test_asic_cpu_from_flat_stat_blocks_from_hierarchical(self):
        # CI feeds a flattened mapped stat (single cpu module = total) as --stat
        # for series continuity, and a hierarchical mapped stat as --block-stat
        # for the per-block breakdown. cpu must come from the flat one, the
        # blocks from the hierarchical one.
        flat = ("=== cpu ===\n   Number of cells:               9000\n"
                "   Chip area for top module '\\cpu': 70000.000000\n")
        doc = metrics.build_asic(
            metrics.parse_yosys_stat(flat), {}, "j2", "c",
            block_stat=metrics.parse_yosys_stat(read("yosys_stat_asic.txt")))
        names = {m["name"]: m for m in doc["metrics"]}
        # cpu total: from the flat stat, NOT the hierarchical 5547/48210
        self.assertEqual(names["cpu/cells"]["value"], 9000)
        self.assertEqual(names["cpu/area"]["value"], 70000.0)
        # per-block: from the hierarchical block_stat
        self.assertEqual(names["shifter/cells"]["value"], 329)
        self.assertEqual(names["datapath/area"]["value"], 19880.0)
        self.assertEqual(names["decode/cells"]["value"], 1410)

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
