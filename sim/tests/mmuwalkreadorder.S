! mmuwalkreadorder.S -- CONTRACT LOCK C3 (docs/mmu/pagemask-walker-contract.md
! sections 3(d), 4 and 7.2). Lane 1, cpu_tb.
!
! READ THE DIVISION OF LABOUR FIRST -- THIS GUARD IS ONE HALF OF C3.
! ==================================================================
! C3 is specified as "Lane 1 PLUS a testbench assertion". The DETECTOR is
! `p_walk_read_order` in core/tlb_walk.vhd, a permanently-asserted,
! simulation-only monitor over the walker's OBSERVABLE bus sequence: for any
! one way it requires the address offsets +0, +4, +8 in that order, and +8
! never before +0. THIS FILE IS THE DRIVER. Its own result codes say nothing
! about read order; its job is to make EVERY shape of walk actually happen, in
! one image, so the monitor has something to observe.
!
! That split is forced by the nature of the defect. `tag_hi` is the COMMIT
! POINT of the torn-write protocol (data, then tag_lo, then a barrier, then
! tag_hi). Reading `data` first -- the rejected alternative 3(d), which is
! tempting because it would let the walker know `pm` at compare time -- makes a
! walk landing mid-store read the OLD data and then the NEW, matching tag_hi,
! and install a stale PTEL under a legitimate tag. BOTH WORDS ARE INDIVIDUALLY
! WELL-FORMED, so no software-visible state distinguishes it: a torn entry is
! by construction indistinguishable to hardware. No assertion this .S file
! could make would catch it. The RTL monitor is the only mechanised defence,
! and a violation ends the run with its own named report string rather than
! with a result code.
!
! THE FIVE WALK SHAPES (contract section 4's read-count table)
!   A  VA 0x0011_0000  way-0 hit                       3 reads
!   B  VA 0x0012_0000  way-0 tag_hi mismatch, way-1 hit  4 reads
!   C  VA 0x0013_0000  way-0 tag_lo reject,   way-1 hit  5 reads
!   D  VA 0x0014_0000  way-0 data reject (V=0), way-1 hit 6 reads  <- worst case
!   E  VA 0x0015_0000  both ways tag_hi mismatch        2 reads, then the miss
!                      exception, which is the only path that leaves the FSM
!                      through the give-up exit rather than through st_install
!
! A..D also carry ordinary data assertions, so this file is a real guard in its
! own right and not merely a stimulus generator: each case must return the
! sentinel at its own RELOCATED physical address, and the four together must
! move cnt_hits by exactly 4. E must fault exactly once with DMISS_R and
! TEA = 0x0015_0000, moving cnt_walks but not cnt_hits.
!
! COUNTER TRUSTWORTHINESS (contract P1). Case E's pass condition includes a
! NON-increment (cnt_hits unchanged), which a dead counter satisfies. It is
! paired in the same run with A..D's exact +4 cnt_hits assertion and with case
! E's own cnt_walks increment. Self-contained; P1g is not required.
!
! IDENTITY MAPPING. No page under test is identity-mapped
! (VA 0x0011_0000 -> PA 0x0071_0000 and so on), and every VA-as-physical
! address is seeded with poison, so an inert MMU fails check 0x81 immediately.
! The CODE page (VA 0x1000 -> PA 0x1000) is identity, forced by the flat image
! load (README-identity-mapping.md category (b)); nothing here depends on it.
!
! P5 (VA-backing). Every VA touched under AT=1 is below 0x0016_0000, inside the
! cosim's 16 MB backed window. Case E deliberately misses, so its raw VA
! reaches the bus during the miss window; it is backed.
!
! RESULT CODES (base 0x80)
!   0x81..0x84  wrong data in case A / B / C / D
!   0x85  case E: no fault -- a way was accepted although both tags mismatch
!   0x86  case E: EXPEVT is not DMISS_R
!   0x87  case E: TEA is not 0x0015_0000
!   0x88  cases A..D: cnt_hits delta != 4
!   0x89  case E: cnt_hits MOVED -- something was accepted
!   0x8A  case E: cnt_walks did NOT move -- no walk, or the counter is dead
!   0x8B  an UNEXPECTED fault during cases A..D
!   0xE9  TRIP: a second fault (contract P2 fallback range, phase = 9)
!   0xD1  unexpected GENERAL exception (VBR+0x100); a MULTI_HIT lands here
!
! MUTATION EVIDENCE
! =================
! M6 -- THE STATED MUTATION, rejected alternative 3(d): the walker reads
!       `data` (+8) before `tag_hi` (+0). Applied by reordering the FSM --
!       st_idle -> st_data, st_data -> st_tag_hi, st_tag_lo -> st_install,
!       st_next_way -> st_data -- so the per-way bus sequence becomes
!       +8, +0, +4 while the walk still installs.
!
!       RESULT: the run ends at 3760 ns with
!
!         ../core/tlb_walk.vhd:427:15:@3760ns:(assertion failure):
!         WALK READ ORDER VIOLATED: data (+8) read before ...
!         instance: /cpu_tb/cpu1/g_tlb_walk/u_tlb_walk/p_walk_read_order
!
!       That is a NAMED, self-identifying failure that cannot be conflated with
!       another guard's, and at 3.76us it is 32x inside the 120us stop-time --
!       it is the counter firing, not a timeout. All five Group-C locks fail
!       under M6, as they must: the assertion is a global invariant, so it
!       fires on the first walk of any image.
!
! The monitor's own PRECONDITION is asserted, not gated. It decodes the word
! offset from bus_a(3 downto 2) and the way select from bus_a(4), which is the
! entry layout only at entry_bytes = 16. That is checked by an unconditional
! `severity failure` assertion in the same process rather than being folded
! into the sample condition, because a gate would SILENTLY SWITCH THE MONITOR
! OFF at any other width -- a guard that stops checking when its precondition
! moves, which is the vacuity pattern this whole contract exists to eliminate.
! Confirmed not to false-fire: the full suite is green with it in place.
!
! SPECIFICITY -- every other mutation leaves this guard GREEN, so it is not a
! guard that simply dislikes RTL edits:
!       M1 (coarse tag accepted)                     PASS
!       M2 (MBZ term deleted)                        PASS
!       M3 (page_mask hardwired to "0000")           PASS
!       M4 (vpn_compare_mask("0000") off n=0)        PASS
!       M7 (the two mask functions agree above pm=8) PASS
!
! RESTORED: pristine RTL, PASS.
! All runs: docker ghcr.io/mountain-reverie/jcore-cpu-ci:latest, CPU_VARIANT=j4,
! SIM_TOP=cpu_tb, --stop-time=120us, measured 2026-08-22. Every mutation run
! REBUILT the cosim (never `-n`, which skips the build and measures stale
! hardware). To re-apply any mutation, follow the repro block in
! docs/mmu/group-c-locks.md section 9; that file also carries the full
! cross-table and, per row, whether it has been independently
! reproduced or rests on this record alone.
!
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

        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed physical memory from the (PA, value) table, AT off. ----
        mov.l   p_seed, r14
        mov.l   p_seed_end, r5
1:      mov.l   @r14+, r0
        mov.l   @r14+, r1
        mov.l   r1, @r0
        cmp/hs  r5, r14
        bf      1b

        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR = 0
        nop
        nop

        ! ---- Code page -> WAY 1 of ITS set (set 0x01, which none of the five
        ! ---- cases uses -- their VPNs hash to 0x14/0x24/0x34/0x05/0x15).
        mov.l   p_tsbslot_reg, r12
        mov.l   p_pteh_code, r6
        mov     #0, r7
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12
        mov.l   @r12, r10
        tsb_fill_way r10, 16, r6, r7, r8

        ! ---- WAY 0 rows, from a (setVA, tag_hi, tag_lo, PTEL) table. The tag
        ! ---- is written SEPARATELY from the VA whose set is used, which is
        ! ---- what lets a row be deliberately wrong in exactly one field.
        mov.l   p_w0, r14
        mov.l   p_w0_end, r5
1:      mov.l   @r14+, r6              ! VA whose SET this row goes in
        mov.l   @r14+, r1              ! tag_hi
        mov.l   @r14+, r7              ! tag_lo
        mov.l   @r14+, r8              ! PTEL
        mov.l   r6, @r12
        mov.l   @r12, r10
        tsb_fill r10, r1, r7, r8
        cmp/hs  r5, r14
        bf      1b

        ! ---- WAY 1 rows, same table shape. tsb_fill_way's way offset is an
        ! ---- assembly-time displacement, so the two ways need two passes.
        mov.l   p_w1, r14
        mov.l   p_w1_end, r5
1:      mov.l   @r14+, r6
        mov.l   @r14+, r1
        mov.l   @r14+, r7
        mov.l   @r14+, r8
        mov.l   r6, @r12
        mov.l   @r12, r10
        tsb_fill_way r10, 16, r1, r7, r8
        cmp/hs  r5, r14
        bf      1b

        mov     #0, r10                 ! fault count
        mov     #0, r14                 ! 0 = cases A..D, 5 = case E
        bra     _run
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_gen - 0x100
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000CD
p_tsbslot_reg:  .long 0xFF000048
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061
p_seed:         .long _seed_tab
p_seed_end:     .long _seed_tab_end
p_w0:           .long _w0_tab
p_w0_end:       .long _w0_tab_end
p_w1:           .long _w1_tab
p_w1_end:       .long _w1_tab_end

        .balign 4
        ! setVA        tag_hi       tag_lo       PTEL
_w0_tab:
        .long 0x00110000, 0x00110000, 0x00000000, 0x007100E9  ! A: way-0 HIT
        .long 0x00120000, 0x00999000, 0x00000000, 0x007200E9  ! B: tag_hi wrong
        .long 0x00130000, 0x00130000, 0x00000077, 0x007300E9  ! C: tag_lo wrong
        .long 0x00140000, 0x00140000, 0x00000000, 0x007400E8  ! D: V=0 in data
        .long 0x00150000, 0x00998000, 0x00000000, 0x007500E9  ! E: tag_hi wrong
_w0_tab_end:
_w1_tab:
        .long 0x00120000, 0x00120000, 0x00000000, 0x007200E9  ! B: way-1 HIT
        .long 0x00130000, 0x00130000, 0x00000000, 0x007300E9  ! C: way-1 HIT
        .long 0x00140000, 0x00140000, 0x00000000, 0x007400E9  ! D: way-1 HIT
        .long 0x00150000, 0x00997000, 0x00000000, 0x007500E9  ! E: also wrong
_w1_tab_end:

        .balign 4
_seed_tab:
        .long 0x00710000, 0xADD0A001    ! A relocated
        .long 0x00720000, 0xADD0B002    ! B relocated
        .long 0x00730000, 0xADD0C003    ! C relocated
        .long 0x00740000, 0xADD0D004    ! D relocated
        .long 0x00110000, 0xDEAD0BAD    ! poison at the untranslated addresses
        .long 0x00120000, 0xDEAD0BAD
        .long 0x00130000, 0xDEAD0BAD
        .long 0x00140000, 0xDEAD0BAD
        .long 0x00150000, 0xDEAD0BAD
_seed_tab_end:

ENTRY(_run)
        mov.l   q_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! AT on
        nop
        nop
        nop
        nop

        mov.l   q_warm, r7              ! warm the DTLB for the code page

        ! ============ CASES A..D: four different walk shapes ============
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13
        mov.l   q_ad_tab, r14
        mov     #4, r11
        mov     #0x81, r12
        bsr     _chk
        nop
        mov     #0, r14                 ! r14 is the phase marker again

        ! cnt_hits must have advanced by EXACTLY 4 -- four walks, four
        ! installs, one per case, none of them resolved any other way.
        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        extu.w  r1, r1
        mov     r13, r2
        extu.w  r2, r2
        sub     r2, r1
        mov     #4, r0
        cmp/eq  r1, r0
        mov     #0x88, r9
        bf      _fail_at

        ! ============ CASE E: both ways mismatch -> the miss exception =====
        mov     #5, r14
        mov.l   q_walkcnt, r0
        mov.l   @r0, r13
        mov.l   q_va_e, r0
        mov.l   @r0, r6                 ! <-- must FAULT

        mov     #0x85, r9               ! fell through: a way was accepted
        bra     _fail_at
        nop

_final:
        mov.l   q_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _done
        nop

        ! ---- _chk: r14 clobbered as the table pointer, r11 = count,
        ! ---- r12 = the result code of the first entry.
_chk:
1:      mov.l   @r14+, r0
        mov.l   @r14+, r3
        mov.l   @r0, r1                 ! <-- the access under test
        cmp/eq  r1, r3
        bf      _chk_bad
        add     #1, r12
        dt      r11
        bf      1b
        rts
        nop
_chk_bad:
        mov     r12, r9
        bra     _fail_at
        nop

_fail_at:
        mov.l   q_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _fail
        nop

        .align 2
q_mmucr:        .long 0xFF000010
q_warm:         .long 0x00000000
q_walkcnt:      .long 0xFF000054
q_ad_tab:       .long _ad_tab
q_va_e:         .long 0x00150000

        .balign 4
_ad_tab:
        .long 0x00110000, 0xADD0A001    ! 0x81  A  way-0 hit
        .long 0x00120000, 0xADD0B002    ! 0x82  B  way-0 tag_hi mismatch
        .long 0x00130000, 0xADD0C003    ! 0x83  C  way-0 tag_lo reject
        .long 0x00140000, 0xADD0D004    ! 0x84  D  way-0 data reject (V=0)

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
        ! `mov #imm, Rn` SIGN-EXTENDS 8 bits, and this guard's codes reach into
        ! the 0x80/0x90 band, so 0x85 would otherwise be reported as
        ! 0xFFFFFF85. Normalise here rather than at every use site; every code
        ! this file can emit fits in a byte.
        extu.b  r9, r9
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
        .balign 0x100
_v_gen:
        mov.l   Hg_code, r9
        bra     _fail
        nop
        .align 2
Hg_code:        .long 0x000000D1

        .space  0x300 - (. - _v_gen)
_v_fault:                               ! = VBR + 0x400
        add     #1, r10
        mov     r10, r0
        cmp/eq  #1, r0
        bt      _first_fault
        mov.l   H_trip, r9
        bra     _fail_at
        nop

_first_fault:
        mov     r14, r0
        cmp/eq  #5, r0
        bt      _e_fault
        mov     #0x8B, r9               ! a fault in cases A..D
        bra     _fail_at
        nop

_e_fault:
        mov.l   H_expevt, r0
        mov.l   @r0, r1
        mov.l   H_dmiss_r, r2
        cmp/eq  r1, r2
        mov     #0x86, r9
        bf      _fail_at

        mov.l   H_tea, r0
        mov.l   @r0, r1
        mov.l   H_va_e, r2
        cmp/eq  r1, r2
        mov     #0x87, r9
        bf      _fail_at

        mov.l   H_walkcnt, r0
        mov.l   @r0, r11

        ! cnt_hits must NOT have moved -- neither way may be accepted.
        mov     r11, r1
        extu.w  r1, r1
        mov     r13, r2
        extu.w  r2, r2
        cmp/eq  r1, r2
        mov     #0x89, r9
        bf      _fail_at

        ! cnt_walks MUST have moved -- the increment half of contract P1's
        ! pairing rule, without which a dead counter satisfies the check above.
        mov     r11, r1
        shlr16  r1
        mov     r13, r2
        shlr16  r2
        cmp/eq  r1, r2
        mov     #0x8A, r9
        bt      _fail_at

        ! Deliberately NOT an RTE: case E has no mapping by design.
        bra     _final
        nop

        .align 2
H_trip:         .long 0x000000E9
H_expevt:       .long 0xFF000024
H_dmiss_r:      .long 0x00000060
H_tea:          .long 0xFF00000C
H_va_e:         .long 0x00150000
H_walkcnt:      .long 0xFF000054

        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
