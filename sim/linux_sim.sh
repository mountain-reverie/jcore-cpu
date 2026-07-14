#!/bin/bash
# linux_sim.sh -- SP2: local runner for cosim'ing the REAL linux@jcore MMU
# TLB-miss handler objects against the jcore-cpu GHDL testbench.
#
# STATUS: WIP (Task 0 bring-up only). This script currently only captures
# the Task-0 build+link recipe that was proven to work; it does not yet
# drive the GHDL cosim (that lands in later SP2 tasks).
#
# ---------------------------------------------------------------------------
# Task 0 findings (object-build + link bring-up, de-risking ram@0 relocation)
# ---------------------------------------------------------------------------
#
# LINUX_SRC   defaults to ../linux (branch "jcore")
# J4GAS       ../binutils-gdb/build-sh2/gas/as-new
# J4LD        ../binutils-gdb/build-sh2/ld/ld-new   <-- IMPORTANT, see below
#
# kbuild reaches the J4 gas via CC (kbuild has no clean AS= override path
# that survives .S dependency generation), NOT via AS=:
#
#   mkdir -p /tmp/j4bin && ln -sf "$J4GAS" /tmp/j4bin/as
#   cd "$LINUX_SRC"
#   make ARCH=sh CROSS_COMPILE=sh2-elf- CC="sh2-elf-gcc -B/tmp/j4bin" jcore_defconfig
#   make ARCH=sh CROSS_COMPILE=sh2-elf- CC="sh2-elf-gcc -B/tmp/j4bin" \
#        arch/sh/mm/tlb-jcore.o arch/sh/kernel/cpu/jcore/ex.o arch/sh/kernel/cpu/jcore/entry.o
#
# Undefined-symbol stub set required by the three objects (cross-object
# references only -- exact `sh2-elf-nm *.o | grep ' U '` output):
#   tlb-jcore.o : arch_local_irq_restore, arch_local_save_flags
#   ex.o        : exception_handler, jcore_tlb_fault_entry (resolves internally
#                 from entry.o), __jcore_tlb_walk (resolves internally from
#                 tlb-jcore.o)
#   entry.o     : do_page_fault
# -> harness stub set = { do_page_fault, exception_handler,
#                          arch_local_irq_restore, arch_local_save_flags }
#   (all four stubbed as trivial `rts; nop` in sim/tests/mmulinux_stub.S)
#
# GOTCHA (the actual checkpoint moment): the FIRST trial link, using the
# system `sh2-elf-ld` (GNU ld 2.43.1), FAILED:
#   sh2-elf-ld: .../tlb-jcore.o: relocations in generic ELF (EM: 42)
#   sh2-elf-ld: .../tlb-jcore.o: error adding symbols: file in wrong format
# Root cause: the linux objects were assembled by the WIP J4 gas
# (2.46.50, this workspace's binutils-gdb build), which stamps a newer/
# extended e_flags (0x1b, "unknown ISA" to old readelf) that the *system*
# ld (2.43.1) does not understand. This is NOT a PAGE_OFFSET/absolute-
# relocation problem -- it is a toolchain VERSION SKEW between assembler
# and linker. Fix: link with the ld built alongside the same gas
# (build-sh2/ld/ld-new, also 2.46.50) instead of the system sh2-elf-ld:
#
#   LX=../linux
#   LD=../binutils-gdb/build-sh2/ld/ld-new
#   sh2-elf-gcc -m2 -Iinclude -c sim/tests/mmulinux_stub.S -o /tmp/mmulinux_stub.o
#   "$LD" -T sim/tests/sh32.x /tmp/mmulinux_stub.o \
#      "$LX/arch/sh/mm/tlb-jcore.o" "$LX/arch/sh/kernel/cpu/jcore/ex.o" \
#      "$LX/arch/sh/kernel/cpu/jcore/entry.o" \
#      "$(sh2-elf-gcc -print-file-name=libgcc.a)" -o /tmp/mmulinux_stub.elf
#
# Result: LINKS CLEANLY at ram@0 (origin 0x0, sim/tests/sh32.x). No absolute
# PAGE_OFFSET-style relocation was observed -- the ram@0 model is de-risked.
# Resolved low addresses (objdump -t /tmp/mmulinux_stub.elf):
#   jcore_vbr_base       0x000008e0
#   jcore_tlb_miss       0x00000ce0
#   __jcore_tlb_walk     0x00000140
#   do_page_fault        0x0000012c  (stub)
#   exception_handler    0x00000130  (stub)
#   arch_local_irq_restore 0x00000134 (stub)
#   arch_local_save_flags  0x00000138 (stub)
#
# NEXT (later SP2 tasks): replace the trivial stub with real scenario asm
# driving jcore_tlb_miss end-to-end through the GHDL cosim, using J4LD
# (not the system ld) for every link step involving linux@jcore objects.

set -euo pipefail
echo "linux_sim.sh: WIP, see comments at top of this file for the Task 0" >&2
echo "bring-up recipe. GHDL cosim driving not yet implemented." >&2
exit 1
