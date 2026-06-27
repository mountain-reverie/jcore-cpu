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
CFLAGS = -m2 -g -Os -Wall -Iinclude -DCONFIG_PRIV_ARCH=$(CONFIG_PRIV_ARCH) -DCONFIG_MMU_ARCH=$(CONFIG_MMU_ARCH)
LDFLAGS = -T sh32.x -Map main.map

all: interrupts.img rte.img privmode.img banktest.img exctest.img excguard.img trapatest.img pm3vec.img pm3guard.img rteredir.img mmureg.img mmuguard.img mmuxlate.img mmufault.img mmurte.img mmustore.img mmuimiss.img mmusr.img mmuicolor.img mmudcbit.img mmuldtlbr.img mmutsb.img mmurun.img mmuidx.img mmustres.img mmustr2.img mmuirun.img mmuainc.img mmuainc2.img mmureloc.img mmurelocif.img mmurelocbp.img mmustale.img mmuasid.img mmupage4k.img mmupage16k.img mmupage64k.img mmupage1m.img mmupagemix.img mmupagemix2.img mmupagewalk.img m8_smoke.img m8_dside.img m8_ifetch_0.img m8_ifetch_1.img m8_ifetch_2.img m8_macarith.img m8_macseq.img

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
mmurte.elf: mmurte.o
mmustore.elf: mmustore.o
mmuimiss.elf: mmuimiss.o
mmusr.elf: mmusr.o
mmuicolor.elf: mmuicolor.o
mmudcbit.elf: mmudcbit.o
mmureloc.elf: mmureloc.o
mmustale.elf: mmustale.o
mmuasid.elf: mmuasid.o
mmupage4k.elf: mmupage4k.o
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

%.o: %.S
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

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

%.elf:
	$(LD) $(LDFLAGS) $^ $(LIBGCC) -o $@

%.img: %.elf
	$(OBJCOPY) -v -S -O binary --srec-forceS3 $< $@

clean:
	rm -f *.o *.elf *.img *.map

.PHONY: clean
mmutsb.elf: mmutsb.o
