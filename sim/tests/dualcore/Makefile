CC = sh2-elf-gcc
OBJCOPY = sh2-elf-objcopy
CFLAGS = -m2 -nostdlib
LDFLAGS = -T link.x -nostdlib

# mmusmpasid needs the shared guard headers one directory up (sim_instr.h,
# mmuwalk_common.inc) and must know it is being built for a PRIV_ARCH core --
# the whole body is #if CONFIG_PRIV_ARCH'd, so a CONFIG_PRIV_ARCH=0 build
# assembles to nothing but _done and reports a vacuous pass.
MMUFLAGS = -m2 -nostdlib -I.. -DCONFIG_PRIV_ARCH=1

all: smp_ok.img smp_bug.img smp_bringup.img mmusmpasid_ok.img mmusmpasid_bug.img

smp_ok.elf: smp_repro.s link.x
	$(CC) $(CFLAGS) $(LDFLAGS) smp_repro.s -o $@
smp_bug.elf: smp_repro.s link.x
	$(CC) $(CFLAGS) -Wa,--defsym,HAZARD=1 $(LDFLAGS) smp_repro.s -o $@
smp_bringup.elf: smp_bringup.s link.x
	$(CC) $(CFLAGS) $(LDFLAGS) smp_bringup.s -o $@

# mmusmpasid_ok: per-core TSBs -- must PASS.
# mmusmpasid_bug: both cores share cpu0's TSB -- must FAIL. This pair is what
# proves the guard can fail; see run_mmusmpasid.sh.
mmusmpasid_ok.elf: mmusmpasid.S link.x ../mmuwalk_common.inc ../sim_instr.h
	$(CC) $(MMUFLAGS) $(LDFLAGS) mmusmpasid.S -o $@
mmusmpasid_bug.elf: mmusmpasid.S link.x ../mmuwalk_common.inc ../sim_instr.h
	$(CC) $(MMUFLAGS) -DSHARED_TSB=1 $(LDFLAGS) mmusmpasid.S -o $@

%.img: %.elf
	$(OBJCOPY) -O binary $< $@
clean:
	rm -f *.elf *.img
.PHONY: all clean
