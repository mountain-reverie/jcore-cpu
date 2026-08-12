CC = sh2-elf-gcc
LD = sh2-elf-ld
AR = sh2-elf-ar
OBJCOPY = sh2-elf-objcopy
NM = sh2-elf-nm
RANLIB = sh2-elf-ranlib
LIBGCC = `sh2-elf-gcc -print-file-name=libgcc.a`
# CPU_VARIANT selects the same variant as ../Makefile / variants.toml.
# CONFIG_PRIV_ARCH is DERIVED from it (variants.toml: only [j4] sets
# PRIV_ARCH=true) rather than being a standalone flag callers set directly.
# 0 = J2/J1 (no privilege; privmode expects no trap), 1 = J4 (privmode
# expects the trap).
CPU_VARIANT ?= j2
CONFIG_PRIV_ARCH := $(if $(filter j4,$(CPU_VARIANT)),1,0)
# CONFIG_SH2A_ARCH is likewise DERIVED from CPU_VARIANT (variants.toml: only
# [j2a] sets SH2A_ARCH=true) rather than being a standalone flag.
CONFIG_SH2A_ARCH := $(if $(filter j2a,$(CPU_VARIANT)),1,0)
CFLAGS = -m2 -g -Os -Wall -Iinclude -DCONFIG_PRIV_ARCH=$(CONFIG_PRIV_ARCH) -DCONFIG_SH2A_ARCH=$(CONFIG_SH2A_ARCH)
LDFLAGS = -T sh32.x -Map main.map

# BASE_IMGS: images that must build AND pass on the base-J2 cpu_ctb.
# regression.sh Step 6 iterates THIS list (via `make print-base-imgs`)
# instead of globbing *.img, so J4-only images left behind in this
# directory by a previous sim/mmu_sim.sh run can never be swept up and
# run against a decoder that cannot pass them.
BASE_IMGS := interrupts.img rte.img privmode.img banktest.img exctest.img excguard.img trapatest.img pm3vec.img pm3guard.img rteredir.img mmureg.img mmuguard.img mmuxlate.img mmufault.img mmufsr.img mmudslot.img mmurte.img mmustore.img mmuimiss.img mmuimiss_illegal.img mmusr.img mmuicolor.img mmudcbit.img mmuldtlbr.img mmutsb.img mmuwalkhit.img mmurun.img mmubench.img mmubenchi.img mmuvecsplit.img mmuidx.img mmustres.img mmustr2.img mmudrain.img mmuimissrest.img mmushadowld.img mmushadowst.img mmurestartpc.img mmupcprobe.img mmudspcprobe.img mmudspcprobe_late.img mmudspcprobe_lateb.img mmudspcprobe_latew.img mmudspcprobe_latec.img mmudspcprobe_latem.img mmudspcprobe_latemw.img mmustcldslot.img mmusmep.img mmuirun.img mmuainc.img mmuainc2.img mmureloc.img mmurelocif.img mmurelocbp.img mmustale.img mmuasid.img mmuasidsh.img mmuglobal.img mmumultihit.img mmudblflt.img mmunest_trapa.img mmunest_slotill.img mmunest.img mmuremap.img mmucmpcsr.img mmupage4k.img mmupagereloc16k.img mmupage16k.img mmupage64k.img mmupage1m.img mmupagemix.img mmupagemix2.img mmupagewalk.img m8_smoke.img m8_dside.img m8_ifetch_0.img m8_ifetch_1.img m8_ifetch_2.img m8_macarith.img m8_macseq.img m8_dsdslot_0.img m8_multihit_ifetch.img shldshadguard.img

all: $(BASE_IMGS)

# Names (no .img suffix), one per line, for regression.sh Step 6.
.PHONY: print-base-imgs
print-base-imgs:
	@printf '%s\n' $(basename $(BASE_IMGS))

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

# mmulinuxexc: the same real-linux-objects harness, but for the NON-TLB fixed
# vectors (VBR+0x100 general/TRAPA/protection, VBR+0x600 interrupt). mmulinux
# covers VBR+0x400 only, which is why those two were the ones found broken.
mmulinuxexc.o: mmulinuxexc.S
	mkdir -p $(J4BIN) && ln -sf $(abspath $(J4GAS)) $(J4BIN)/as
	$(CC) $(CFLAGS) -D__ASSEMBLY__ -I$(LINUX_SRC)/arch/sh/include -B$(J4BIN) -Wa,--isa=any -c $< -o $@

