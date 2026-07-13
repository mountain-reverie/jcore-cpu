! mmuidslot.S -- I-side TLB fault (IMISS) in a branch delay slot: does the
! restart land on the BRANCH or elsewhere? (J4 + MMU_ARCH). Companion to
! mmudslot.S (the data-side case). CONFIRMS the I-side restart is BUGGY.
!
! FINDING (measured 2026-07-06): the delay-slot fetch at VA 0x1000 IMISSes; the
! handler reads SPC = 0x100A = (branch target 0x100C) - 2, i.e. SPC = live PC-2
! where the live fetch PC has ALREADY been redirected to the branch TARGET by the
! time the delay-slot fetch misses. So the restart lands PAST the branch, not on
! it -- the branch is skipped / delay slot not re-issued, and execution then
! hangs. Correct behaviour = restart at the branch (0x0FFE), like SLOT_ILLEGAL.
!
! HARNESS REQUIREMENTS (learned the hard way):
!  * MUST run with the J4 overlay decoder active (via sim/mmu_sim.sh, or a manual
!    `make -C decode generate-j4`). A base-decoder run makes LDTLB/PTEH no-ops ->
!    AT never enables -> no fault.
!  * MUST keep SR.RB=0: the I-side TLB fault path is gated on dp_sr.rb='0'
!    (core/cpu.vhd). With RB=1 (reset default) I-fetches bypass the TLB.
!  * Branch DIRECTLY to the page-end branch (no nop sled): a sled lets the
!    icache/prefetcher pull page-1 lines in early and mask the miss.
!  * Progress markers are written to the PIO/LED port 0xABCD0000 (P2, prints
!    "LED: WRITE 0xNN"): 0x11=AT on, 0x33=handler entered, then SPC[7:0],SPC[15:8],
!    0x4C=idl_target (correct), 0x5D=fell through (bug).
!
! Layout (absolute VAs via .org in the VMA-0 image, like mmuicolor.S):
!   Page 0 (0x0000-0x0FFF): identity-mapped code/handler/literals.
!   Page 1 (0x1000-0x1FFF): UNMAPPED; the delay-slot fetch at 0x1000 -> IMISS.
!   The delayed branch sits at VA 0x0FFE (last halfword of page 0); its delay
!   slot is fetched at 0x1000. The handler installs page 1 and RTEs to SPC.
!
! J4 overlay opcodes:
!   LDC r0,PTEH=0x405E  LDC r0,PTEL=0x406E  LDC r0,ASIDR=0x407E
!   LDTLB=0x0038        LDC r0,VBR=0x402E

#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

        .section .vect
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

        ! Stay in .vect (linker VMA 0) so .org below places code at ABSOLUTE VAs.
ENTRY(start)
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0. REQUIRED: the I-side TLB fault path is gated on
        !      SR.RB='0' (core/cpu.vhd i_at_translated consumer). With RB=1 (reset
        !      default) I-fetches bypass the TLB and never IMISS. ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_imiss - 0x400 (so VBR+0x400 = _v_imiss). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Map page 0 (VA 0x0000-0x0FFF): identity, W+X+U+C = 0xE8. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0, ASID=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB

        ! ---- Page 1 (VA 0x1000-0x1FFF) is left UNMAPPED: the delay-slot fetch
        !      at 0x1000 misses -> IMISS. (X=0 no-execute does NOT fault in
        !      supervisor mode in this design, so IPROT is not usable here.) The
        !      handler installs page 1 and RTEs. ----

        ! ---- r14 = PIO/LED base (0xABCD0000, P2 fixed-translate) for progress
        !      markers; each 'mov.b r13,@r14' prints "LED: WRITE 0xNN". ----
        mov.l   p_pio, r14

        ! ---- Enable AT (MMUCR.AT=1 at P4 0xFF000010). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        mov     #0x11, r13              ! marker A: AT enabled
        mov.b   r13, @r14

        mov     #1, r9                  ! sentinel: no-exception = result 1
        mov     #0xAA, r3               ! sentinel: delay slot must overwrite r3 with 0x55
        ! Branch DIRECTLY to the page-end branch (no nop sled) so page 1 stays
        ! cold and the delay-slot fetch at 0x1000 genuinely misses -> IMISS.
        bra     critical
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_imiss - 0x400
p_mmucr:        .long 0xFF000010
p_ptel_page0:   .long 0x000000C8        ! W|X|C (U cleared: kernel code, SMEP)
p_pteh_page1:   .long 0x00001000        ! VPN = 1
p_ptel_nx:      .long 0x000000A8        ! W|U|C  (X=0 -> IPROT on fetch)
p_pio:          .long 0xABCD0000        ! PIO/LED marker port
p_critical:     .long critical

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

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

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ================================================================
        ! IMISS handler at VBR+0x400 = _v_imiss (on page 0). Installs a
        ! full-access mapping for page 1 and RTEs to the hardware SPC.
        ! ================================================================
        .balign 4
