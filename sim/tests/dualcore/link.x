OUTPUT_FORMAT("elf32-sh")
OUTPUT_ARCH(sh)

MEMORY { ram : ORIGIN = 0x00000000, LENGTH = 0x00010000 }

SECTIONS {
  .text 0x0 : { *(.vect) *(.text*) *(.rodata*) } > ram
  .data : { *(.data*) } > ram
  .bss  : { *(.bss*) *(COMMON) } > ram
}
