! mmuboot.S -- SP3-c Task 3: cosim guard linking the REAL boot MMU-enable
! sequence (arch/sh/kernel/cpu/jcore/mmu_enable.S, jcore_mmu_enable, Task 2)
! and proving:
!
!   (1) the real enable sequence programs TSBBR/TSBCFG/ASIDR/PTEH/MMUCR and
!       returns without faulting (AT ends up on, nothing else disturbed);
!   (2) a translated access to a page whose TSB slot we install (mimicking
!       what a real TLB-miss handler's install step would do) actually
!       RELOCATES: the VA (0x00100000) and the backing PA (0x00071000) are
!       deliberately different, and the value read back is the one seeded
!       at the PA, not at the VA;
!   (3) a translated access to a page with NO TSB entry takes the real
!       TLB-miss vector (VBR+0x400) -- distinguishable from (2) by two
!       independent counters (install_cnt vs miss_cnt) so neither path can
!       silently substitute for the other.
!
! Unlike mmulinux.S (SP2), this harness does NOT link the real Linux TLB
! walker/entry objects -- Task 2 only factored out the boot enable stub, not
! a full fault handler -- so this file hand-rolls its OWN minimal vector
! table (same pattern as mmurun.S's ss4.1/4.2 hot/slow split), but calls the
! REAL jcore_mmu_enable for the enable step itself, per the input contract
! documented at the top of mmu_enable.S:
!
!   r4 = boot-TSB P1 base address (JCORE_BOOT_TSB_SIZE_LOG=8 is baked into
!        the routine -> 4096-byte / 256-slot boot TSB, 4096-byte aligned).
!        r0/r1 scratch, returns via rts with MMUCR=AT|TI written last.
!
! Slot format (3 live words + 1 pad, matches tlb-jcore.c / mmurun.S):
!   +0 tag_hi = VPN (faulting VA, page-aligned)
!   +4 tag_lo = ASID_TAG
!   +8 data   = PTEL image (PFN | flags)
!
! The miss handler here is deliberately NOT a general walker: it recognises
! exactly one known "should install" VA (k_va_a) and installs a
! hand-built PTE for it; any other faulting VA (k_va_b) is treated as
! "expected miss, no mapping" and control is redirected (jmp, never
! rte/resume -- same rationale as mmulinux.S's do_page_fault: retrying an
! unmapped access would just fault forever) back into the linear test flow.
!
! r9 fail codes:
!   1  first touch of va_A (mapped) didn't read back the seeded PA value
!   2  va_A's installed TSB slot tag_hi != va_A (install didn't run / wrong VA)
!   3  va_A's installed TSB slot tag_lo != 0 (ASID_TAG)
!   4  va_A's installed TSB slot data != expected PTEL image
!   5  install_cnt != 1 after the first (miss+install) touch
!   6  hit_cnt != 1 after the second (TLB-flushed, TSB-warm) touch
!   7  install_cnt changed on the warm-hit touch (walker/install re-ran)
!   8  second touch's readback != seeded PA value
!   9  miss_cnt != 1 after touching the unmapped VA
!   10 install_cnt changed on the unmapped touch (a mapping was installed
!      for a VA that must NOT have one)

#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

        .section .vect,"a"
        .long start
        .long 0x00007000
        .long start
        .long 0x00007000
        .rept 60
        .long 0
        .endr
        .long SIM_INSTR_MAGIC
        .long _sim_instr_end
        .long _done
        .long _fail
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .section .textlo,"ax"
ENTRY(start)
        mov.l   p_sp,    r15
        mov.l   p_kmain, r0
        jmp     @r0
        nop
        .align 2
p_sp:    .long 0x80090F00
p_kmain: .long kmain

        .text
kmain:
        ! ---- Ensure RB=0 (keep MD=1). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop

        ! ---- Zero bank-1 r0-r7 (our miss handler runs at SR.RB=1 and
        ! stores computed [not undefined] data through them, but zero them
        ! anyway -- same defensive pattern as mmulinux.S/mmurun.S: the
        ! ghdl SRAM model rejects a store of genuinely undefined data, and
        ! this is cheap insurance). ----
        mov.l   p_rbset,   r8
        mov.l   p_rbclear, r9
        stc     sr, r0 ; or  r8, r0 ; ldc r0, sr      ! -> RB=1
        nop ; nop
        mov     #0, r0 ; mov #0, r1 ; mov #0, r2 ; mov #0, r3
        mov     #0, r4 ; mov #0, r5 ; mov #0, r6 ; mov #0, r7
        stc     sr, r0 ; and r9, r0 ; ldc r0, sr      ! -> RB=0
        nop ; nop
        mov     #0, r4 ; mov #0, r5 ; mov #0, r6 ; mov #0, r7

        ! ---- ASIDR/PTEH will be set by jcore_mmu_enable itself; zero the
        ! GBR too (tidy, matches mmulinux.S). ----
        mov     #0, r0
        ldc     r0, gbr
        nop
        nop

        ! ---- Zero counters. ----
        mov.l   k_install_cnt, r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_hit_cnt,     r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_miss_cnt,    r0 ; mov #0, r1 ; mov.l r1, @r0

        ! ---- Zero the 4096-byte (256-slot) boot TSB (JCORE_BOOT_TSB_SIZE_LOG
        ! is baked into jcore_mmu_enable as 8 -> 16 << 8 = 4096 bytes). ----
        mov.l   k_tsb, r0
        mov.l   k_tsb_words, r2
        mov     #0, r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- Seed the backing PA (0x00071000, DELIBERATELY != va_A
        ! 0x00100000, so a correct readback after translation proves real
        ! relocation happened, not an identity-map coincidence). ----
        mov.l   k_backing_a, r0
        mov.l   v_seed_a,    r1
        mov.l   r1, @r0

        ! ---- VBR = P1 alias of our own miss-vector table. ----
        mov.l   k_vbr, r0
        ldc     r0, vbr
        nop
        nop

        ! ================= call the REAL jcore_mmu_enable =================
        mov.l   k_tsb, r4               ! r4 = boot-TSB P1 base (4096-aligned)
        mov.l   p_mmu_enable, r0
        jsr     @r0
         nop
        ! AT is now on (MMUCR=AT|TI written in jcore_mmu_enable's rts delay
        ! slot -- genuinely the last thing it does before returning).

        ! ================= touch #1: va_A, TSB empty -> miss -> install ===
        mov.l   k_va_a, r0
        mov.l   @r0, r8                 ! -> VBR+0x400 -> _h_slow installs
                                         ! va_A's PTE -> LDTLB.RN resumes
                                         ! the load in place.

        ! ---- Verify the installed TSB slot (TSBPTR still points at
        ! va_A's slot -- no further miss has happened yet). AT stays on;
        ! P1 accesses are untranslated regardless. ----
        stc     tsbptr, r3
        mov.l   @r3, r2
        mov.l   k_va_a, r1
        cmp/eq  r1, r2 ; mov #2, r9 ; bf _fail
        mov.l   @(4,r3), r2
        mov     #0, r1
        cmp/eq  r1, r2 ; mov #3, r9 ; bf _fail
        mov.l   @(8,r3), r2
        mov.l   k_ptel_a, r1
        cmp/eq  r1, r2 ; mov #4, r9 ; bf _fail

        mov.l   k_install_cnt, r0 ; mov.l @r0, r2 ; mov #1, r1
        cmp/eq  r1, r2 ; mov #5, r9 ; bf _fail

        ! ================= touch #2: TI-flush TLB (TSB warm), re-touch ====
        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0   ! AT|TI
        mov.l   k_va_a, r0
        mov.l   @r0, r10                ! -> miss -> _h_common TSB HIT ->
                                         ! LDTLB.RN, install_cnt untouched

        mov.l   k_hit_cnt, r0 ; mov.l @r0, r2 ; mov #1, r1
        cmp/eq  r1, r2 ; mov #6, r9 ; bf _fail
        mov.l   k_install_cnt, r0 ; mov.l @r0, r2 ; mov #1, r1
        cmp/eq  r1, r2 ; mov #7, r9 ; bf _fail

        ! ================= touch #3: unmapped VA -> real miss, no entry ===
        mov.l   k_mmucr, r0 ; mov #5, r1 ; mov.l r1, @r0   ! AT|TI (fresh miss)
        mov.l   k_va_b, r0
        mov.l   @r0, r11                ! -> VBR+0x400 -> _h_slow: VA !=
                                         ! va_A -> miss_cnt++, jmp after_miss
                                         ! (load never completes/resumes)
after_miss:

        ! ---- Disable AT before the final readbacks / result store. ----
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0

        ! ================= VERIFY =================
        mov.l   v_seed_a, r1 ; cmp/eq r1, r8  ; mov #1, r9 ; bf _fail
        mov.l   v_seed_a, r1 ; cmp/eq r1, r10 ; mov #8, r9 ; bf _fail
        mov.l   k_miss_cnt, r0 ; mov.l @r0, r2 ; mov #1, r1
        cmp/eq  r1, r2 ; mov #9, r9 ; bf _fail
        mov.l   k_install_cnt, r0 ; mov.l @r0, r2 ; mov #1, r1
        cmp/eq  r1, r2 ; mov #10, r9 ; bf _fail

        mov     #0, r9
        bra     _done
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_rbset:        .long 0x20000000
p_mmu_enable:   .long jcore_mmu_enable

k_install_cnt:  .long 0x80090100
k_hit_cnt:      .long 0x80090104
k_miss_cnt:     .long 0x80090108

k_tsb:          .long 0x80060000       ! 4096-byte, 4096-aligned boot TSB
k_tsb_words:    .long 1024             ! 4096 bytes / 4

k_backing_a:    .long 0x80071000       ! P1 alias of backing PA 0x00071000
v_seed_a:       .long 0xC0FFEE00

k_va_a:         .long 0x00100000       ! mapped test VA (P0)
k_ptel_a:       .long 0x000710F1       ! PFN(0x00071000) | V|C|U|W|D (0x0F1)
k_va_b:         .long 0x00200000       ! deliberately unmapped VA (P0)

k_vbr:          .long _vbase
k_mmucr:        .long 0xFF000010

ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:  .long TEST_RESULT_ADDRESS

! ===================== our own minimal miss-vector table ==================
! VBR points at the P1 alias of _vbase; hardware delivers all TLB faults to
! VBR+0x400 (I/D, miss/prot merged to one vector).
        .balign 4
_vbase:
        .space 0x400, 0
_v_tlb:                                 ! _vbase + 0x400 (all TLB faults)
        bra     _h_common
        nop

        ! ---- hot path: TSB tag match -> just LDTLB.RN. ----
_h_common:
        stc     tsbptr, r0
        mov.l   @r0, r1                 ! tag_hi
        stc     pteh, r2
        cmp/eq  r1, r2
        bf      _h_slow
        mov.l   @(4,r0), r1             ! tag_lo
        stc     asidr, r2
        cmp/eq  r1, r2
        bf      _h_slow
        mov.l   @(8,r0), r3             ! PTEL data
        mov.l   H_hit_cnt, r4
        mov.l   @r4, r5
        add     #1, r5
        mov.l   r5, @r4
        ldc     r3, ptel
        ldtlb.rn                        ! installs into the TLB + resumes
                                         ! the faulting instruction

        ! ---- slow path: only va_A is a known-good install; anything else
        ! is a deliberate miss with no mapping. ----
_h_slow:
        stc     pteh, r2
        mov.l   H_va_a, r1
        cmp/eq  r1, r2
        bf      _h_miss

        stc     tsbptr, r0
        mov.l   H_va_a,  r1 ; mov.l r1, @r0
        mov     #0, r1      ; mov.l r1, @(4,r0)
        mov.l   H_ptel_a, r1 ; mov.l r1, @(8,r0)
        mov.l   H_install_cnt, r3
        mov.l   @r3, r4
        add     #1, r4
        mov.l   r4, @r3
        ldc     r1, ptel
        ldtlb.rn                        ! installs + resumes

_h_miss:
        mov.l   H_miss_cnt, r3
        mov.l   @r3, r4
        add     #1, r4
        mov.l   r4, @r3

        ! ---- restore SR.RB=0 (this handler ran at RB=1) before handing
        ! control back to the RB=0 linear test flow -- we deliberately
        ! never rte/resume the faulting instruction (it has no mapping and
        ! would just fault forever); jmp straight back into kmain. ----
        stc     sr, r0
        mov.l   H_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        mov.l   H_after_miss, r0
        jmp     @r0
        nop

        .align 2
H_hit_cnt:      .long 0x80090104        ! == k_hit_cnt
H_install_cnt:  .long 0x80090100        ! == k_install_cnt
H_miss_cnt:     .long 0x80090108        ! == k_miss_cnt
H_va_a:         .long 0x00100000        ! == k_va_a
H_ptel_a:       .long 0x000710F1        ! == k_ptel_a
H_rbclear:      .long 0xDFFFFFFF        ! == p_rbclear
H_after_miss:   .long after_miss
