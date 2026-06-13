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
            out.setdefault(m.group(1), {})["area"] = float(m.group(2))
            continue
        m = re.search(r"Chip area for module '\\?(\S+?)':\s+([\d.]+)", line)
        if m and "area" not in out.get(m.group(1), {}):
            out[m.group(1)]["area"] = float(m.group(2))
    return out


def parse_sta_report(text, period_ns):
    """OpenSTA stdout -> {"wns","tns","fmax_mhz","power_mw"} (keys present only
    when parsed). `report_wns`/`report_tns` print "wns max -4.83"; take the last
    field so "wns -4.83" and "wns max -4.83" both parse. Fmax is derived from
    the critical path = period - wns. Power total is the last numeric on the
    "Total" row of report_power (Watts -> mW).
    """
    out = {}
    for line in text.splitlines():
        m = re.match(r"^wns\b.*?(-?[\d.eE+-]+)\s*$", line)
        if m:
            out["wns"] = float(m.group(1))
        m = re.match(r"^tns\b.*?(-?[\d.eE+-]+)\s*$", line)
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