mmulinuxexc.elf: mmulinuxexc.o $(TLBJCORE_O) $(EX_O) $(ENTRY_O)
	$(J4LD) -T sh32_p1.x -Map main.map $^ $(LIBGCC) -o $@

mmulinuxexc.img: mmulinuxexc.elf
	$(J4OBJCOPY) -v -S -O binary --srec-forceS3 $< $@

mmulinux.img: mmulinux.elf
	$(J4OBJCOPY) -v -S -O binary --srec-forceS3 $< $@

# ---------------------------------------------------------------------------
# J4-TLB SP2 Task 6: mmuhuge -- like mmulinux, but proves the REAL walker
# installs a multi-size huge TLB entry (PageMask != 16 KB base) from a
# huge-page PTE size slot. See sim/tests/mmuhuge.S.
# ---------------------------------------------------------------------------
mmuhuge.o: mmuhuge.S
	mkdir -p $(J4BIN) && ln -sf $(abspath $(J4GAS)) $(J4BIN)/as
	$(CC) $(CFLAGS) -D__ASSEMBLY__ -I$(LINUX_SRC)/arch/sh/include -B$(J4BIN) -Wa,--isa=any -c $< -o $@

mmuhuge.elf: mmuhuge.o $(TLBJCORE_O) $(EX_O) $(ENTRY_O)
	$(J4LD) -T sh32_p1.x -Map main.map $^ $(LIBGCC) -o $@

mmuhuge.img: mmuhuge.elf
	$(J4OBJCOPY) -v -S -O binary --srec-forceS3 $< $@

# ---------------------------------------------------------------------------
# SP3-c Task 3: mmuboot links the REAL jcore_mmu_enable (Task 2) and drives
# it through the cosim; the TLB-miss handler itself is hand-rolled in
# mmuboot.S (Task 2 only factored the boot enable stub, not a full walker).
# ---------------------------------------------------------------------------
MMU_ENABLE_O := $(LINUX_SRC)/arch/sh/kernel/cpu/jcore/mmu_enable.o

# The linux@jcore objects are built OUT OF TREE by kbuild (the full-regression
# CI job and sim/linux_sim.sh do it); this Makefile must NEVER compile them.
# These explicit rules exist to override the `%.o: %.c` / `%.o: %.S` pattern
# rules, which match their absolute paths perfectly well and would rebuild them
# with plain CFLAGS -- kernel sources need kbuild's include paths and die on
# `linux/mm.h: No such file or directory`.
#
# This is not hypothetical. Adding .cpu-variant as a prerequisite of those
# pattern rules made exactly that happen in CI: the kbuild-built objects are
# OLDER than the stamp written at the start of the run, so make considered them
# out of date and recompiled them locally. mmulinux/mmuboot/mmuhuge all failed
# to build while every other guard passed. With no prerequisites here, an object
# that exists is never out of date, and a missing one gets a diagnostic that
# names the real problem instead of a confusing header error.
$(TLBJCORE_O) $(EX_O) $(ENTRY_O) $(MMU_ENABLE_O):
	@test -f $@ || { \
	  echo "ERROR: $@ is missing."; \
	  echo "  It is a linux@jcore kbuild output, not built here."; \
	  echo "  See sim/linux_sim.sh and the full-regression CI job."; \
	  exit 1; }

mmuboot.o: mmuboot.S
	mkdir -p $(J4BIN) && ln -sf $(abspath $(J4GAS)) $(J4BIN)/as
	$(CC) $(CFLAGS) -D__ASSEMBLY__ -I$(LINUX_SRC)/arch/sh/include -B$(J4BIN) -Wa,--isa=any -c $< -o $@

mmuboot.elf: mmuboot.o $(MMU_ENABLE_O)
	$(J4LD) -T sh32_p1.x -Map main.map $^ $(LIBGCC) -o $@

mmuboot.img: mmuboot.elf
	$(J4OBJCOPY) -v -S -O binary --srec-forceS3 $< $@

