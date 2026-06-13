# FPGA/ASIC Synthesis Metrics Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture FPGA (ECP5) and ASIC (Nangate45) synthesis metrics on every commit, persist them as per-commit history on the GitHub Pages site, alert on PR regressions, and render trend / per-block / variant-comparison dashboards.

**Architecture:** `synth-cpu.yml` runs the existing synth flow, then new scripts parse the tool output into canonical JSON, convert it to `github-action-benchmark`'s custom format, and (on master) publish the whole site via the Actions Pages pipeline (no `gh-pages` branch — history is bootstrapped by curling the prior data back from the live site, matching playwright-ci-go).

**Tech Stack:** Python 3 (stdlib only) for parsing/conversion, Bash for the STA driver, `benchmark-action/github-action-benchmark@v1`, Chart.js (CDN) for the custom dashboard, GitHub Actions Pages deploy.

**Spec:** `docs/superpowers/specs/2026-06-13-synth-metrics-dashboard-design.md`

---

## File Structure

**New files:**
- `synth/metrics.py` — parsers (yosys `stat`, OpenSTA report, nextpnr log) + canonical-JSON builder + CLI. Pure functions, fully unit-tested.
- `synth/to_gha_bench.py` — merge canonical JSONs → `gha-bench-{size,speed}.json` (action input format).
- `synth/cpu_sta.sh` — full-CPU Nangate45 tech-map + OpenSTA driver (extends `regression.sh` Step 8 from the decoder to `cpu`).
- `synth/tests/test_metrics.py` — `unittest` for `metrics.py`.
- `synth/tests/test_to_gha_bench.py` — `unittest` for `to_gha_bench.py`.
- `synth/tests/fixtures/` — captured sample tool outputs + expected JSON.
- `dashboard/index.html`, `dashboard/app.js` — custom Chart.js dashboard.
- `dashboard/fixtures/data.js` — tiny `window.BENCHMARK_DATA` sample for local dashboard testing.

**Modified files:**
- `.github/workflows/synth-cpu.yml` — add STA + emit steps to `synth-asic`/`synth-ecp5`; add `publish-pages` job.
- `synth/README.md` — document the metrics scripts and local reproduction.

**Key conventions (from spec):**
- Metric `name` is always `<block>/<metric>` (e.g. `cpu/area`, `datapath/area`).
- A canonical metric is `{"name","unit","value","dir"}` where `dir ∈ {smaller,bigger}`.
- `target ∈ {asic-nangate45, ecp5-lfe5u-85f}`; `variant` starts at `direct-rom72`.
- Per-block = `decode, datapath, mult, register_file`. Timing/Fmax/power are top-level (`cpu/...`) only.
- All metric emission is **best-effort, non-gating**: a parse miss omits that metric and prints `WARN`, never exits non-zero.

---

## Task 1: Scaffold + yosys `stat` parser (TDD)

**Files:**
- Create: `synth/metrics.py`
- Create: `synth/tests/test_metrics.py`
- Create: `synth/tests/fixtures/yosys_stat_asic.txt`

- [ ] **Step 1: Create the yosys-stat fixture**

Create `synth/tests/fixtures/yosys_stat_asic.txt` with a representative
`stat -liberty` dump (hierarchical: a top `cpu` plus sub-modules). Exact text:

```
2. Printing statistics.

=== datapath ===

   Number of wires:               2100
   Number of cells:               2345
     $_DFF_P_                       210
     AND2_X1                        900

   Chip area for module '\datapath': 19880.000000

=== decode ===

   Number of wires:               1500
   Number of cells:               1410
     AOI21_X1                       700

   Chip area for module '\decode': 11020.000000

=== mult ===

   Number of cells:                820
   Chip area for module '\mult': 8450.000000

=== register_file ===

   Number of cells:                640
   Chip area for module '\register_file': 6300.000000

=== cpu ===

   Number of wires:               9000
   Number of cells:               5678

   Chip area for module '\cpu': 2560.000000

   Chip area for top module '\cpu': 48210.000000
```

- [ ] **Step 2: Write the failing test**

Create `synth/tests/test_metrics.py`:

```python
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `python3 -m unittest synth.tests.test_metrics -v` from repo root
(or `cd synth/tests && python3 -m unittest test_metrics -v`).
Expected: FAIL — `ModuleNotFoundError: No module named 'metrics'` / `AttributeError`.

- [ ] **Step 4: Write minimal implementation**

Create `synth/metrics.py`:

```python
#!/usr/bin/env python3
"""Parse jcore synthesis tool output into canonical metric JSON.

All parsers are pure (text -> dict) and individually unit-tested. The CLI at
the bottom wires file reads and writes one canonical JSON per target. Parsing
is best-effort: a missing field yields no metric rather than an error.
"""
import re

# Modules whose per-block area/utilisation we surface (spec). Order is stable
# for deterministic output.
BLOCKS = ["cpu", "decode", "datapath", "mult", "register_file"]


def parse_yosys_stat(text):
    """yosys `stat -liberty` dump -> {module: {"cells": int, "area": float}}.

    Per-module `=== name ===` sections carry "Number of cells" and
    "Chip area for module '\\name'". The top module also prints
    "Chip area for top module" (total incl. submodules) which we prefer for
    the top.
    """
    out = {}
    cur = None
    for line in text.splitlines():
        m = re.match(r"^=== (\S+) ===", line)
        if m:
            cur = m.group(1)
            out.setdefault(cur, {})
            continue
        if cur is None:
            continue
        m = re.search(r"Number of cells:\s+(\d+)", line)
        if m:
            out[cur]["cells"] = int(m.group(1))
            continue
        m = re.search(r"Chip area for top module '\\?(\S+?)':\s+([\d.]+)", line)
        if m:
            out[m.group(1)]["area"] = float(m.group(2))
            continue
        m = re.search(r"Chip area for module '\\?(\S+?)':\s+([\d.]+)", line)
        if m and "area" not in out.get(m.group(1), {}):
            out[m.group(1)]["area"] = float(m.group(2))
    return out
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd synth/tests && python3 -m unittest test_metrics -v`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add synth/metrics.py synth/tests/test_metrics.py synth/tests/fixtures/yosys_stat_asic.txt
git commit -m "feat(synth): yosys stat parser for per-block cells/area"
```

