#!/usr/bin/env python3
"""Assert that no MMU_ARCH-gated logic survives into a non-MMU (J1/J2) netlist.

WHY THIS AND NOT CELL COUNT.  The obvious check for "J1/J2 are unaffected by MMU
work" is to diff the post-synthesis cell count.  That check is deterministic for a
given commit but useless as a gate: MEASURED on three commits of the MMU
exception-delivery work, total cell count moved by -453/+401/-305/-430 cells in
both directions from changes that provably leaked no logic.  Adding an
MMU_ARCH-gated field to a shared record, or an architecture-scope signal tied off
under `if not MMU_ARCH generate`, leaves dangling zero-cell wire bits that survive
flatten and steer abc9 (see core/datapath.vhm's wb_grace and g_restore2 notes).
The optimizer then lands somewhere different for reasons unrelated to
correctness, so a cell-count gate fires constantly and means nothing.

What we actually care about is narrower and is decidable: on a non-MMU build,
every MMU-named net must be CONSTANT-DRIVEN, i.e. elaborated away.  A net that
still carries a driver is real logic that escaped its generate.  That is exactly
the failure mode the codebase warns about, and unlike cell count it cannot be
tripped by optimizer re-steering.

Usage:
    synth/cpu_synth.sh timing            # with SYNTH_VARIANT=j1 or j2
    python3 synth/check_mmu_leak.py build/cpu_timing.json

Exit status 0 = clean, 1 = leak found (prints the offending nets).
"""

import json
import re
import sys

# Nets whose names indicate MMU_ARCH-gated state.  Substring match, case
# insensitive.  Add a pattern here whenever MMU work introduces a new signal
# family -- an unlisted name is simply not checked, so the list is the coverage.
MMU_PATTERNS = (
    r"if_fault",
    r"if_exc_captured",
    r"older_unretired",
    r"tlb_exc",
    r"tlb_squash",
    r"tlb_restore",
    r"tlb_fault",
    r"texc_",
    r"squash_ifetch",
    r"squash_arm",
    r"wb_grace",
    r"ma_dslot",
    r"ma_launch",
    r"inst_fault",
    r"id_delay_slot",
)

_PAT = re.compile("|".join(MMU_PATTERNS), re.IGNORECASE)


def leaks(netlist_path):
    """Return (total_matched, list_of_live_nets) for the given yosys JSON."""
    with open(netlist_path) as fh:
        design = json.load(fh)

    total = 0
    live = []
    for module_name, module in design.get("modules", {}).items():
        for net_name, net in module.get("netnames", {}).items():
            if not _PAT.search(net_name):
                continue
            total += 1
            # In yosys JSON a bit is either an int (a real net index) or one of
            # the strings "0"/"1"/"x"/"z" (a constant).  All-constant means the
            # net was elaborated away and carries no logic.
            bits = net.get("bits", [])
            if not all(isinstance(bit, str) for bit in bits):
                live.append((module_name, net_name))
    return total, live


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2

    total, live = leaks(argv[1])

    if live:
        print(f"FAIL: {len(live)} MMU-gated net(s) survived into the non-MMU netlist:")
        for module_name, net_name in live[:40]:
            print(f"    {module_name}  {net_name}")
        if len(live) > 40:
            print(f"    ... and {len(live) - 40} more")
        print()
        print("A live net here means MMU logic escaped its `if MMU_ARCH generate`.")
        print("Check for a signal declared at architecture scope and merely tied")
        print("off under `if not MMU_ARCH generate` -- see core/datapath.vhm's")
        print("wb_grace note for why that is not sufficient.")
        return 1

    print(f"OK: {total} MMU-named net(s) present, all constant-driven (no leak).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
