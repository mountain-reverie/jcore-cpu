#!/usr/bin/env python3
"""Parse jcore synthesis tool output into canonical metric JSON.

All parsers are pure (text -> dict) and individually unit-tested. The CLI at
the bottom wires file reads and writes one canonical JSON per target. Parsing
is best-effort: a missing field yields no metric rather than an error.
"""
import re

# Canonical blocks whose per-block area/utilisation we surface (spec). Order is
# stable for deterministic output. "shifter" became its own block when the
# barrel shifter was extracted from datapath into entity work.shifter.
BLOCKS = ["cpu", "decode", "datapath", "mult", "register_file", "shifter"]


def parse_yosys_stat(text):
    """yosys `stat -liberty` dump -> {module: {"cells": int, "area": float}}.

    Faithful per-section parse, keyed by the RAW module name as yosys prints it.
    Under `synth -top cpu` (no -flatten) the ghdl-yosys plugin keeps the RTL
    hierarchy, so names are GHDL-mangled: `datapath_Bstru`, `shifter_Bcomb`,
    `register_file_Btwo_bank_5_21_32`, etc. (entity `_B` architecture). The
    trailing `=== design hierarchy ===` pseudo-section carries the recursive
    total; it is captured under its own key (the header is matched in full so it
    does NOT bleed its total into the previous real module). Use aggregate_blocks
    to roll these raw modules up to BLOCKS.

    Each section carries "Number of cells" and "Chip area for module '\\name'".
    The top module also prints "Chip area for top module" (total incl.
    submodules) which we prefer for the top.
    """
    out = {}
    cur = None
    for line in text.splitlines():
        m = re.match(r"^=== (.+?) ===\s*$", line)
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


def _canonical(module):
    """GHDL-mangled module name -> base entity. Strips the `_B<arch>` suffix the
    ghdl-yosys plugin appends: `datapath_Bstru` -> `datapath`,
    `register_file_Btwo_bank_5_21_32` -> `register_file`, `shifter_Bcomb` ->
    `shifter`. Names with no `_B` (e.g. `cpu`) pass through unchanged."""
    return module.split("_B", 1)[0]


def _block_for(base):
    """Map a base entity name to the BLOCK that owns it: an exact match, or a
    `block_` prefix so a block's nested sub-modules fold into it (decode_core /
    decode_table -> decode). `cpu` is excluded here; it is the whole-design
    total, handled by aggregate_blocks, not the thin top-level glue module."""
    for blk in BLOCKS:
        if blk == "cpu":
            continue
        if base == blk or base.startswith(blk + "_"):
            return blk
    return None


def aggregate_blocks(stat):
    """Roll a faithful per-module stat (parse_yosys_stat) up to BLOCKS.

    Each block sums its own module plus any nested sub-modules (so `decode`
    includes decode_core + decode_table). Sibling blocks that nest inside
    another (register_file, shifter live under datapath) stay separate — they
    are their own BLOCKS, and yosys counts each module's OWN cells only, so the
    per-block sums partition the design without double-counting. `cpu` is the
    whole-design total: cells from the `design hierarchy` recursive count (else
    the sum of all module cells), area from `Chip area for top module`.
    """
    agg = {}
    total_cells = 0
    for mod, info in stat.items():
        if mod == "design hierarchy":
            continue
        if "cells" in info:
            total_cells += info["cells"]
        blk = _block_for(_canonical(mod))
        if blk is None:
            continue
        d = agg.setdefault(blk, {})
        if "cells" in info:
            d["cells"] = d.get("cells", 0) + info["cells"]
        if "area" in info:
            d["area"] = round(d.get("area", 0.0) + info["area"], 6)
    dh = stat.get("design hierarchy", {})
    cpu = agg.setdefault("cpu", {})
    cpu["cells"] = dh.get("cells", total_cells)
    top = stat.get("cpu", {})
    if "area" in top:
        cpu["area"] = top["area"]
    return agg


def parse_sta_report(text, period_ns):
    """OpenSTA stdout -> {"wns","tns","fmax_mhz","power_mw"} (keys present only
    when parsed). `report_wns`/`report_tns` print "wns max -4.83"; take the last
    field so "wns -4.83" and "wns max -4.83" both parse. Fmax is derived from
    the critical path = period - wns. Power total comes from report_power's
    "Total" row (Watts -> mW): its columns are internal/switching/leakage/total
    and a trailing percentage, e.g. "Total 2.94e-03 1.80e-03 3.03e-04 5.04e-03
    100.0%". We take the last numeric column, skipping a trailing "%" token
    (older OpenSTA omits the percentage, so both formats parse).
    """
    out = {}
    for line in text.splitlines():
        m = re.match(r"^wns\b.*?(-?[\d.eE+-]+)\s*$", line)
        if m:
            out["wns"] = float(m.group(1))
        m = re.match(r"^tns\b.*?(-?[\d.eE+-]+)\s*$", line)
        if m:
            out["tns"] = float(m.group(1))
        if re.match(r"^Total\s", line):
            for tok in reversed(line.split()[1:]):
                if tok.endswith("%"):
                    continue  # trailing percentage column, not the wattage
                try:
                    out["power_mw"] = float(tok) * 1000.0
                    break
                except ValueError:
                    break  # non-numeric where the total should be — give up
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


