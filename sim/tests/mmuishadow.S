! mmuishadow.S -- an ITLB fill also fills the DTLB (one-way, I -> D).
!
! The walker installs into the faulting side only (cpu.vhd's itlb_wr/dtlb_wr
! routing). That is right for a D-side miss, but wrong-by-omission for an
! I-side one: SH code pages carry PC-relative literal pools, so a page that
! was just FETCHED is about to be READ, and under side-only routing that read
! costs a second full walk of the same TSB entry. The shadow fill installs the
! same PTE into the DTLB one cycle after the ITLB, so the literal-pool load
! hits. The reverse direction is deliberately NOT done -- see cpu.vhd.
!
! Construction, inherited from mmuwalkiside.S: the observed page is `.tlbtext`,
! linked by sim/tests/sh32_tlbtext.x at 0x00008000 (identity VA == PA), present
! in the TSB and absent from both TLBs. Jumping to it is an I-side miss; the
! walk that resolves it is the ONLY walk that should ever be needed for the
! page.
!
! THE MEASUREMENT IS ORDER-CRITICAL. The walk counter lives at P4 0xFF000054
! ([31:16]=walks [15:0]=hits), and P4 is untranslated, so reading it is not
! itself a D-side access to the observed page. But `mov.l p_counter, r0` WOULD
! be: a PC-relative literal load is exactly the access under test, and doing
! one before the baseline is captured hides the very event this guard exists to
! see. The prologue at _target therefore builds 0xFF000054 from immediates
! (mov #-1 / shll16 / shll8 / add) and touches NO literal until the baseline is
! in a register. Adding an innocent-looking `mov.l` to that prologue makes this
! guard pass unconditionally.
!
! Slot arithmetic, using mmutsb.S's documented hash:
!   VA 0x00008000 -> vpn 0x08, hash 0x08^(0x08>>6)=0x08, idx 0x08 -> 0x00010100
!
! Result codes:
!   1  target never executed -- the fetch was lost (or the guard fell through)
!   2  SPC moved -- an exception was taken instead of a walk
!   3  the walk counter did not advance -- the walker never ran at all
!   4  THE DEFECT: the counter advanced again on the literal-pool load, so the
!      ITLB fill did not shadow into the DTLB and the page was walked twice
!   5  an exception was taken on the literal-pool load itself
!
#include "sim_instr.h"
#include "mmuwalk_common.inc"
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

        .text
ENTRY(start)
#if CONFIG_PRIV_ARCH

        ! r9 carries the result code, and the fault stub below distinguishes
        ! "faulted before the probe" (code 2) from "the probe itself faulted"
        ! (code 5) by whether the target code has pre-loaded it. That test is
        ! only meaningful if r9 starts at a known zero.
        mov     #0, r9

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_fault - 0x400 ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Fill the slot the I-side walk will probe for VA 0x00008000. ----
        mov.l   p_tsb_slot, r0
        mov.l   p_vpn,  r1
        mov.l   p_asid, r2
        mov.l   p_ptel_x, r3
        tsb_fill r0, r1, r2, r3

        ! ---- Seed the SPC sentinel, then enable AT. ----
        mov.l   p_sent_spc, r0
        .word   0x404E                  ! LDC r0, SPC

        ! ---- Code page for THIS text: a GLOBAL TSB entry in way 1, installed
        ! ---- by the walker on the first fetch after AT goes on. Way 1 so it
        ! ---- cannot displace the way-0 entry placed above. U=0 (SMEP). ----
        mov.l   p_tsbslot_reg, r12
        mov.l   p_pteh_code, r6         ! VA = PA = start (4 KB-aligned)
        mov     #0, r7
        mov     r7, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        tsb_fill_way r10, 16, r6, r7, r8

        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Jump into the unmapped page: I-fetch miss, walker resolves. ----
        mov.l   p_target, r0
        jmp     @r0
        nop

        mov     #1, r9                  ! fell through -> target never executed
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _fail
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_fault - 0x400
p_mmucr:        .long 0xFF000010
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000CD ! identity: PPN=start, U cleared (SMEP)
p_tsbslot_reg:  .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsb_slot:     .long 0x00010100        ! hash(0x00008000) -- see header
p_vpn:          .long 0x00008000
p_asid:         .long 0x00000000
p_ptel_x:       .long 0x000080C9        ! PA 0x00008000 | W|X|C|V, U=0 (SMEP)
p_sent_spc:     .long 0xDEADBE00
p_target:       .long _target

#else
        bra     _done
        nop
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:      .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH
        ! MISS-vector stub at VBR+0x400. Reaching it before the probe means an
        ! exception was taken where the walker should have resolved the fetch
        ! (code 2); reaching it after means the literal-pool load itself
        ! faulted (code 5). r9 is pre-loaded by the target code, so the stub
        ! only supplies the default.
        .balign 4
        .space 0x600, 0
        .balign 4
_v_fault:                                ! = VBR + 0x400
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        tst     r9, r9
        bf      1f
        mov     #2, r9
1:
        bra     _fail
        nop

        .align 2
H_mmucr:        .long 0xFF000010

        ! Force .text alignment to 4 KB so `start` is page-aligned.
        .balign 0x1000
_pad_page:
        .space 0x1000, 0

! ======================================================================
! Translated-only code. Linked at VA 0x00008000 by sh32_tlbtext.x, absent
! from both TLBs, reachable only if the walker installs the TSB entry above.
!
! _done/_fail are ~28 KB away, well outside bra's +/-4 KB displacement, so
! the exits use mov.l + jmp -- which are themselves literal loads, and so are
! only safe AFTER the measurement is complete.
! ======================================================================
        .section .tlbtext, "ax"
        .balign 4
_target:
        ! ---- Baseline, with NO literal touched yet. See the header: the
        ! ---- address is built from immediates precisely so that the first
        ! ---- D-side access to this page is the probe below and nothing else.
        ! ---- -1 -> 0xFFFFFFFF, <<16 -> 0xFFFF0000, <<8 -> 0xFF000000.
        mov     #5, r9                  ! default code if the probe faults
        mov     #-1, r0
        shll16  r0
        shll8   r0
        add     #0x54, r0               ! 0xFF000054: [31:16]walks [15:0]hits
        mov     r0, r14                 ! keep the address; no reload needed
        mov.l   @r14, r11               ! r11 = counters after the I-side walk

        ! ---- 3: did the walker actually run? If the fetch of this page cost
        ! ---- no walk at all the whole guard is vacuous.
        tst     r11, r11
        bf      1f
        mov     #3, r9
        bra     _t_exit_fail
        nop
1:
        ! ---- THE PROBE. A PC-relative literal load from this same page: the
        ! ---- D side's first ever access to VA 0x00008xxx. With the shadow
        ! ---- fill it hits the DTLB; without it, it misses and walks.
        mov.l   t_probe_val, r1

        ! ---- 4: the counters must not have moved. Full 32-bit compare, so a
        ! ---- second walk is caught whether it hit or missed in the TSB.
        mov.l   @r14, r12
        cmp/eq  r11, r12
        bt      2f
        mov     #4, r9
        bra     _t_exit_fail
        nop
2:
        ! ---- The probe read what it should have, i.e. the DTLB translation
        ! ---- installed by the shadow fill maps to the right page. A wrong-VPN
        ! ---- shadow install would translate this load elsewhere. The
        ! ---- reference is built from an IMMEDIATE, never loaded from this
        ! ---- page: a second literal would be mistranslated in exactly the
        ! ---- same way as the first and the compare would pass regardless.
        mov     #0x7B, r2
        cmp/eq  r1, r2
        bt      3f
        mov     #4, r9
        bra     _t_exit_fail
        nop
3:
        ! ---- 2: SPC untouched -> no exception was entered on the way here.
        .word   0x0042                  ! STC SPC, r0
        mov.l   t_sent_spc, r1
        cmp/eq  r0, r1
        bt      4f
        mov     #2, r9
        bra     _t_exit_fail
        nop
4:
        mov.l   t_mmucr, r0             ! AT off (identity below, so execution
        mov     #0, r1                  ! continues at PA == VA unchanged)
        mov.l   r1, @r0
        mov.l   t_done, r0
        jmp     @r0
        nop

_t_exit_fail:
        mov.l   t_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov.l   t_fail, r0
        jmp     @r0
        nop

        .align 2
t_probe_val:    .long 0x0000007B        ! value the probe must read back
t_sent_spc:     .long 0xDEADBE00
t_mmucr:        .long 0xFF000010
t_done:         .long _done
t_fail:         .long _fail

#endif  ! CONFIG_PRIV_ARCH
