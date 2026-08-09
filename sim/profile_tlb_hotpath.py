#!/usr/bin/env python3
"""profile_tlb_hotpath.py -- per-cycle attribution of one TLB-miss fault->resume.

bench_tlb_hotpath.sh answers "how many cycles"; this answers "spent where".
It walks the same VCD, picks one steady-state TSB-hit fault, and prints every
cycle from the faulting instruction to the resumed one, attributing each to the
PC held during it. Instruction text comes from the guard ELF via objdump, so the
listing names real instructions rather than raw addresses.

Cycles are attributed to the PC value the architectural `pc` signal holds during
them. That is a dwell measure, not an issue measure: a PC that stalls shows the
stall folded into its own count, which is exactly what we want for finding where
the time goes. Cycles before the handler's first PC appears are attributed to
hardware exception ENTRY, and those after the handler's last PC to RETURN/RESUME
-- neither is any instruction's fault.

Usage:  sim/profile_tlb_hotpath.py <guard> [vcd]
        (defaults: guard=mmubench, vcd=$TMPDIR/tlb_hotpath_bench.vcd)
Env:    OBJDUMP (default sh2-elf-objdump), NM (default sh2-elf-nm)
"""
import os
import re
import subprocess
import sys

P1 = 0x80000000
guard = sys.argv[1] if len(sys.argv) > 1 else "mmubench"
vcd = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    os.environ.get("TMPDIR", "/tmp"), "tlb_hotpath_bench.vcd")
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
elf = os.path.join(root, "sim", "tests", f"{guard}.elf")
OBJDUMP = os.environ.get("OBJDUMP", "sh2-elf-objdump")
NM = os.environ.get("NM", "sh2-elf-nm")

if not os.path.exists(vcd):
    sys.exit(f"profile: no VCD at {vcd}; run sim/bench_tlb_hotpath.sh first")
if not os.path.exists(elf):
    sys.exit(f"profile: no ELF at {elf}")

# --- symbols: the fast-path bracket, same pair the bench uses ---
syms = {}
for line in subprocess.run([NM, elf], capture_output=True, text=True).stdout.splitlines():
    f = line.split()
    if len(f) == 3:
        syms[f[2]] = int(f[0], 16)
for need in ("_h_common", "_h_slow", "_vbase"):
    if need not in syms:
        sys.exit(f"profile: {need} not in {elf}")
HC, HS, VB = (P1 + syms[s] for s in ("_h_common", "_h_slow", "_vbase"))

# --- disassembly text, keyed by address ---
disasm = {}
dis = subprocess.run([OBJDUMP, "-d", elf], capture_output=True, text=True).stdout
for line in dis.splitlines():
    m = re.match(r"\s*([0-9a-f]+):\s+(?:[0-9a-f]{2} )+\s*\t(.*)", line)
    if m:
        disasm[P1 + int(m.group(1), 16)] = " ".join(m.group(2).split())

# Guards that RUN code from a translated page copy a stub image from its link
# address (u_code_img, in P1) to the page's backing store. objdump only knows
# the link address, so map the copy back or the faulting instruction prints "?".
if "u_code_img" in syms and "u_code_end" in syms:
    img, end = P1 + syms["u_code_img"], P1 + syms["u_code_end"]
    for off in range(0, end - img, 2):
        if img + off in disasm:
            disasm.setdefault(0x00100000 + off, disasm[img + off] + "   [copied stub]")

# --- VCD: architectural pc, plus a couple of context signals ---
ids = {}
want = {"pc[31:0]": "pc", "if_stall": "if_stall", "slot": "slot"}
events = []          # (time, name, value)
t = 0
for line in open(vcd):
    line = line.rstrip("\n")
    if not line:
        continue
    m = re.match(r"\$var \w+ \d+ (\S+) (\S+) \$end", line)
    if m and m.group(2) in want:
        ids[m.group(1)] = want[m.group(2)]
        continue
    if line[0] == "#":
        t = int(line[1:])
        continue
    if line[0] == "b":
        p = line.split()
        if len(p) == 2 and p[1] in ids:
            try:
                events.append((t, ids[p[1]], int(p[0][1:], 2)))
            except ValueError:
                pass
    elif line[0] in "01" and len(line) > 1 and line[1:] in ids:
        events.append((t, ids[line[1:]], int(line[0])))

pcev = [(t, v) for t, n, v in events if n == "pc"]
if len(pcev) < 2:
    sys.exit("profile: no pc[31:0] transitions found in VCD")
stamps = sorted({t for t, _ in pcev if t > 0})
PER = (stamps[1] - stamps[0]) if len(stamps) > 1 else 10_000_000

# --- locate fast-path windows; take a steady-state TSB hit (second half) ---
inh, ent, wins = False, None, []
for t, v in pcev:
    h = HC <= v < HS
    if h and not inh:
        inh, ent = True, t
    elif inh and not h:
        wins.append((ent, t))
        inh = False
if not wins:
    sys.exit("profile: no fast-path visits")
