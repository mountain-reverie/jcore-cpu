CC = sh2-elf-gcc
OBJCOPY = sh2-elf-objcopy
CFLAGS = -m2 -nostdlib
LDFLAGS = -T link.x -nostdlib

all: smp_ok.img smp_bug.img smp_bringup.img

smp_ok.elf: smp_repro.s link.x
	$(CC) $(CFLAGS) $(LDFLAGS) smp_repro.s -o $@
smp_bug.elf: smp_repro.s link.x
	$(CC) $(CFLAGS) -Wa,--defsym,HAZARD=1 $(LDFLAGS) smp_repro.s -o $@
smp_bringup.elf: smp_bringup.s link.x
	$(CC) $(CFLAGS) $(LDFLAGS) smp_bringup.s -o $@
%.img: %.elf
	$(OBJCOPY) -O binary $< $@
clean:
	rm -f *.elf *.img
.PHONY: all clean
