OBJS := entry.o gdb.o sh2.o main.o version.o
OBJS += uartlite.o
#OBJS += uart16550.o

TESTS_OBJS := testbra.o
TESTS_OBJS += testmov.o testmov2.o testmov3.o
TESTS_OBJS += testalu.o
TESTS_OBJS += testshift.o
TESTS_OBJS += testmul.o testmulu.o testmuls.o testmull.o testdmulu.o testdmuls.o testmulconf.o
TESTS_OBJS += testdiv.o
TESTS_OBJS += testmacw.o testmacl.o
TESTS_OBJS := $(addprefix tests/,$(TESTS_OBJS))

CC = sh2-elf-gcc
LD = sh2-elf-ld
AR = sh2-elf-ar
RANLIB = sh2-elf-ranlib
ECHO = /bin/echo
LDFLAGS = -T startup/sh32.x -Map main.map
LIBGCC = $(shell $(CC) -print-libgcc-file-name)

# Freestanding ROM: no libc is linked (see LDFLAGS/LIBGCC below). GCC 14's
# loop-idiom recognition (-ftree-loop-distribute-patterns, on by default at
# -O2/-Os) can rewrite hand-written loops into calls to libc functions such
# as memcpy/memset/strlen -- notably gdb.c's own strl() gets turned into a
# call to strlen(), which then fails to link. Disable that idiom conversion;
# this is the same fix the Linux kernel carries for the same reason.
#
# -Wa,--isa=sh-j2: J-core code must be assembled AS J-core. -m2 selects
# generic SH-2 codegen for gcc, but generic SH-2 genuinely lacks the dynamic
# shifts shad/shld, which the J2 core does implement (see
# testrom/tests/testshift.s and sim/tests/shldshadguard.S). The assembler
# needs to be told the real ISA separately from the codegen model; the same
# pattern is already used in sim/tests/Makefile (-Wa,--isa=any / --isa=sh2a).
CFLAGS := -m2 -Wa,--isa=sh-j2 -g -Os -Wall -fno-tree-loop-distribute-patterns

DDR ?= ddr16
ifeq ($(DDR), lpddr)
	CFLAGS += -D LPDDR
else ifeq ($(DDR), ddr8)
	CFLAGS += -D DDR_BL4
endif

all: main.elf

tests/libtests.a: $(TESTS_OBJS)
	$(AR) -cur $@ $^
	$(RANLIB) $@
	@echo Built test library


main.elf: $(OBJS) tests/libtests.a
	$(LD) $(LDFLAGS) $(OBJS) -Ltests -ltests $(LIBGCC) -o $@

main.o: main.c
	$(CC) $(CFLAGS) -fno-inline -c $<

.s.o:
	$(CC) $(CFLAGS) -c $< -o $@

version.c:
	@printf "char version_string[] = \"revision: $(shell hg head | head -1)\\\\nbuild: $(shell date)\\\\n\";\n" > $@

clean:
	rm -f *.[oa] tests/*.o tests/libtests.a
	rm -f version.c
	rm -f main.srec main.elf *.map a.out

.PHONY: clean all