NEXTPNR_ICE40_BLOCKS = [
    "ICESTORM_LC", "ICESTORM_RAM", "ICESTORM_DSP", "ICESTORM_SPRAM",
    "SB_IO", "SB_GB",
]


def parse_nextpnr_ice40_log(text):
    """nextpnr-ice40 stdout -> {"util": {block: used}, "fmax": {clock: mhz}}.

    Utilisation rows look like "  ICESTORM_LC:  6789/ 5280  128%"; we keep the
    `used` number. On iCE40 a logic cell (ICESTORM_LC) holds one LUT4 + one FF,
    so the up5k "5,280 LUT4" budget is the LC count — that is what build_ice40
    surfaces as cpu/SB_LUT4. Fmax rows reuse the ECP5 format; clock names are
    cleaned ($glbnet$clk -> clk) and the lowest per name is kept (the binding
    post-route constraint, matching the gate's tail behaviour).
    """
    util, fmax = {}, {}
    for line in text.splitlines():
        for blk in NEXTPNR_ICE40_BLOCKS:
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


def build_asic(stat, sta, variant, commit, block_stat=None, target="asic-nangate45"):
    """Canonical doc for the Nangate45 ASIC flow.

    `stat` is the primary (flattened) mapped stat: it sources the `cpu` total
    area/cells — the long-running series — so that series stays continuous.
    `block_stat`, when given, is a HIERARCHICAL mapped stat (modules kept) used
    only for the per-block decode/datapath/mult/register_file/shifter breakdown;
    the flattened netlist the timing flow produces has a single `cpu` module and
    cannot attribute per block. With no block_stat, per-block falls back to
    `stat` (correct only if `stat` itself is hierarchical, as in the tests)."""
    metrics_ = []
    cpu_blocks = aggregate_blocks(stat)
    per_block = aggregate_blocks(block_stat) if block_stat is not None else cpu_blocks
    for blk in BLOCKS:
        info = cpu_blocks.get(blk, {}) if blk == "cpu" else per_block.get(blk, {})
        if "area" in info:
            metrics_.append(_metric("%s/area" % blk, "um2", info["area"], "smaller"))
        if "cells" in info:
            metrics_.append(_metric("%s/cells" % blk, "cells", info["cells"], "smaller"))
    # Timing is labelled "(relative)": the CI ASIC flow is non-timing-driven
    # generic synth on an academic slow-corner library with no buffering,
    # placement, or parasitics, so the absolute numbers are NOT real silicon
    # frequencies — only a regression signal. (Real 45nm would clock far higher.)
    #
    # WNS/TNS are reported as positive VIOLATION magnitudes (max(0, -slack)),
    # smaller-is-better, NOT raw negative slack. github-action-benchmark's
    # regression ratio (prev/curr) is sign-broken for negative values, so raw
    # slack made a timing *improvement* (e.g. -3.34 -> -2.74 ns) false-alarm as a
    # 1.22x regression. As a violation magnitude the same improvement is
    # 3.34 -> 2.74 ns (a real decrease) and compares correctly; 0 means timing met.
    if "wns" in sta:
        metrics_.append(_metric("cpu/WNS violation (relative)", "ns",
                                round(max(0.0, -sta["wns"]), 3), "smaller"))
    if "tns" in sta:
        metrics_.append(_metric("cpu/TNS violation (relative)", "ns",
                                round(max(0.0, -sta["tns"]), 3), "smaller"))
    if "fmax_mhz" in sta:
        metrics_.append(_metric("cpu/Fmax (relative)", "MHz", round(sta["fmax_mhz"], 3), "bigger"))
    if "power_mw" in sta:
        metrics_.append(_metric("cpu/power", "mW", round(sta["power_mw"], 4), "smaller"))
    return {"target": target, "variant": variant,
            "commit": commit, "metrics": metrics_}


def parse_nextpnr_fmax(text):
    """Final (post-route) Fmax in MHz from a nextpnr log: the value on the LAST
    'Max frequency for clock' line. nextpnr prints an early placement estimate
    and a final post-route value for the same clock; the last line is the final
    one — matching the CI gate's `tail -1` extraction. Returns float or None.
    """
    val = None
    for line in text.splitlines():
        m = re.search(r"Max frequency for clock '[^']+':\s+([\d.]+)\s*MHz", line)
        if m:
            val = float(m.group(1))
    return val