m8_macarith.elf: m8_macarith.o
m8_multihit_ifetch.elf: m8_multihit_ifetch.o
interrupts.elf: interrupts.o
rte.elf: rte.o
privmode.elf: privmode.o
banktest.elf: banktest.o
exctest.elf: exctest.o
excguard.elf: excguard.o
trapatest.elf: trapatest.o
shldshadguard.elf: shldshadguard.o
rteredir.elf: rteredir.o
pm3vec.elf: pm3vec.o
pm3guard.elf: pm3guard.o
mmureg.elf: mmureg.o
mmuguard.elf: mmuguard.o
mmuxlate.elf: mmuxlate.o
mmufault.elf: mmufault.o
mmufsr.elf: mmufsr.o
mmudslot.elf: mmudslot.o
mmuidslot.elf: mmuidslot.o
mmufaultage.elf: mmufaultage.o
mmumhorder.elf: mmumhorder.o
mmuidorder.elf: mmuidorder.o
mmuwalkorderhit.elf: mmuwalkorderhit.o
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
mmuasidsh.elf: mmuasidsh.o
mmuglobal.elf: mmuglobal.o
mmumultihit.elf: mmumultihit.o
mmudblflt.elf: mmudblflt.o
mmunest_trapa.elf: mmunest_trapa.o
mmunest_slotill.elf: mmunest_slotill.o
mmunest.elf: mmunest.o
mmuremap.elf: mmuremap.o
mmucmpcsr.elf: mmucmpcsr.o
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
mmudrain.elf: mmudrain.o
mmushadowld.elf: mmushadowld.o
mmushadowst.elf: mmushadowst.o
mmurestartpc.elf: mmurestartpc.o
mmupcprobe.elf: mmupcprobe.o
mmudspcprobe.elf: mmudspcprobe.o
mmudspcprobe_late.elf: mmudspcprobe_late.o
mmustcldslot.elf: mmustcldslot.o
# Per-form Defect 7 locks: three-line wrappers that #define DSLOT_FORM and
# #include mmudspcprobe_late.S, so the harness exists once. The .o depends on
# the shared harness too -- editing it must rebuild every form.
mmudspcprobe_lateb.o: mmudspcprobe_late.S
mmudspcprobe_latew.o: mmudspcprobe_late.S
mmudspcprobe_latec.o: mmudspcprobe_late.S
mmudspcprobe_latem.o: mmudspcprobe_late.S
mmudspcprobe_latemw.o: mmudspcprobe_late.S
mmudspcprobe_lateb.elf: mmudspcprobe_lateb.o
mmudspcprobe_latew.elf: mmudspcprobe_latew.o
mmudspcprobe_latec.elf: mmudspcprobe_latec.o
mmudspcprobe_latem.elf: mmudspcprobe_latem.o
mmudspcprobe_latemw.elf: mmudspcprobe_latemw.o
mmuimissrest.elf: mmuimissrest.o
mmusmep.elf: mmusmep.o


# ---------------------------------------------------------------------------
# CPU_VARIANT stamp. CFLAGS carries -DCONFIG_PRIV_ARCH / -DCONFIG_SH2A_ARCH,
# both DERIVED from CPU_VARIANT above -- but make only ever compares .S/.c
# timestamps, so `make CPU_VARIANT=j4 foo.img` over a tree built at j2 reports
# "up to date" and hands back the J2 binary. That is not hypothetical: it is
# what makes regression.sh Step 6 run J4 images on a base-J2 cpu_ctb and report
# ~74 of 77 sim tests failing, a total-collapse signature that looks like a
# catastrophic RTL regression and is purely stale artifacts.
#
# .cpu-variant records the variant actually used to build the objects in this
# directory. It is rewritten only when the value CHANGES (cmp before mv), so it
# does not itself force a rebuild on every invocation -- but when the variant
# does change, every .o depending on it is correctly out of date.
.PHONY: FORCE
.cpu-variant: FORCE
	@echo '$(CPU_VARIANT) $(CONFIG_PRIV_ARCH) $(CONFIG_SH2A_ARCH)' > $@.tmp
	@if cmp -s $@.tmp $@; then rm -f $@.tmp; else \
	  test ! -f $@ || echo "  CPU_VARIANT changed to '$(CPU_VARIANT)'; rebuilding"; \
	  mv $@.tmp $@; fi

sh2a_%.o: sh2a_%.S .cpu-variant
	$(CC) $(CFLAGS) -Wa,--isa=sh2a -c $< -o $@