_v_imiss:                               ! = VBR + 0x400
        mov     #0x33, r13              ! marker B: I-side fault handler entered
        mov.b   r13, @r14
        .word   0x0042                  ! STC SPC, r0  (r0 = restart PC)
        mov     r0, r13
        mov.b   r13, @r14               ! emit SPC[7:0]: branch=0xFE, dslot=0x00
        .word   0x4019                  ! shlr8 r0
        mov     r0, r13
        mov.b   r13, @r14               ! emit SPC[15:8]: 0x10 => 0x10xx, 0x0F => 0x0Fxx
        mov.l   Hpteh1, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=1, ASID=0)
        mov.l   Hptel1, r0
        .word   0x406E                  ! LDC r0, PTEL  = 0xE8 (full access)
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        .word   0x0038                  ! LDTLB
        rte                             ! PC <- SPC (hardware value)
        nop

        .balign 4
Hpteh1:         .long 0x00001000        ! VPN = 1
Hptel1:         .long 0x000010C8        ! PA 0x1000 (identity) | W|X|C (kernel-fetched delay slot, SMEP)

        ! CORRECT landing: the branch target, on PAGE 0 (always mapped). Reached
        ! only if the branch is (re-)taken after the delay-slot fault is serviced.
        .balign 4
idl_target:
        mov     #0x4C, r13              ! marker C: branch taken (CORRECT)
        mov.b   r13, @r14
        ! Verify the delay slot actually executed: r3 must be 0x55 (set by the
        ! delay slot), not the 0xAA sentinel. If r3==0xAA the delay slot was
        ! SKIPPED on restart even though the branch was taken -> result 4.
        mov     #0x55, r0
        cmp/eq  r0, r3
        bf      _idslot_skipped
        mov     #0, r9
        bra     _done
        nop
_idslot_skipped:
        mov     #4, r9
        bra     _fail
        nop

        ! ================================================================
        ! Critical page-straddling region. The branch lands at VA 0x0FFE so
        ! its delay slot is fetched at VA 0x1000 (page 1, unmapped -> IMISS).
        ! ================================================================
        ! Nop sled on page 0: entered by branch, then falls through to the
        ! page-end branch at 0x0FFE.
        .org 0x0400
sled:
        mov     #0x5E, r13              ! marker E: reached sled (low page-0 addr)
        mov.b   r13, @r14
        .rept (0x0FFE-0x0404)/2
        nop
        .endr
critical:                               ! = VA 0x0FFE (last halfword of page 0)
        bra     idl_target              ! target on PAGE 0 (mapped); only the
                                        ! delay slot below (0x1000) faults.
        ! ---- VA 0x1000 (page 1, UNMAPPED): the delay slot instruction. Its
        !      fetch IMISSes. Only this fetch faults (target is on page 0). ----
        mov     #0x55, r3               ! delay slot (harmless)
        ! ---- VA 0x1002: fall-through (BUGGY landing: branch was skipped) ----
        mov     #0x5D, r13              ! marker D: fell through branch (BUG)
        mov.b   r13, @r14
        mov     #2, r9
        bra     _fail
        nop

        ! Ensure the image extends well past page 1 so the bus backs the
        ! page-1 fetches before the TLB exception fires.
        .org 0x1800

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