def build_ecp5(util, fmax_rep, fmax_bare, variant, commit):
    """Canonical doc for the ECP5 FPGA flow.

    util: {block: used} from the bare-cpu nextpnr log (LUT/FF/hard blocks).
    fmax_rep: representative Fmax (MHz) from the cpu_timing_top harness P&R —
              the number the CI gate measures. fmax_bare: the bare-cpu Fmax,
              depressed by the unconstrained-IO artifact. Both surfaced, labelled.
    """
    unit_for = {"TRELLIS_COMB": "LUT4", "TRELLIS_FF": "FF"}
    metrics_ = []
    for blk, used in sorted(util.items()):
        label = unit_for.get(blk, blk)
        metrics_.append(_metric("cpu/%s" % label, label, used, "smaller"))
    if fmax_rep is not None:
        metrics_.append(_metric("cpu/Fmax (representative)", "MHz", round(fmax_rep, 2), "bigger"))
    if fmax_bare is not None:
        metrics_.append(_metric("cpu/Fmax (IO-unconstrained)", "MHz", round(fmax_bare, 2), "bigger"))
    return {"target": "ecp5-lfe5u-85f", "variant": variant,
            "commit": commit, "metrics": metrics_}


# nextpnr-ice40 utilisation block -> canonical series name. ICESTORM_LC is the
# logic-cell count, which on up5k IS the "5,280 LUT4" budget, so it surfaces as
# the cpu/SB_LUT4 series the dashboard tracks. nextpnr folds FFs into LCs, so
# there is no separate SB_DFF figure on this target.
ICE40_CANON = [
    ("ICESTORM_LC", "SB_LUT4"),
    ("ICESTORM_RAM", "EBR"),
    ("ICESTORM_DSP", "SB_MAC16"),
]


def build_ice40(util, fmax_rep, variant, commit):
    """Canonical doc for the iCE40 up5k FPGA flow (cpu_timing_top harness P&R).

    util: {block: used} from the nextpnr-ice40 log. fmax_rep: representative
    Fmax (MHz) from the same P&R, reported (no declared up5k clock yet).
    """
    metrics_ = []
    for blk, label in ICE40_CANON:
        if blk in util:
            metrics_.append(_metric("cpu/%s" % label, label, util[blk], "smaller"))
    if fmax_rep is not None:
        metrics_.append(_metric("cpu/Fmax (representative)", "MHz", round(fmax_rep, 2), "bigger"))
    return {"target": "ice40-up5k", "variant": variant,
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

    p = argparse.ArgumentParser(description="emit canonical synth metrics JSON")
    p.add_argument("--target", required=True,
                   choices=["asic-nangate45", "asic-sky130", "asic-ihp-sg13g2",
                            "asic-sky130-pnr", "asic-ihp-sg13g2-pnr",
                            "ecp5-lfe5u-85f", "ice40-up5k"])
    p.add_argument("--variant", default="direct-rom72")
    p.add_argument("--commit", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--stat", help="yosys stat -liberty dump (asic/ecp5); flattened cpu total")
    p.add_argument("--block-stat", help="hierarchical yosys stat -liberty dump (asic) for per-block area/cells")
    p.add_argument("--sta", help="OpenSTA report (asic)")
    p.add_argument("--nextpnr", help="bare-cpu nextpnr-ecp5 log (util + IO-unconstrained Fmax)")
    p.add_argument("--nextpnr-timing", help="cpu_timing_top harness nextpnr log (representative Fmax)")
    p.add_argument("--nextpnr-ice40", help="nextpnr-ice40 up5k log (util + representative Fmax)")
    p.add_argument("--period-ns", type=float, default=20.0)
    a = p.parse_args(argv)

    if a.target in ("asic-nangate45", "asic-sky130", "asic-ihp-sg13g2"):
        stat = parse_yosys_stat(_read(a.stat)) if a.stat else {}
        block_stat = parse_yosys_stat(_read(a.block_stat)) if a.block_stat else None
        sta = parse_sta_report(_read(a.sta), a.period_ns) if a.sta else {}
        doc = build_asic(stat, sta, a.variant, a.commit,
                         block_stat=block_stat, target=a.target)
    elif a.target == "ice40-up5k":
        parsed = parse_nextpnr_ice40_log(_read(a.nextpnr_ice40)) if a.nextpnr_ice40 else {"util": {}}
        fmax_rep = parse_nextpnr_fmax(_read(a.nextpnr_ice40)) if a.nextpnr_ice40 else None
        doc = build_ice40(parsed.get("util", {}), fmax_rep, a.variant, a.commit)
    else:
        bare = parse_nextpnr_log(_read(a.nextpnr)) if a.nextpnr else {"util": {}}
        fmax_bare = parse_nextpnr_fmax(_read(a.nextpnr)) if a.nextpnr else None
        fmax_rep = parse_nextpnr_fmax(_read(a.nextpnr_timing)) if a.nextpnr_timing else None
        doc = build_ecp5(bare.get("util", {}), fmax_rep, fmax_bare, a.variant, a.commit)

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
