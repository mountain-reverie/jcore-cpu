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


if __name__ == "__main__":
    unittest.main()
