CC = sh2-elf-gcc
LD = sh2-elf-ld
AR = sh2-elf-ar
OBJCOPY = sh2-elf-objcopy
RANLIB = sh2-elf-ranlib
LIBGCC = `sh2-elf-gcc -print-file-name=libgcc.a`
# Must match the DUT's PRIV_ARCH generic (see ../Makefile). 0 = J2/J1 (no
# privilege; privmode expects no trap), 1 = J4 (privmode expects the trap).
CONFIG_PRIV_ARCH ?= 0
CONFIG_MMU_ARCH ?= 0
CONFIG_SH2A_ARCH ?= 0
CFLAGS = -m2 -g -Os -Wall -Iinclude -DCONFIG_PRIV_ARCH=$(CONFIG_PRIV_ARCH) -DCONFIG_MMU_ARCH=$(CONFIG_MMU_ARCH) -DCONFIG_SH2A_ARCH=$(CONFIG_SH2A_ARCH)
LDFLAGS = -T sh32.x -Map main.map

all: interrupts.img rte.img privmode.img banktest.img exctest.img excguard.img trapatest.img pm3vec.img pm3guard.img rteredir.img mmureg.img mmuguard.img mmuxlate.img mmufault.img mmudslot.img mmurte.img mmustore.img mmuimiss.img mmuimiss_illegal.img mmusr.img mmuicolor.img mmudcbit.img mmuldtlbr.img mmutsb.img mmurun.img mmuidx.img mmustres.img mmustr2.img mmusmep.img mmuirun.img mmuainc.img mmuainc2.img mmureloc.img mmurelocif.img mmurelocbp.img mmustale.img mmuasid.img mmuglobal.img mmumultihit.img mmudblflt.img mmupage4k.img mmupagereloc16k.img mmupage16k.img mmupage64k.img mmupage1m.img mmupagemix.img mmupagemix2.img mmupagewalk.img m8_smoke.img m8_dside.img m8_ifetch_0.img m8_ifetch_1.img m8_ifetch_2.img m8_macarith.img m8_macseq.img

# J4-only guard images. These require the J4/PRIV/MMU overlay decoder built
# by sim/mmu_sim.sh to pass: the base-J2 cpu_ctb cannot fire illegal-
# instruction exceptions at all. They are deliberately kept OUT of `all` so
# regression.sh Step 6 -- which runs `make all` then globs sim/tests/*.img on
# the base-J2 cpu_ctb -- never sweeps them up and hangs to stop-time.
# sim/mmu_sim.sh builds each of these explicitly by target name ($t.img).
j4-guards: j4_illegal_trap.img

# ---------------------------------------------------------------------------
# SP2 mmulinux: harness driving the REAL linux@jcore MMU objects (built by
# LINUX_SRC's kbuild) through the cosim. Both the harness .S and the three
# linux@jcore objects use real J4-only mnemonics (LDTLB, LDC/STC
# PTEH/PTEL/ASIDR/TSBPTR/VBR) that only the WIP J4 gas/ld
# (binutils-gdb/build-sh2) understand -- the system sh2-elf-gas/ld choke on
# them (unknown opcode / EM:42 "wrong format" respectively; see
# sim/linux_sim.sh and the SP2 Task 0 report). Defaults assume the standard
# jcore-workspace sibling-checkout layout from sim/tests/.
# ---------------------------------------------------------------------------
LINUX_SRC ?= ../../../linux
J4GAS ?= ../../../binutils-gdb/build-sh2/gas/as-new
J4LD ?= ../../../binutils-gdb/build-sh2/ld/ld-new
# The system sh2-elf-objcopy also chokes on the J4 e_flags ("Unable to
# recognise the format of the input file") -- use the objcopy built
# alongside the same J4 gas/ld for mmulinux.elf -> mmulinux.img.
J4OBJCOPY ?= ../../../binutils-gdb/build-sh2/binutils/objcopy
J4BIN ?= /tmp/j4bin