%.o: %.S .cpu-variant
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.c .cpu-variant
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
sh2a_divs.elf: sh2a_divs.o
sh2a_movincdec.elf: sh2a_movincdec.o
sh2a_movrt_nott.elf: sh2a_movrt_nott.o
sh2a_branchn.elf: sh2a_branchn.o
sh2a_bitmem_rmw.elf: sh2a_bitmem_rmw.o
sh2a_pref.elf: sh2a_pref.o
sh2a_tbr.elf: sh2a_tbr.o
j4_illegal_trap.elf: j4_illegal_trap.o
mmubench.elf: mmubench.o tlbwalk.o
mmubenchi.elf: mmubenchi.o tlbwalk.o
mmuvecsplit.elf: mmuvecsplit.o
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
# m8_dsdslot_0: the data-side-fault-in-DELAY-SLOT sweep (General MOV.{B,W,L}
# forms, STC.L/STS.L, TAS.B planted in a branch delay slot, run straight-line
# P1; the delay-slot instruction's DATA access DMISSes; the restart must land
# on the branch and any base-register update apply exactly once). No
# cumulative-fetch ceiling applies here, so it is a single image.
#
# Cases whose faulting access launches in a slot AFTER slot 0 (CAS.L's locked
# RMW, and the MOV.{B,W,L} @Rm+ post-increment loads) are emitter-skipped
# with an explicit "Defect 7" reason: ma_dslot is shadowed at access-launch,
# so a late-launching access restarts at the delay-slot instruction itself
# instead of the branch. See sim/mmu_sim.sh and
# decode/gen-go/internal/faultgen/emit.go (lateAccess). Re-enable those
# cases via the emitter once Defect 7 is fixed.
m8_dsdslot_0.elf: m8_dsdslot_0.o tlbwalk.o

%.elf:
	$(LD) $(LDFLAGS) $^ $(LIBGCC) -o $@

%.img: %.elf
	$(OBJCOPY) -v -S -O binary --srec-forceS3 $< $@

# The M8 harness keeps its page tables, TSB, stack and snapshot buffers in a
# FIXED block at 0x00010000 (see m8_runtime.inc). An image that reaches it gets
# its own code overwritten by kmain's page-table setup -- silently, and with a
# symptom (CPU reset loop / bus ACK timeout) that looks nothing like the cause.
# That happened for real once; fail the build instead.
M8_SCRATCH_BASE = 0x10000
m8_%.img: m8_%.elf
	@end=$$($(NM) -n $< | awk '/ _edata/{print $$1}'); 	 if [ $$((0x$$end)) -ge $$(($(M8_SCRATCH_BASE))) ]; then 	   echo "ERROR: $< _edata=0x$$end reaches the M8 scratch block at $(M8_SCRATCH_BASE)." >&2; 	   echo "       Split the axis into more images, or move the block up." >&2; 	   exit 1; 	 fi
	$(OBJCOPY) -v -S -O binary --srec-forceS3 $< $@

clean:
	rm -f *.o *.elf *.img *.map .cpu-variant

.PHONY: clean j4-guards
mmutsb.elf: mmutsb.o
mmuwalkhit.elf: mmuwalkhit.o
mmuwalkmiss.elf: mmuwalkmiss.o
mmuwalkstale.elf: mmuwalkstale.o
mmuwalktorn.elf: mmuwalktorn.o
mmuwalkdside.elf: mmuwalkdside.o
mmuwalkorder.elf: mmuwalkorder.o
mmutsbslot.elf: mmutsbslot.o
mmuwalkasid.elf: mmuwalkasid.o
mmutsbvictim.elf: mmutsbvictim.o
mmuwalkway1.elf: mmuwalkway1.o
mmup4alias.elf: mmup4alias.o
# mmuwalkiside and mmusplit need code at a VA absent from the TLB, so they link
# with their own script (sh32_tlbtext.x = sh32.x + a .tlbtext section fixed at
# VA 0x00008000).
mmuwalkiside.elf: mmuwalkiside.o
	$(LD) -T sh32_tlbtext.x -Map main.map $^ $(LIBGCC) -o $@
mmusplit.elf: mmusplit.o
	$(LD) -T sh32_tlbtext.x -Map main.map $^ $(LIBGCC) -o $@
