CC = sh2-elf-gcc
LD = sh2-elf-ld
AR = sh2-elf-ar
OBJCOPY = sh2-elf-objcopy
RANLIB = sh2-elf-ranlib
LIBGCC = `sh2-elf-gcc -print-file-name=libgcc.a`
# Must match the DUT's PRIV_ARCH generic (see ../Makefile). 0 = J2/J1 (no
# privilege; privmode expects no trap), 1 = J4 (privmode expects the trap).
CONFIG_PRIV_ARCH ?= 0
CFLAGS = -m2 -g -Os -Wall -Iinclude -DCONFIG_PRIV_ARCH=$(CONFIG_PRIV_ARCH)
LDFLAGS = -T sh32.x -Map main.map

all: interrupts.img rte.img privmode.img

interrupts.elf: interrupts.o
rte.elf: rte.o
privmode.elf: privmode.o

%.o: %.S
	$(CC) $(CFLAGS) -c $< -o $@

%.elf:
	$(LD) $(LDFLAGS) $^ $(LIBGCC) -o $@

%.img: %.elf
	$(OBJCOPY) -v -S -O binary --srec-forceS3 $< $@

clean:
	rm -f *.o *.elf *.img *.map

.PHONY: clean