hits = wins[len(wins) // 2:]
if not hits:
    sys.exit("profile: no steady-state hit window")
ent, ext = hits[0]

# fault = last user-code PC before entry; resume = first user-code PC after exit.
#
# `>= ext`, not `> ext`: the redirect lands on the restart PC in the very cycle
# the PC leaves the handler bracket, so a strict `>` skips the restart PC and
# names its SUCCESSOR as the resume point. bench_tlb_hotpath.sh uses the strict
# form, which is why its cycle count includes the restarted instruction's own
# first execute cycle -- the two agree on the number, and this is where that
# last cycle comes from.
pre = [(t, v) for t, v in pcev if t < ent and v < VB]
post = [(t, v) for t, v in pcev if t >= ext and v < VB]
if not pre or not post:
    sys.exit("profile: could not bracket fault->resume")
t_fault, pc_fault = pre[-1]
t_restart, pc_restart = post[0]
# End the timeline where the bench ends it, so both report the same total.
after = [(t, v) for t, v in pcev if t > ext and v < VB]
t_resume, pc_resume = after[0] if after else (t_restart, pc_restart)

# --- per-cycle PC timeline across [t_fault, t_resume] ---
timeline = []                                  # (cycle_index, pc)
cur = pc_fault
idx = {t: v for t, v in pcev}
n = (t_resume - t_fault) // PER
for c in range(n):
    tt = t_fault + c * PER
    if tt in idx:
        cur = idx[tt]
    timeline.append((c, cur))

# --- attribute ---
order, cycles = [], {}
for _, v in timeline:
    if v not in cycles:
        cycles[v] = 0
        order.append(v)
    cycles[v] += 1

total = len(timeline)
entry = sum(c for v, c in cycles.items() if v < HC or v >= HS) if False else 0
handler = sum(c for v, c in cycles.items() if HC <= v < HS)
outside = total - handler

# The install-and-return instruction. Everything the PC visits INSIDE the
# bracket after it is not executed code: LDTLB.RN has no delay slot, so the PC
# momentarily advances onto whatever follows (here .balign padding) while the
# install completes and the redirect to SPC resolves. Crediting those cycles to
# a "nop" the CPU never runs would be a lie, so they are labelled as redirect.
LDTLB_RN = {0x03fb, 0x0078, 0x00fb}
ldtlb_pc = None
for v in sorted(k for k in disasm if HC <= k < HS):
    txt = disasm[v]
    m = re.match(r"\.word 0x([0-9a-f]{4})", txt)
    if (m and int(m.group(1), 16) & 0xf0ff in LDTLB_RN) or txt.startswith("ldtlb.rn"):
        ldtlb_pc = v

# Classify by PHASE, walking the timeline in order, not by address range: with
# no .balign padding after LDTLB.RN the PC parks on _h_slow's FIRST instruction
# during the redirect, which an address test would misfile as slow-path code.
#   entry    : before the first handler PC
#   body     : first handler PC .. the LDTLB.RN slot inclusive
#   redirect : after LDTLB.RN, until the PC reaches the restart PC
#   restart  : the restarted instruction itself
buckets = {"entry": 0, "body": 0, "redirect": 0, "restart": 0}
phase_of = {}
phase = "entry"
for _, v in timeline:
    if phase == "entry" and HC <= v < HS:
        phase = "body"
    elif phase == "body" and ldtlb_pc is not None and v != ldtlb_pc and not (HC <= v <= ldtlb_pc):
        phase = "redirect"
    if phase == "redirect" and v == pc_restart:
        phase = "restart"
    buckets[phase] += 1
    phase_of.setdefault(v, phase)

print(f"profile: guard={guard}  clock {PER/1e6:.1f} ns")
print(f"profile: fault at PC 0x{pc_fault:08x} ({disasm.get(pc_fault,'?')})")
print(f"profile: restart at PC 0x{pc_restart:08x} ({disasm.get(pc_restart,'?')})"
      f"  = {total} cycles, incl. the restarted instruction's first execute cycle")
print()
print("  cyc  PC          where               instruction")
print("  ---  ----------  ------------------  --------------------------------")
for v in order:
    ph = phase_of.get(v, "?")
    if ph == "redirect":
        where, txt = "LDTLB.RN redirect", "(PC parked here; NOT executed)"
    elif ph == "entry":
        where, txt = "fault detect+entry", disasm.get(v, "?")
    elif ph == "restart":
        where, txt = "RESTARTED insn", disasm.get(v, "?")
    else:
        where, txt = f"handler+0x{v-HC:02x}", disasm.get(v, "?")
    print(f"  {cycles[v]:3d}  0x{v:08x}  {where:18s}  {txt}")
print()
print(f"  {total:3d}  TOTAL")
print()
print("  Rolled up:")
print(f"    {buckets['entry']:3d} cyc  HW exception entry (PC held on the faulting insn)")
nbody = sum(1 for v in order if phase_of.get(v) == "body")
print(f"    {buckets['body']:3d} cyc  handler body, {nbody} executed instructions")
print(f"    {buckets['redirect']:3d} cyc  LDTLB.RN install + redirect to SPC")
print(f"    {buckets['restart']:3d} cyc  first execute cycle of the restarted instruction")