TLBJCORE_O := $(LINUX_SRC)/arch/sh/mm/tlb-jcore.o
EX_O := $(LINUX_SRC)/arch/sh/kernel/cpu/jcore/ex.o
ENTRY_O := $(LINUX_SRC)/arch/sh/kernel/cpu/jcore/entry.o

mmulinux.o: mmulinux.S
	mkdir -p $(J4BIN) && ln -sf $(abspath $(J4GAS)) $(J4BIN)/as
	$(CC) $(CFLAGS) -D__ASSEMBLY__ -I$(LINUX_SRC)/arch/sh/include -B$(J4BIN) -Wa,--isa=any -c $< -o $@

mmulinux.elf: mmulinux.o $(TLBJCORE_O) $(EX_O) $(ENTRY_O)
	$(J4LD) -T sh32_p1.x -Map main.map $^ $(LIBGCC) -o $@

mmulinux.img: mmulinux.elf
	$(J4OBJCOPY) -v -S -O binary --srec-forceS3 $< $@

# ---------------------------------------------------------------------------
# SP3-c Task 3: mmuboot links the REAL jcore_mmu_enable (Task 2) and drives
# it through the cosim; the TLB-miss handler itself is hand-rolled in
# mmuboot.S (Task 2 only factored the boot enable stub, not a full walker).
# ---------------------------------------------------------------------------
MMU_ENABLE_O := $(LINUX_SRC)/arch/sh/kernel/cpu/jcore/mmu_enable.o

mmuboot.o: mmuboot.S
	mkdir -p $(J4BIN) && ln -sf $(abspath $(J4GAS)) $(J4BIN)/as
	$(CC) $(CFLAGS) -D__ASSEMBLY__ -I$(LINUX_SRC)/arch/sh/include -B$(J4BIN) -Wa,--isa=any -c $< -o $@

mmuboot.elf: mmuboot.o $(MMU_ENABLE_O)
	$(J4LD) -T sh32_p1.x -Map main.map $^ $(LIBGCC) -o $@

mmuboot.img: mmuboot.elf
	$(J4OBJCOPY) -v -S -O binary --srec-forceS3 $< $@

m8_macarith.elf: m8_macarith.o
interrupts.elf: interrupts.o
rte.elf: rte.o
privmode.elf: privmode.o
banktest.elf: banktest.o
exctest.elf: exctest.o
excguard.elf: excguard.o
trapatest.elf: trapatest.o
rteredir.elf: rteredir.o
pm3vec.elf: pm3vec.o
pm3guard.elf: pm3guard.o
mmureg.elf: mmureg.o
mmuguard.elf: mmuguard.o
mmuxlate.elf: mmuxlate.o
mmufault.elf: mmufault.o
mmudslot.elf: mmudslot.o
mmuidslot.elf: mmuidslot.o
mmubratest.elf: mmubratest.o
mmurte.elf: mmurte.o
mmustore.elf: mmustore.o
mmuimiss.elf: mmuimiss.o
mmuimiss_illegal.elf: mmuimiss_illegal.o
mmusr.elf: mmusr.o
mmuicolor.elf: mmuicolor.o
mmudcbit.elf: mmudcbit.o
mmureloc.elf: mmureloc.o
mmustale.elf: mmustale.o
mmuasid.elf: mmuasid.o
mmuglobal.elf: mmuglobal.o
mmumultihit.elf: mmumultihit.o
mmudblflt.elf: mmudblflt.o
mmupage4k.elf: mmupage4k.o
mmupagereloc16k.elf: mmupagereloc16k.o
mmupage16k.elf: mmupage16k.o
mmupage64k.elf: mmupage64k.o
mmupage1m.elf: mmupage1m.o
mmupagemix.elf: mmupagemix.o
mmupagemix2.elf: mmupagemix2.o
mmupagewalk.elf: mmupagewalk.o
mmurelocif.elf: mmurelocif.o
mmurelocbp.elf: mmurelocbp.o
mmuldtlbr.elf: mmuldtlbr.o
mmuidx.elf: mmuidx.o
mmustres.elf: mmustres.o
mmustr2.elf: mmustr2.o
mmusmep.elf: mmusmep.o