---

## Task 2: OpenSTA report parser (TDD)

**Files:**
- Modify: `synth/metrics.py`
- Modify: `synth/tests/test_metrics.py`
- Create: `synth/tests/fixtures/sta_cpu.txt`

- [ ] **Step 1: Create the STA fixture**

Create `synth/tests/fixtures/sta_cpu.txt` (OpenSTA output at a 20 ns period):

```
Startpoint: u_datapath.reg_q[3] (rising edge-triggered flip-flop)
Endpoint: u_datapath.acc_q[7] (rising edge-triggered flip-flop)
Path Group: virt_clk
Path Type: max

  Delay    Time   Description
---------------------------------------------------------
   0.00    0.00   clock virt_clk (rise edge)
  24.83   24.83   data arrival time
  20.00   20.00   data required time
---------------------------------------------------------
                  slack (VIOLATED) -4.83

wns max -4.83
tns max -52.10

Group                   Internal  Switching    Leakage      Total
                           Power      Power      Power      Power
----------------------------------------------------------------
Sequential              4.10e-03   1.20e-03   3.00e-05   5.33e-03
Combinational           5.00e-03   2.10e-03   4.00e-05   7.24e-03
----------------------------------------------------------------
Total                   9.10e-03   3.30e-03   7.00e-05   1.257e-02
```

- [ ] **Step 2: Write the failing test**

Append to `synth/tests/test_metrics.py`:

```python
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd synth/tests && python3 -m unittest test_metrics.TestStaReport -v`
Expected: FAIL — `AttributeError: module 'metrics' has no attribute 'parse_sta_report'`.

- [ ] **Step 4: Write minimal implementation**

Append to `synth/metrics.py`:

```python
def parse_sta_report(text, period_ns):
    """OpenSTA stdout -> {"wns","tns","fmax_mhz","power_mw"} (keys present only
    when parsed). `report_wns`/`report_tns` print "wns max -4.83"; take the last
    field so "wns -4.83" and "wns max -4.83" both parse. Fmax is derived from
    the critical path = period - wns. Power total is the last numeric on the
    "Total" row of report_power (Watts -> mW).
    """
    out = {}
    for line in text.splitlines():
        m = re.match(r"^wns\b.*?(-?[\d.]+)\s*$", line)
        if m:
            out["wns"] = float(m.group(1))
        m = re.match(r"^tns\b.*?(-?[\d.]+)\s*$", line)
        if m:
            out["tns"] = float(m.group(1))
        m = re.match(r"^Total\s+.*\s+([\d.eE+-]+)\s*$", line)
        if m:
            try:
                out["power_mw"] = float(m.group(1)) * 1000.0
            except ValueError:
                pass
    if "wns" in out:
        crit = period_ns - out["wns"]  # wns<0 lengthens the path
        if crit > 0:
            out["fmax_mhz"] = 1000.0 / crit
    return out
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd synth/tests && python3 -m unittest test_metrics -v`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add synth/metrics.py synth/tests/test_metrics.py synth/tests/fixtures/sta_cpu.txt
git commit -m "feat(synth): OpenSTA report parser (WNS/TNS/Fmax/power)"
```

---

## Task 3: nextpnr log parser (TDD)

**Files:**
- Modify: `synth/metrics.py`
- Modify: `synth/tests/test_metrics.py`
- Create: `synth/tests/fixtures/nextpnr_ecp5.log`

- [ ] **Step 1: Create the nextpnr fixture**

Create `synth/tests/fixtures/nextpnr_ecp5.log` (matches the lines the existing
workflow greps):

```
Info: Device utilisation:
Info: 	          TRELLIS_COMB:  6789/83640    8%
Info: 	           TRELLIS_FF:  1234/83640    1%
Info: 	         TRELLIS_RAMW:     0/10455    0%
Info: 	               DP16KD:     2/  208    0%
Info: 	           MULT18X18D:     1/  156    0%
Info: 	               ALU54B:     0/   78    0%
Info: 	           TRELLIS_IO:    42/  365   11%
Info: 	              EHXPLLL:     0/    4    0%
Info: Max frequency for clock '$glbnet$clk$TRELLIS_IO_IN': 41.23 MHz (PASS at 50.00 MHz)
Info: Max frequency for clock '$glbnet$clk': 38.90 MHz (PASS at 50.00 MHz)
```

- [ ] **Step 2: Write the failing test**

Append to `synth/tests/test_metrics.py`:

```python
class TestNextpnrLog(unittest.TestCase):
    def test_utilisation_and_hardblocks(self):
        got = metrics.parse_nextpnr_log(read("nextpnr_ecp5.log"))
        self.assertEqual(got["util"]["TRELLIS_COMB"], 6789)
        self.assertEqual(got["util"]["TRELLIS_FF"], 1234)
        self.assertEqual(got["util"]["DP16KD"], 2)
        self.assertEqual(got["util"]["MULT18X18D"], 1)
        self.assertEqual(got["util"]["TRELLIS_IO"], 42)

    def test_fmax_per_clock_keeps_max(self):
        got = metrics.parse_nextpnr_log(read("nextpnr_ecp5.log"))
        # bare '$glbnet$clk' is the canonical clock; cleaned name is "clk"
        self.assertAlmostEqual(got["fmax"]["clk"], 38.90)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd synth/tests && python3 -m unittest test_metrics.TestNextpnrLog -v`
Expected: FAIL — no `parse_nextpnr_log`.

- [ ] **Step 4: Write minimal implementation**

Append to `synth/metrics.py`:

```python
NEXTPNR_BLOCKS = [
    "TRELLIS_COMB", "TRELLIS_FF", "DP16KD", "MULT18X18D",
    "ALU54B", "TRELLIS_IO", "EHXPLLL",
]


