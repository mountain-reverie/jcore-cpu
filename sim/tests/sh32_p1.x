/**************************************************************************
 sh32_p1.x -- linker script for sim/tests/mmulinux.elf ONLY.

 Links the whole harness image (mmulinux.o + the real linux@jcore objects
 tlb-jcore.o/ex.o/entry.o) with VMA = P1 (0x80000000 | phys) but LMA =
 phys (0x0-based), via GNU ld's "> region AT> region" idiom. The .img is
 still produced as a physical (LMA) image and loaded at physical 0 by the
 cosim exactly like sh32.x's flat P0 link, but every symbol/literal
 (jcore_vbr_base, jcore_tlb_fault_entry, kmain, ...) now evaluates to its
 P1 VMA -- so an I-fetch of ANY linked code is a plain P1 (untranslated)
 bus access under MMUCR.AT=1, matching how the real kernel runs (kernel
 text lives at P1/PAGE_OFFSET=0x80000000, never subject to TLB
 translation). This removes the need for the "jmp to a manually-OR'd P1
 alias" trampoline sh32.x-linked harnesses used, and is what makes the
 real jcore_tlb_real_fault -> jcore_tlb_fault_entry tail (entered under
 SR.BL=1, i.e. no further TLB-miss exceptions can be taken) safe: its
 `mov.l 4f,r0 ; jmp @r0` literal is now a P1 address, not a P0 address
 that would itself I-side TLB-miss while already in the fault handler.

 Workload VAs (VA_A/B/C, 0x00100000 et al) are NOT linker symbols -- they
 are harness-chosen literal constants in .data/.text and are unaffected
 by this script; they remain genuine P0 addresses for the walker to
 translate, which is the entire point of the test.
 **************************************************************************/

OUTPUT_FORMAT("elf32-sh")
OUTPUT_ARCH(sh)

MEMORY
{
	ram_p1 (rwx) : ORIGIN = 0x80000200, LENGTH = 0x00020000
	ram    (rwx) : ORIGIN = 0x00000000, LENGTH = 0x00000200
	stack  (rw)  : ORIGIN = 0x00007d00, LENGTH = 0x0300
}

SECTIONS
{
/* .vect MUST be linked VMA==LMA==low-physical (region "ram", no AT>): the
   simulator's parse_sim_instructions() (sim/cpu_ctb.c) recovers num_vals
   purely arithmetically from the *absolute address* of the self-referential
   _sim_instr_end label ((addr(_sim_instr_end)/4) - 66) -- i.e. it assumes
   addr(_sim_instr_end) == its own file byte offset, which only holds if
   .vect's VMA equals its LMA (physical/file placement). This is a
   cpu_ctb.c-wide assumption shared by every P0-linked sh32.x test too, so
   .vect keeps that placement here rather than moving to P1 -- it is pure
   header data (reset vectors + sim_instr magic block), never itself
   fetched/executed as code past reset, so this has no bearing on the P1
   fault-path fix below. */
.vect : {
	*(.vect)
	} > ram

/* .textlo: the `start` trampoline ONLY (mmulinux.S), also kept low/P0
   (VMA==LMA, region "ram", contiguous right after .vect). Empirically
   required: pointing the reset vector (.vect's `.long start`) straight at
   a P1 (0x8000xxxx) address makes the CPU's very first post-reset fetch
   produce an X on the data bus at cycle 1 (bus_monitor "address has an
   X"/"Writing without address" -> permanent bus-exception hang) -- seen
   with plain scenarios 1-3 too, so it is a reset-from-P1 artifact, not
   scenario-4/5 content. Booting from a low vector for a few cycles before
   jumping into P1-linked code (exactly like every other harness in this
   tree) avoids it. */
.textlo : AT (ADDR(.vect) + SIZEOF(.vect)) {
	*(.textlo)
	} > ram

/* CRITICAL INVARIANT: each P1 section's LMA (its byte offset in the flat
   .img, which the cosim loads at physical 0) MUST equal its VMA folded to
   the physical address the hardware fetches from -- i.e. VMA & 0x1FFFFFFF.
   The core's g_inst_p1_fold (core/cpu.vhd) translates a P1 instruction VA
   0x8xxxxxxx to PA = VA & 0x1FFFFFFF; the fetch then reads that PA out of
   backing RAM. So the section's physical bytes must be sitting at exactly
   VA & 0x1FFFFFFF. Setting LMA = ADDR(section) & 0x1FFFFFFF enforces this
   for every section, self-consistently, with no LMA-cursor dependency.

   (An earlier revision chained LMA sequentially off .textlo -- e.g. .text
   VMA 0x80000000 but LMA 0x128 -- so the fold read PA 0x0 (the .vect table)
   instead of kmain's real bytes at 0x128: the CPU executed garbage after a
   few benign vector-table words and the fetch pipeline stalled. ram_p1 now
   ORIGINs at 0x80000200 so every P1 PA (>= 0x200) clears the low .vect +
   .textlo region (< 0x128) with no LMA collision.) */
.text : AT (ADDR(.text) & 0x1FFFFFFF) {
	*(.text)
	*(.strings)
	_etext = . ;
	} > ram_p1

.tors : AT (ADDR(.tors) & 0x1FFFFFFF) {
	___ctors = . ;
	*(.ctors)
	___ctors_end = . ;
	___dtors = . ;
	*(.dtors)
	___dtors_end = . ;
	} > ram_p1

.rodata : AT (ADDR(.rodata) & 0x1FFFFFFF) {
	*(.rodata*)
	} > ram_p1

.data : AT (ADDR(.data) & 0x1FFFFFFF) {
	_sdata = . ;
	*(.data)
	_edata = . ;
	} > ram_p1

.bss : AT (ADDR(.bss) & 0x1FFFFFFF) {
	_bss_start = .;
	*(.bss)
	*(COMMON)
	_end = .;
	} > ram_p1

.stack :
	{
	_stack = .;
	*(.stack)
	} > stack
}