%.o: %.S
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

sh2a_movi20.elf: sh2a_movi20.o
sh2a_movl12.elf: sh2a_movl12.o
sh2a_disp12s.elf: sh2a_disp12s.o
sh2a_disp12mix.elf: sh2a_disp12mix.o
sh2a_disp12bw.elf: sh2a_disp12bw.o
sh2a_disp12u.elf: sh2a_disp12u.o
sh2a_disp12stall.elf: sh2a_disp12stall.o
sh2a_movml0.elf: sh2a_movml0.o
sh2a_movml.elf: sh2a_movml.o
sh2a_movml_b2b.elf: sh2a_movml_b2b.o
sh2a_movml_pop.elf: sh2a_movml_pop.o
sh2a_movml_pop0.elf: sh2a_movml_pop0.o
sh2a_movml_pop2.elf: sh2a_movml_pop2.o
sh2a_movml_pop_b2b.elf: sh2a_movml_pop_b2b.o
sh2a_movml_pop_restart.elf: sh2a_movml_pop_restart.o
sh2a_movml_push_restart.elf: sh2a_movml_push_restart.o
sh2a_movmu.elf: sh2a_movmu.o
sh2a_movmu_b2b.elf: sh2a_movmu_b2b.o
sh2a_movmu_pop_restart.elf: sh2a_movmu_pop_restart.o
sh2a_movmu_pop_push.elf: sh2a_movmu_pop_push.o
sh2a_bitreg.elf: sh2a_bitreg.o
sh2a_clip.elf: sh2a_clip.o
sh2a_mulr.elf: sh2a_mulr.o
sh2a_movincdec.elf: sh2a_movincdec.o
sh2a_movrt_nott.elf: sh2a_movrt_nott.o
sh2a_branchn.elf: sh2a_branchn.o
sh2a_bitmem_rmw.elf: sh2a_bitmem_rmw.o
j4_illegal_trap.elf: j4_illegal_trap.o
mmurun.elf: mmurun.o tlbwalk.o
mmuirun.elf: mmuirun.o tlbwalk.o
mmuainc.elf: mmuainc.o tlbwalk.o
mmuainc2.elf: mmuainc2.o tlbwalk.o
m8_smoke.elf: m8_smoke.o tlbwalk.o
m8_dside.elf: m8_dside.o tlbwalk.o
m8_macseq.elf: m8_macseq.o tlbwalk.o
# m8_ifetch_{0,1,2}: the instruction-FETCH fault-transparency sweep (General
# non-memory instructions planted into the translated code page, fetched
# cold/warm; full {r0,r8,T,MACH,MACL,SR&mask} snapshot). Validated -- mechanism
# mirrors mmuirun.S. Partitioned into 3 sub-images (24 cases each = all 72) so
# every sub-image is a SEPARATE sim run under the co-sim cumulative-fetch ceiling.
m8_ifetch_0.elf: m8_ifetch_0.o tlbwalk.o
m8_ifetch_1.elf: m8_ifetch_1.o tlbwalk.o
m8_ifetch_2.elf: m8_ifetch_2.o tlbwalk.o
# m8_idslot_{0,1,2}: the instruction-FETCH-in-DELAY-SLOT fault-transparency sweep
# (same General non-memory set, planted in a branch delay slot straddling a page
# boundary so the delay-slot fetch IMISSes; the restart must land on the branch).
m8_idslot_0.elf: m8_idslot_0.o tlbwalk.o
m8_idslot_1.elf: m8_idslot_1.o tlbwalk.o
m8_idslot_2.elf: m8_idslot_2.o tlbwalk.o

%.elf:
	$(LD) $(LDFLAGS) $^ $(LIBGCC) -o $@

%.img: %.elf
	$(OBJCOPY) -v -S -O binary --srec-forceS3 $< $@

clean:
	rm -f *.o *.elf *.img *.map

.PHONY: clean j4-guards
mmutsb.elf: mmutsb.o
