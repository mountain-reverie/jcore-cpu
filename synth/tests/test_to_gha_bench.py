import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import to_gha_bench  # noqa: E402

FIX = os.path.join(HERE, "fixtures")


class TestConvert(unittest.TestCase):
    def test_splits_by_direction_and_prefixes_target(self):
        size, speed = to_gha_bench.convert(
            [os.path.join(FIX, "canon_asic.json"),
             os.path.join(FIX, "canon_ecp5.json")])
        size_names = {e["name"]: e for e in size}
        speed_names = {e["name"]: e for e in speed}
        self.assertIn("asic-nangate45 · cpu/area", size_names)
        self.assertIn("ecp5-lfe5u-85f · cpu/LUT4", size_names)
        self.assertIn("asic-nangate45 · cpu/Fmax", speed_names)
        self.assertEqual(size_names["asic-nangate45 · cpu/area"]["unit"], "um2")
        self.assertEqual(size_names["asic-nangate45 · cpu/area"]["value"], 48210.0)
        self.assertEqual(size_names["ecp5-lfe5u-85f · cpu/LUT4"]["extra"], "direct-rom72")

    def test_deterministic_order(self):
        size, _ = to_gha_bench.convert(
            [os.path.join(FIX, "canon_ecp5.json"),
             os.path.join(FIX, "canon_asic.json")])
        names = [e["name"] for e in size]
        self.assertEqual(names, sorted(names))


if __name__ == "__main__":
    unittest.main()