def parse_nextpnr_log(text):
    """nextpnr-ecp5 stdout -> {"util": {block: used}, "fmax": {clock: mhz}}.

    Utilisation rows look like "  TRELLIS_COMB:  6789/83640  8%"; we keep the
    `used` number. Fmax rows: "Max frequency for clock '<name>': 41.23 MHz".
    Clock names are cleaned ($glbnet$clk -> clk) and we keep the lowest Fmax
    seen per cleaned name (the binding constraint).
    """
    util, fmax = {}, {}
    for line in text.splitlines():
        for blk in NEXTPNR_BLOCKS:
            m = re.search(r"\b%s:\s+(\d+)/" % re.escape(blk), line)
            if m:
                util[blk] = int(m.group(1))
        m = re.search(r"Max frequency for clock '([^']+)':\s+([\d.]+)\s*MHz", line)
        if m:
            name = m.group(1).split("$")[-1]  # $glbnet$clk -> clk
            val = float(m.group(2))
            if name not in fmax or val < fmax[name]:
                fmax[name] = val
    return {"util": util, "fmax": fmax}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd synth/tests && python3 -m unittest test_metrics -v`
Expected: PASS (7 tests).

- [ ] **Step 6: Commit**

```bash
git add synth/metrics.py synth/tests/test_metrics.py synth/tests/fixtures/nextpnr_ecp5.log
git commit -m "feat(synth): nextpnr-ecp5 log parser (utilisation + Fmax)"
```

---

## Task 4: Canonical builders + CLI (TDD)

**Files:**
- Modify: `synth/metrics.py`
- Modify: `synth/tests/test_metrics.py`

- [ ] **Step 1: Write the failing test**

Append to `synth/tests/test_metrics.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd synth/tests && python3 -m unittest test_metrics.TestBuildCanonical -v`
Expected: FAIL — no `build_asic` / `build_ecp5`.

- [ ] **Step 3: Write minimal implementation**

Append to `synth/metrics.py`:

```python
def _metric(name, unit, value, direction):
    return {"name": name, "unit": unit, "value": value, "dir": direction}


def build_asic(stat, sta, variant, commit):
    """Canonical doc for the Nangate45 ASIC flow."""
    metrics_ = []
    for blk in BLOCKS:
        info = stat.get(blk, {})
        if "area" in info:
            metrics_.append(_metric("%s/area" % blk, "um2", info["area"], "smaller"))
        if "cells" in info:
            metrics_.append(_metric("%s/cells" % blk, "cells", info["cells"], "smaller"))
    if "wns" in sta:
        metrics_.append(_metric("cpu/WNS", "ns", sta["wns"], "bigger"))
    if "tns" in sta:
        metrics_.append(_metric("cpu/TNS", "ns", sta["tns"], "bigger"))
    if "fmax_mhz" in sta:
        metrics_.append(_metric("cpu/Fmax", "MHz", round(sta["fmax_mhz"], 3), "bigger"))
    if "power_mw" in sta:
        metrics_.append(_metric("cpu/power", "mW", round(sta["power_mw"], 4), "smaller"))
    return {"target": "asic-nangate45", "variant": variant,
            "commit": commit, "metrics": metrics_}


def build_ecp5(npr, variant, commit):
    """Canonical doc for the ECP5 FPGA flow."""
    unit_for = {"TRELLIS_COMB": "LUT4", "TRELLIS_FF": "FF"}
    metrics_ = []
    for blk, used in sorted(npr.get("util", {}).items()):
        label = unit_for.get(blk, blk)
        metrics_.append(_metric("cpu/%s" % label, label, used, "smaller"))
    for clk, mhz in sorted(npr.get("fmax", {}).items()):
        metrics_.append(_metric("%s/Fmax" % clk, "MHz", mhz, "bigger"))
    return {"target": "ecp5-lfe5u-85f", "variant": variant,
            "commit": commit, "metrics": metrics_}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd synth/tests && python3 -m unittest test_metrics -v`
Expected: PASS (9 tests).

- [ ] **Step 5: Add the CLI (no new behavior to test — exercised in Step 6)**

Append to `synth/metrics.py`:

```python
def _read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError as e:
        print("WARN: cannot read %s: %s" % (path, e))
        return ""


