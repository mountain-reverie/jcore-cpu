import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import to_gha_bench  # noqa: E402

FIX = os.path.join(HERE, "fixtures")


def _write_canon(dirpath, target, variant, metrics):
    p = os.path.join(dirpath, "%s_%s.json" % (target, variant))
    with open(p, "w") as f:
        json.dump({"target": target, "variant": variant, "commit": "c",
                   "metrics": metrics}, f)
    return p


class TestConvert(unittest.TestCase):
    def test_splits_by_direction_and_prefixes_target(self):
        # The committed fixtures use legacy variant "direct-rom72" -> maps to J2,
        # so names stay BARE (continuous with the published J2 history).
        size, speed, pnr = to_gha_bench.convert(
            [os.path.join(FIX, "canon_asic.json"),
             os.path.join(FIX, "canon_ecp5.json")])
        size_names = {e["name"]: e for e in size}
        speed_names = {e["name"]: e for e in speed}
        self.assertIn("asic-nangate45 · cpu/area", size_names)
        self.assertIn("ecp5-lfe5u-85f · cpu/LUT4", size_names)
        self.assertIn("asic-nangate45 · cpu/Fmax", speed_names)
        self.assertEqual(size_names["asic-nangate45 · cpu/area"]["unit"], "um2")
        self.assertEqual(size_names["asic-nangate45 · cpu/area"]["value"], 48210.0)
        # legacy "direct-rom72" is normalised to the canonical "j2"
        self.assertEqual(size_names["ecp5-lfe5u-85f · cpu/LUT4"]["extra"], "j2")

    def test_deterministic_order(self):
        size, _, _pnr = to_gha_bench.convert(
            [os.path.join(FIX, "canon_ecp5.json"),
             os.path.join(FIX, "canon_asic.json")])
        names = [e["name"] for e in size]
        self.assertEqual(names, sorted(names))

    def test_j2_bare_j1_j4_suffixed(self):
        # J2 keeps the bare name (so its published history continues); J1/J4 get
        # a "[variant]" suffix so the benchmark action keys them as distinct
        # series (no cross-variant false regression).
        m = [{"name": "cpu/LUT4", "unit": "LUT4", "value": 1, "dir": "smaller"}]
        with tempfile.TemporaryDirectory() as d:
            paths = [
                _write_canon(d, "ecp5-lfe5u-85f", "j2", m),
                _write_canon(d, "ecp5-lfe5u-85f", "j1", m),
                _write_canon(d, "ecp5-lfe5u-85f", "j4", m),
            ]
            size, _, _pnr = to_gha_bench.convert(paths)
        names = {e["name"]: e for e in size}
        self.assertIn("ecp5-lfe5u-85f · cpu/LUT4", names)          # j2 bare
        self.assertIn("ecp5-lfe5u-85f · cpu/LUT4 [j1]", names)     # j1 suffixed
        self.assertIn("ecp5-lfe5u-85f · cpu/LUT4 [j4]", names)     # j4 suffixed
        self.assertEqual(names["ecp5-lfe5u-85f · cpu/LUT4"]["extra"], "j2")
        self.assertEqual(names["ecp5-lfe5u-85f · cpu/LUT4 [j1]"]["extra"], "j1")


def _doc(tmp, target, variant, metrics):
    p = os.path.join(tmp, "%s-%s.json" % (target, variant))
    with open(p, "w") as f:
        json.dump({"target": target, "variant": variant, "metrics": metrics}, f)
    return p


class TestPnrBucket(unittest.TestCase):
    def test_pnr_target_isolated_from_size_and_speed(self):
        with tempfile.TemporaryDirectory() as tmp:
            cheap = _doc(tmp, "asic-sky130", "j2",
                         [{"name": "cpu/area", "unit": "um2", "value": 1.0, "dir": "smaller"}])
            pnr = _doc(tmp, "asic-sky130-pnr", "j2",
                       [{"name": "cpu/area", "unit": "um2", "value": 2.0, "dir": "smaller"}])
            size, speed, pnrb = to_gha_bench.convert([cheap, pnr])
            size_names = [e["name"] for e in size]
            pnr_names = [e["name"] for e in pnrb]
            # cheap sky130 stays in size; pnr only in pnr bucket
            self.assertTrue(any("asic-sky130 ·" in n for n in size_names))
            self.assertFalse(any("-pnr" in n for n in size_names))
            self.assertFalse(any("-pnr" in e["name"] for e in speed))
            self.assertTrue(all("asic-sky130-pnr ·" in n for n in pnr_names))
            self.assertEqual(len(pnr_names), 1)


if __name__ == "__main__":
    unittest.main()
