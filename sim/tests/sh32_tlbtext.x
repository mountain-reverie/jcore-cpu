/**************************************
 SuperH (SH-2) C Compiler Linker Script

 sh32_tlbtext.x -- sh32.x plus a .tlbtext output section fixed at VA
 0x00008000: the first page above the stack region, and one the MMU guards'
 identity code-page mapping does not cover.

 Used ONLY by mmuwalkiside.S, which needs code at a VA absent from the TLB so
 the hardware TSB walker has to fault it in on the I side. It is a separate
 script rather than an addition to sh32.x so every other guard image stays
 bit-identical.

 VMA == LMA (identity): the section is loaded where it is linked, so the
 guard's PTEL carries PPN 0x00008000. A VA/=PA mismatch here presents as
 "target never executed" and is easy to misread as a walker bug.
 **************************************/

OUTPUT_FORMAT("elf32-sh")
OUTPUT_ARCH(sh)

MEMORY
{
	ram    : o = 0x00000000, l = 0x200000
	stack  : o = 0x00007d00, l = 0x0300
}

SECTIONS 				
{
.text :	{
	*(.vect)
	*(.text) 				
	*(.strings)
   	 _etext = . ; 
	}  > ram

.tors : {
	___ctors = . ;
	*(.ctors)
	___ctors_end = . ;
	___dtors = . ;
	*(.dtors)
	___dtors_end = . ;
	}  > ram

.rodata : {
    *(.rodata*)
    } >ram

__idata_start = ADDR(.text) + SIZEOF(.text) + SIZEOF(.tors) + SIZEOF(.rodata); 
.data : AT(__idata_start) {
	__idata_start = .;
        _sdata = . ;
	*(.data)
	_edata = . ;
	}  > ram
__idata_end = __idata_start + SIZEOF(.data);

.bss : {
	_bss_start = .;
	*(.bss)
	*(COMMON)
	_end = .;
	}  >ram

.tlbtext 0x00008000 : {
	*(.tlbtext)
	} > ram

.stack :
	{
	_stack = .;
	*(.stack)
	} > stack
}