def main(argv=None):
    import argparse
    import json
    import sys

    p = argparse.ArgumentParser(description="emit canonical synth metrics JSON")
    p.add_argument("--target", required=True, choices=["asic-nangate45", "ecp5-lfe5u-85f"])
    p.add_argument("--variant", default="direct-rom72")
    p.add_argument("--commit", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--stat", help="yosys stat -liberty dump (asic/ecp5)")
    p.add_argument("--sta", help="OpenSTA report (asic)")
    p.add_argument("--nextpnr", help="nextpnr-ecp5 log (ecp5)")
    p.add_argument("--period-ns", type=float, default=20.0)
    a = p.parse_args(argv)

    if a.target == "asic-nangate45":
        stat = parse_yosys_stat(_read(a.stat)) if a.stat else {}
        sta = parse_sta_report(_read(a.sta), a.period_ns) if a.sta else {}
        doc = build_asic(stat, sta, a.variant, a.commit)
    else:
        npr = parse_nextpnr_log(_read(a.nextpnr)) if a.nextpnr else {}
        doc = build_ecp5(npr, a.variant, a.commit)

    if not doc["metrics"]:
        print("WARN: no metrics parsed for %s — writing empty doc" % a.target)
    import os
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as f:
        json.dump(doc, f, indent=2, sort_keys=False)
        f.write("\n")
    print("metrics.py: wrote %d metrics to %s" % (len(doc["metrics"]), a.out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 6: Smoke-test the CLI end to end**

Run from repo root:
```bash
python3 synth/metrics.py --target asic-nangate45 --commit testsha --out /tmp/asic.json \
  --stat synth/tests/fixtures/yosys_stat_asic.txt --sta synth/tests/fixtures/sta_cpu.txt --period-ns 20
python3 -c "import json;d=json.load(open('/tmp/asic.json'));print(len(d['metrics']),'metrics');assert d['target']=='asic-nangate45'"
```
Expected: prints a metrics count > 0 and no assertion error.

- [ ] **Step 7: Commit**

```bash
git add synth/metrics.py synth/tests/test_metrics.py
git commit -m "feat(synth): canonical metric builders + metrics.py CLI"
```

---

## Task 5: Converter to github-action-benchmark format (TDD)

**Files:**
- Create: `synth/to_gha_bench.py`
- Create: `synth/tests/test_to_gha_bench.py`
- Create: `synth/tests/fixtures/canon_asic.json`, `synth/tests/fixtures/canon_ecp5.json`

- [ ] **Step 1: Create canonical-input fixtures**

Create `synth/tests/fixtures/canon_asic.json`:
```json
{
  "target": "asic-nangate45",
  "variant": "direct-rom72",
  "commit": "abc123",
  "metrics": [
    {"name": "cpu/area", "unit": "um2", "value": 48210.0, "dir": "smaller"},
    {"name": "cpu/Fmax", "unit": "MHz", "value": 40.27, "dir": "bigger"}
  ]
}
```

Create `synth/tests/fixtures/canon_ecp5.json`:
```json
{
  "target": "ecp5-lfe5u-85f",
  "variant": "direct-rom72",
  "commit": "abc123",
  "metrics": [
    {"name": "cpu/LUT4", "unit": "LUT4", "value": 6789, "dir": "smaller"},
    {"name": "clk/Fmax", "unit": "MHz", "value": 38.9, "dir": "bigger"}
  ]
}
```

- [ ] **Step 2: Write the failing test**

Create `synth/tests/test_to_gha_bench.py`:

```python
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd synth/tests && python3 -m unittest test_to_gha_bench -v`
Expected: FAIL — no module `to_gha_bench`.

- [ ] **Step 4: Write minimal implementation**

Create `synth/to_gha_bench.py`:

```python
#!/usr/bin/env python3
"""Merge canonical metric JSONs into github-action-benchmark 'custom' inputs.

Splits metrics by direction into two arrays:
  smaller -> customSmallerIsBetter   speed/bigger -> customBiggerIsBetter
Each entry: {"name","unit","value","extra"}. `name` is prefixed with the
target ("asic-nangate45 · cpu/area") so the action's per-metric charts and our
dashboard can group on it; `extra` carries the variant for future faceting.
Output order is sorted by name for deterministic diffs.
"""
import json


def convert(canon_paths):
    size, speed = [], []
    for path in canon_paths:
        with open(path) as f:
            doc = json.load(f)
        target, variant = doc["target"], doc.get("variant", "")
        for m in doc["metrics"]:
            entry = {
                "name": "%s · %s" % (target, m["name"]),
                "unit": m["unit"],
                "value": m["value"],
                "extra": variant,
            }
            (size if m["dir"] == "smaller" else speed).append(entry)
    size.sort(key=lambda e: e["name"])
    speed.sort(key=lambda e: e["name"])
    return size, speed


def main(argv=None):
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("inputs", nargs="+", help="canonical metric JSON files")
    p.add_argument("--size-out", required=True)
    p.add_argument("--speed-out", required=True)
    a = p.parse_args(argv)
    size, speed = convert(a.inputs)
    for path, data in ((a.size_out, size), (a.speed_out, speed)):
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
    print("to_gha_bench.py: %d size, %d speed metrics" % (len(size), len(speed)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd synth/tests && python3 -m unittest test_to_gha_bench -v`
Expected: PASS (2 tests).

- [ ] **Step 6: Run the full Python test suite**

Run from repo root: `cd synth/tests && python3 -m unittest -v`
Expected: PASS (11 tests total).

- [ ] **Step 7: Commit**

```bash
git add synth/to_gha_bench.py synth/tests/test_to_gha_bench.py synth/tests/fixtures/canon_asic.json synth/tests/fixtures/canon_ecp5.json
git commit -m "feat(synth): converter to github-action-benchmark custom format"
```

---

## Task 6: Full-CPU OpenSTA driver script

**Files:**
- Create: `synth/cpu_sta.sh`

This script cannot be unit-tested without the toolchain; it is validated in CI
(Task 8) and via the optional local run below. It mirrors `regression.sh`
Step 8's proven `sta_one` recipe, retargeted from `decode_table` to `cpu`.

- [ ] **Step 1: Write the script**

Create `synth/cpu_sta.sh`:

```bash
#!/usr/bin/env bash
# Full-CPU Nangate45 tech-map + OpenSTA. Extends regression.sh Step 8 (which
# times the decoder unit) to the whole cpu. Best-effort and NON-GATING: if the
# Liberty file or `sta` is unavailable, warn and exit 0 so callers (metrics.py)
# simply emit no ASIC timing metrics.
#
# Precondition: synth/cpu_synth.sh asic has written build/cpu_asic.v.
# Outputs: build/cpu_asic_mapped.v, build/cpu_asic_sta.rpt
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/build"; mkdir -p "$OUT"

NANGATE_LIB="${NANGATE_LIB:-/opt/nangate45/nangate45.lib}"
TARGET_MHZ="${ECP5_TARGET_MHZ:-50}"
PERIOD_NS="$(awk -v m="$TARGET_MHZ" 'BEGIN{printf "%.4f", 1000.0/m}')"

if [ ! -f "$OUT/cpu_asic.v" ]; then
  echo "WARN: $OUT/cpu_asic.v missing — run synth/cpu_synth.sh asic first; skipping STA" >&2
  exit 0
fi
if ! command -v sta >/dev/null 2>&1; then
  echo "WARN: opensta (sta) not installed — skipping ASIC STA" >&2
  exit 0
fi
if [ ! -f "$NANGATE_LIB" ]; then
  echo "WARN: Nangate45 Liberty not at $NANGATE_LIB — skipping ASIC STA" >&2
  exit 0
fi

# 1) Tech-map the generic netlist to Nangate45 (dfflibmap + abc), as Step 7 does.
yosys -p "read_verilog $OUT/cpu_asic.v; dfflibmap -liberty $NANGATE_LIB; abc -liberty $NANGATE_LIB; stat -liberty $NANGATE_LIB; write_verilog $OUT/cpu_asic_mapped.v" \
  | tee "$OUT/cpu_asic_mapped_stat.txt"

# 2) Static timing. Virtual clock + real clk on the cpu's clk port at PERIOD_NS.
TCL="$(mktemp)"; trap 'rm -f "$TCL"' EXIT
cat > "$TCL" <<TCL
read_liberty $NANGATE_LIB
read_verilog $OUT/cpu_asic_mapped.v
link_design cpu
create_clock -name virt_clk -period $PERIOD_NS
create_clock -name clk -period $PERIOD_NS [get_ports clk]
set_input_delay  -clock virt_clk 0 [all_inputs]
set_output_delay -clock virt_clk 0 [all_outputs]
report_checks -path_delay max -format short
report_wns
report_tns
report_power
exit
TCL

if ! timeout 120 sta -no_init -no_splash "$TCL" > "$OUT/cpu_asic_sta.rpt" 2>&1; then
  echo "WARN: OpenSTA did not complete (timeout/fatal) — ASIC timing absent. See $OUT/cpu_asic_sta.rpt" >&2
  tail -20 "$OUT/cpu_asic_sta.rpt" | sed 's/^/    /' >&2
  exit 0
fi
echo "cpu_sta.sh: OK (period ${PERIOD_NS}ns / ${TARGET_MHZ}MHz). Report: $OUT/cpu_asic_sta.rpt"
```

- [ ] **Step 2: Make it executable and lint it**

Run:
```bash
chmod +x synth/cpu_sta.sh
bash -n synth/cpu_sta.sh && echo "syntax OK"
```
Expected: `syntax OK`. (If `shellcheck` is installed: `shellcheck synth/cpu_sta.sh` should report no errors.)

- [ ] **Step 3: Verify the no-toolchain guard exits 0**

Run (simulates a dev box without OpenSTA, with a stub build dir):
```bash
mkdir -p build && echo "// stub" > build/cpu_asic.v
NANGATE_LIB=/nonexistent PATH=/usr/bin:/bin synth/cpu_sta.sh; echo "exit=$?"
```
Expected: prints a `WARN:` about a missing tool/Liberty and `exit=0`.

- [ ] **Step 4: Commit**

```bash
git add synth/cpu_sta.sh
git commit -m "feat(synth): full-CPU Nangate45 map + OpenSTA driver (non-gating)"
```

---

## Task 7: Custom dashboard

**Files:**
- Create: `dashboard/index.html`
- Create: `dashboard/app.js`
- Create: `dashboard/fixtures/data.js`

The action's `window.BENCHMARK_DATA` shape (per github-action-benchmark):
`{ lastUpdate, repoUrl, entries: { "<benchmark name>": [ { commit:{id,timestamp,message,url}, date, benches:[ {name,unit,value,extra} ] }, ... ] } }`.

- [ ] **Step 1: Create a fixture data.js (two commits of history)**

Create `dashboard/fixtures/data.js`:

```javascript
window.BENCHMARK_DATA = {
  lastUpdate: 1700000000000,
  repoUrl: "https://github.com/owner/jcore-cpu",
  entries: {
    "synth-size": [
      { commit: { id: "aaa1111", message: "first", timestamp: "2026-06-10T00:00:00Z", url: "#" }, date: 1700000000000,
        benches: [
          { name: "asic-nangate45 · cpu/area", unit: "um2", value: 49000, extra: "direct-rom72" },
          { name: "asic-nangate45 · datapath/area", unit: "um2", value: 20100, extra: "direct-rom72" },
          { name: "asic-nangate45 · decode/area", unit: "um2", value: 11200, extra: "direct-rom72" },
          { name: "ecp5-lfe5u-85f · cpu/LUT4", unit: "LUT4", value: 6900, extra: "direct-rom72" } ] },
      { commit: { id: "bbb2222", message: "second", timestamp: "2026-06-11T00:00:00Z", url: "#" }, date: 1700086400000,
        benches: [
          { name: "asic-nangate45 · cpu/area", unit: "um2", value: 48210, extra: "direct-rom72" },
          { name: "asic-nangate45 · datapath/area", unit: "um2", value: 19880, extra: "direct-rom72" },
          { name: "asic-nangate45 · decode/area", unit: "um2", value: 11020, extra: "direct-rom72" },
          { name: "ecp5-lfe5u-85f · cpu/LUT4", unit: "LUT4", value: 6789, extra: "direct-rom72" } ] }
    ],
    "synth-speed": [
      { commit: { id: "aaa1111", message: "first", timestamp: "2026-06-10T00:00:00Z", url: "#" }, date: 1700000000000,
        benches: [ { name: "asic-nangate45 · cpu/Fmax", unit: "MHz", value: 39.5, extra: "direct-rom72" },
                   { name: "ecp5-lfe5u-85f · clk/Fmax", unit: "MHz", value: 38.0, extra: "direct-rom72" } ] },
      { commit: { id: "bbb2222", message: "second", timestamp: "2026-06-11T00:00:00Z", url: "#" }, date: 1700086400000,
        benches: [ { name: "asic-nangate45 · cpu/Fmax", unit: "MHz", value: 40.27, extra: "direct-rom72" },
                   { name: "ecp5-lfe5u-85f · clk/Fmax", unit: "MHz", value: 38.9, extra: "direct-rom72" } ] }
    ]
  }
};
```

- [ ] **Step 2: Create the dashboard page**

Create `dashboard/index.html`:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>jcore-cpu — Synthesis Metrics</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
  <style>
    body { font-family: system-ui, sans-serif; margin: 1.5rem; color: #1b1b1b; }
    h1 { font-size: 1.4rem; } h2 { font-size: 1.1rem; margin-top: 2rem; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); gap: 1rem; }
    .card { border: 1px solid #ddd; border-radius: 8px; padding: 0.75rem; }
    table { border-collapse: collapse; } td, th { border: 1px solid #ddd; padding: 4px 8px; }
    .muted { color: #666; font-size: 0.85rem; }
  </style>
</head>
<body>
  <h1>jcore-cpu synthesis metrics</h1>
  <p class="muted">Per-commit FPGA (ECP5) &amp; ASIC (Nangate45) trends. Raw per-metric charts:
    <a href="./bench-size/">size</a> · <a href="./bench-speed/">speed</a>.</p>

  <h2>Trends</h2>
  <div id="trends" class="grid"></div>

  <h2>Per-block area (ASIC, latest)</h2>
  <div class="card" style="max-width:640px"><canvas id="perblock"></canvas></div>

  <h2>Variant comparison (latest)</h2>
  <div id="variants"></div>

  <!-- In production these two are bench-{size,speed}/data.js; locally, the fixture. -->
  <script>window.__SIZE__ = null; window.__SPEED__ = null;</script>
  <script src="./bench-size/data.js" onload="window.__SIZE__=window.BENCHMARK_DATA" onerror="loadFixture()"></script>
  <script src="./bench-speed/data.js" onload="window.__SPEED__=window.BENCHMARK_DATA"></script>
  <script src="./app.js"></script>
</body>
</html>
```

- [ ] **Step 3: Create the dashboard logic**

Create `dashboard/app.js`:

```javascript
// Renders three views from github-action-benchmark BENCHMARK_DATA objects.
// __SIZE__ / __SPEED__ are the two suites (smaller-better / bigger-better).

function loadFixture() {
  // Local dev fallback: load the committed fixture into both suites.
  var s = document.createElement("script");
  s.src = "./fixtures/data.js";
  s.onload = function () { window.__SIZE__ = window.BENCHMARK_DATA; window.__SPEED__ = window.BENCHMARK_DATA; render(); };
  document.body.appendChild(s);
}

function seriesByName(data) {
  // -> { metricName: [ {x: date, y: value, commit} ] }
  var out = {};
  if (!data || !data.entries) return out;
  Object.keys(data.entries).forEach(function (suite) {
    data.entries[suite].forEach(function (run) {
      run.benches.forEach(function (b) {
        (out[b.name] = out[b.name] || []).push({ x: run.date, y: b.value, commit: run.commit });
      });
    });
  });
  return out;
}

function lineCard(parent, title, points, unit) {
  var card = document.createElement("div"); card.className = "card";
  var cv = document.createElement("canvas"); card.appendChild(cv); parent.appendChild(card);
  new Chart(cv, {
    type: "line",
    data: { datasets: [{ label: title + " (" + unit + ")", data: points, tension: 0.2, pointRadius: 3 }] },
    options: { parsing: false, scales: { x: { type: "linear", ticks: { callback: function (v) { return new Date(v).toISOString().slice(0, 10); } } } },
               plugins: { legend: { display: true }, tooltip: { callbacks: { title: function (it) { return new Date(it[0].parsed.x).toISOString().slice(0, 10); } } } } }
  });
}

function render() {
  var size = seriesByName(window.__SIZE__), speed = seriesByName(window.__SPEED__);
  var all = Object.assign({}, size, speed);
  var trends = document.getElementById("trends");
  Object.keys(all).sort().forEach(function (name) {
    var unit = name.indexOf("Fmax") >= 0 ? "MHz" : (name.indexOf("area") >= 0 ? "um2" : "");
    lineCard(trends, name, all[name].sort(function (a, b) { return a.x - b.x; }), unit);
  });
  renderPerBlock(size);
  renderVariants(all);
}

function latestBenches(data) {
  // newest run across the size suite -> {name: value}
  var best = null;
  if (data && data.entries) Object.keys(data.entries).forEach(function (s) {
    data.entries[s].forEach(function (run) { if (!best || run.date > best.date) best = run; });
  });
  var map = {}; if (best) best.benches.forEach(function (b) { map[b.name] = b; });
  return map;
}

function renderPerBlock(size) {
  var latest = latestBenches(window.__SIZE__);
  var blocks = ["decode", "datapath", "mult", "register_file"];
  var vals = blocks.map(function (b) { var k = "asic-nangate45 · " + b + "/area"; return latest[k] ? latest[k].value : 0; });
  new Chart(document.getElementById("perblock"), {
    type: "bar",
    data: { labels: blocks, datasets: [{ label: "area (um2)", data: vals }] },
    options: { plugins: { legend: { display: false } } }
  });
}

function renderVariants(all) {
  // Group latest value per (variant, metric). With one variant today this is a
  // single column; it grows as variants are added.
  var rows = {}, variants = {};
  Object.keys(all).forEach(function (name) {
    var pts = all[name]; if (!pts.length) return;
    var last = pts[pts.length - 1];
    // variant carried on bench.extra is not in the point; fall back to "current".
    var v = "current"; variants[v] = true;
    (rows[name] = rows[name] || {})[v] = last.y;
  });
  var vlist = Object.keys(variants);
  var html = "<table><tr><th>metric</th>" + vlist.map(function (v) { return "<th>" + v + "</th>"; }).join("") + "</tr>";
  Object.keys(rows).sort().forEach(function (name) {
    html += "<tr><td>" + name + "</td>" + vlist.map(function (v) { return "<td>" + (rows[name][v] != null ? rows[name][v] : "—") + "</td>"; }).join("") + "</tr>";
  });
  html += "</table>";
  document.getElementById("variants").innerHTML = html;
}

// If the production data.js files loaded, render now; otherwise the size
// onerror handler already triggered loadFixture() which calls render().
if (window.__SIZE__ || window.__SPEED__) render();
```

- [ ] **Step 4: Verify the dashboard renders against the fixture**

Run from repo root:
```bash
mkdir -p /tmp/dashtest && cp dashboard/index.html dashboard/app.js /tmp/dashtest/ \
  && mkdir -p /tmp/dashtest/fixtures && cp dashboard/fixtures/data.js /tmp/dashtest/fixtures/ \
  && cd /tmp/dashtest && python3 -m http.server 8099 >/dev/null 2>&1 & echo "serving pid $!"
```
Then either open `http://localhost:8099/` in a browser and confirm three
sections render (trends line charts, per-block bar, variant table), or run a
headless check:
```bash
sleep 1; curl -s http://localhost:8099/ | grep -q 'jcore-cpu synthesis metrics' && echo "page served OK"
kill %1 2>/dev/null || true
```
Expected: `page served OK` (and, if opened in a browser, no JS console errors;
the `bench-size/data.js` 404 is expected and falls back to the fixture).

- [ ] **Step 5: Commit**

```bash
git add dashboard/
git commit -m "feat(synth): custom Chart.js metrics dashboard + fixture"
```

---

## Task 8: Wire into synth-cpu.yml

**Files:**
- Modify: `.github/workflows/synth-cpu.yml`

- [ ] **Step 1: Add the STA period env var**

In `.github/workflows/synth-cpu.yml`, the existing `env:` block already sets
`ECP5_TARGET_MHZ: "50"`. No change needed — `cpu_sta.sh` reads it.

- [ ] **Step 2: Add STA + emit steps to `synth-asic`**

In the `synth-asic` job, immediately AFTER the existing
"Report cell/area stats" step and BEFORE "Upload artifacts", insert:

```yaml
      - name: Full-CPU STA (Nangate45 + OpenSTA)
        run: synth/cpu_sta.sh   # non-gating; writes build/cpu_asic_sta.rpt
      - name: Emit ASIC metrics
        run: |
          set -euo pipefail
          # Hierarchical area stat for per-block numbers (separate from the
          # gating netlist read). cpu_asic_mapped.v is Nangate45-mapped.
          yosys -p "read_verilog build/cpu_asic_mapped.v; stat -liberty $NANGATE_LIB" \
            | tee build/asic_area_stat.txt
          period_ns=$(awk -v m="${ECP5_TARGET_MHZ}" 'BEGIN{printf "%.4f",1000.0/m}')
          python3 synth/metrics.py --target asic-nangate45 \
            --commit "${GITHUB_SHA}" --out synth/metrics/asic-nangate45.json \
            --stat build/asic_area_stat.txt --sta build/cpu_asic_sta.rpt \
            --period-ns "$period_ns"
        env:
          NANGATE_LIB: /opt/nangate45/nangate45.lib
      - name: Upload metrics
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: metrics-asic
          path: synth/metrics/*.json
          retention-days: 14
```

- [ ] **Step 3: Add emit step to `synth-ecp5`**

In the `synth-ecp5` job, AFTER "Report Fmax + utilisation" and BEFORE
"Upload artifacts", insert:

```yaml
      - name: Emit ECP5 metrics
        run: |
          set -euo pipefail
          python3 synth/metrics.py --target ecp5-lfe5u-85f \
            --commit "${GITHUB_SHA}" --out synth/metrics/ecp5-lfe5u-85f.json \
            --nextpnr build/nextpnr.log
      - name: Upload metrics
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: metrics-ecp5
          path: synth/metrics/*.json
          retention-days: 14
```

- [ ] **Step 4: Add the `publish-pages` job**

Append this job at the end of `.github/workflows/synth-cpu.yml` (same
indentation level as `synth-asic:`). The repo's `${{ github.repository }}` is
`<owner>/jcore-cpu`; the Pages URL is `https://<owner>.github.io/jcore-cpu`.

```yaml
  publish-pages:
    needs: [synth-asic, synth-ecp5]
    if: always()
    runs-on: ubuntu-24.04
    permissions:
      contents: read
      pages: write
      id-token: write
      pull-requests: write
    environment:
      name: github-pages
      url: ${{ steps.deploy.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - name: Download ASIC metrics
        uses: actions/download-artifact@v4
        with: { name: metrics-asic, path: metrics-in }
        continue-on-error: true
      - name: Download ECP5 metrics
        uses: actions/download-artifact@v4
        with: { name: metrics-ecp5, path: metrics-in }
        continue-on-error: true
      - name: Build action inputs
        run: |
          set -euo pipefail
          mkdir -p site/bench-size site/bench-speed
          python3 synth/to_gha_bench.py metrics-in/*.json \
            --size-out build-size.json --speed-out build-speed.json
          ls -l build-size.json build-speed.json
      - name: Bootstrap prior history from the live site
        run: |
          set -euo pipefail
          base="https://${GITHUB_REPOSITORY_OWNER}.github.io/${GITHUB_REPOSITORY##*/}"
          for kind in size speed; do
            url="$base/bench-$kind/benchmark-data.json"
            if curl -fsSL --head "$url" >/dev/null 2>&1; then
              curl -fsSL "$url" -o "site/bench-$kind/benchmark-data.json"
              echo "fetched prior $kind history"
            else
              echo '{}' > "site/bench-$kind/benchmark-data.json"
              echo "no prior $kind history (first run)"
            fi
          done
      - name: Append size suite
        uses: benchmark-action/github-action-benchmark@v1
        with:
          name: synth-size
          tool: customSmallerIsBetter
          output-file-path: build-size.json
          external-data-json-path: site/bench-size/benchmark-data.json
          benchmark-data-dir-path: site/bench-size
          alert-threshold: "110%"
          comment-on-alert: true
          fail-on-alert: false
          auto-push: false
          github-token: ${{ secrets.GITHUB_TOKEN }}
      - name: Append speed suite
        uses: benchmark-action/github-action-benchmark@v1
        with:
          name: synth-speed
          tool: customBiggerIsBetter
          output-file-path: build-speed.json
          external-data-json-path: site/bench-speed/benchmark-data.json
          benchmark-data-dir-path: site/bench-speed
          alert-threshold: "110%"
          comment-on-alert: true
          fail-on-alert: false
          auto-push: false
          github-token: ${{ secrets.GITHUB_TOKEN }}
      - name: Assemble site
        run: |
          set -euo pipefail
          for kind in size speed; do
            echo "window.BENCHMARK_DATA = $(cat site/bench-$kind/benchmark-data.json)" \
              > "site/bench-$kind/data.js"
          done
          cp dashboard/index.html dashboard/app.js site/
          mkdir -p site/fixtures && cp dashboard/fixtures/data.js site/fixtures/
      - name: Upload Pages artifact
        if: github.event_name == 'push'
        uses: actions/upload-pages-artifact@v3
        with: { path: site }
      - name: Deploy to GitHub Pages
        id: deploy
        if: github.event_name == 'push'
        uses: actions/deploy-pages@v4
```

- [ ] **Step 5: Validate the workflow YAML**

Run from repo root:
```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/synth-cpu.yml')); print('YAML OK')"
```
Expected: `YAML OK`. (If `actionlint` is available, run it; expect no errors.)

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/synth-cpu.yml
git commit -m "ci(synth): emit metrics + publish-pages job (branch-less Pages)"
```

---

## Task 9: Docs + manual Pages enablement note

**Files:**
- Modify: `synth/README.md`

- [ ] **Step 1: Append a metrics section to `synth/README.md`**

Add this section to `synth/README.md`:

```markdown
## Synthesis metrics dashboard

Every push to `master` publishes FPGA/ASIC synthesis metrics to GitHub Pages
(`https://<owner>.github.io/jcore-cpu`). PRs get a regression comment but do not
update the published history. The site is the database — history is bootstrapped
each run by fetching the prior `bench-{size,speed}/benchmark-data.json` back
from the live site (no `gh-pages` branch).

One-time setup: repo Settings → Pages → Source = "GitHub Actions".

Pipeline (in `.github/workflows/synth-cpu.yml`):
1. `synth-asic` / `synth-ecp5` run the existing synth flow, then
   `synth/cpu_sta.sh` (full-CPU OpenSTA, ASIC only) and `synth/metrics.py`
   emit `synth/metrics/<target>.json`.
2. `publish-pages` merges them via `synth/to_gha_bench.py`, runs
   `github-action-benchmark` (size = smaller-better, speed = bigger-better),
   and on `master` deploys the dashboard via the Actions Pages pipeline.

Reproduce a metric locally (requires the CI image toolchain):
```bash
make -C decode generate
for f in core/mult core/datapath decode/decode_core; do \
  LD_LIBRARY_PATH='' perl ../jcore-soc/tools/v2p < "$f.vhm" > "$f.vhd"; done
synth/cpu_synth.sh asic && synth/cpu_sta.sh
python3 synth/metrics.py --target asic-nangate45 --commit local \
  --out /tmp/m.json --stat build/cpu_asic_mapped_stat.txt --sta build/cpu_asic_sta.rpt --period-ns 20
```

Run the parser unit tests (no toolchain needed):
```bash
cd synth/tests && python3 -m unittest -v
```
```

- [ ] **Step 2: Verify the doc reproduction commands are internally consistent**

Run from repo root: `cd synth/tests && python3 -m unittest -v`
Expected: PASS (11 tests) — confirms the documented test command works.

- [ ] **Step 3: Commit**

```bash
git add synth/README.md
git commit -m "docs(synth): document the metrics dashboard pipeline"
```

---

## Post-Implementation: Manual Steps (cannot be automated)

These require repo-admin action and a real CI run; note them in the PR description:

1. **Enable Pages:** repo Settings → Pages → Source = **GitHub Actions**.
2. **First run is empty:** the very first master push creates the history
   (`benchmark-data.json` = `{}` → one commit). The dashboard is meaningful
   from the second data point on.
3. **Verify the published site** loads at `https://<owner>.github.io/jcore-cpu`
   after the first master deploy, and that a PR touching the core produces a
   benchmark comment.

---

## Self-Review Notes (addressed)

- **Spec coverage:** ASIC cell/area/WNS/TNS/Fmax/power → Tasks 1,2,4; ECP5
  util/hardblocks/Fmax → Tasks 3,4; per-block area → Task 1/4 (`BLOCKS`);
  converter split by direction → Task 5; branch-less Pages + curl bootstrap →
  Task 8; custom dashboard (trends/per-block/variants) → Task 7; full-CPU STA
  extension → Task 6; non-gating policy → guards in Tasks 6 & 4 CLI; docs →
  Task 9.
- **Naming consistency:** `parse_yosys_stat`, `parse_sta_report`,
  `parse_nextpnr_log`, `build_asic`, `build_ecp5`, `convert` are used
  identically across plan and tests. Metric names use the `<block>/<metric>`
  convention everywhere; converter prefixes `"<target> · "`.
- **Known approximations (from spec risks):** per-block area depends on a
  hierarchical netlist — if `synth`/`abc` flattens `cpu_asic_mapped.v`,
  per-block rows are absent and only `cpu/area` appears (parser handles missing
  modules gracefully; no failure). Power and nextpnr Fmax are estimates; the
  110% non-failing threshold absorbs run-to-run noise.
```
