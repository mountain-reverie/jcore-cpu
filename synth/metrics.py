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
