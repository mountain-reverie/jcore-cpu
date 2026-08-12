! mmutsbvictim.S -- 2-way TSB sets and the OS-seeded victim selector
! (Phase-2 Task 4).
!
! Two independent things are checked here, because neither is observable
! through the other:
!
! A. WAY 1 IS REACHABLE. tsb_ptr() now returns a 32-byte-aligned SET address
!    and a set holds two 16-byte entries (way 0 at +0/+4/+8, way 1 at
!    +16/+20/+24). This guard puts the ONLY valid entry in way 1, leaves way 0
!    all-zero, and takes a TLB miss. A 1-way walker (or a `tsb_ways => 1`
!    generic left un-raised) probes way 0, sees tag_hi 0 != VPN, gives up, and
!    the MISS exception fires -- caught below as a diverted vector, and by the
!    SPC/SSR/EXPEVT sentinels. Only a genuinely 2-way walker passes.
!
! B. THE VICTIM SELECTOR IS LIVE AND OS-SEEDED. 0xFF00004C (TSBVSEED) is
!    WRITE-ONLY: it seeds the LFSR and reads back a hard zero, because a seed
!    software can read is a seed an attacker can read, and the whole reason
!    the seed comes from the OS is that a constant compiled into this
!    open-source core would be public. 0xFF000050 (TSBVICT) exposes ONLY the
!    1-bit way nomination, and each read advances the LFSR one step.
!
!    Checked: the seed does not read back (code 6); the nomination is not
!    stuck at a constant over 16 reads (code 7 -- this is the check that a
!    "always nominate way 0" mutation of tsb_lfsr_next() must break); and the
!    sequence DEPENDS ON THE SEED, i.e. two different seeds do not produce the
!    same 16 nominations (code 8). Code 8 is what stops a "selector" that
!    ignores its seed -- exactly the predictable-sequence failure the
!    write-only seed register exists to prevent -- from passing code 7.
!
! Setup is mmuwalkhit.S's, unchanged: same TSBBR=0x00010006 (TSB_SIZE_LOG=6,
! now counting SETS), TSBCFG=0x00000061, fault VA 0x00042000, which hashes to
! set 0x00010060 = 0x00010000 | (idx 0x03 << 5).
!
! Result codes:
!   1  load returned wrong data (way-1 entry never installed, or installed
!      wrong -- e.g. a walker reading way 1's words at the wrong offsets)
!   2  an exception was taken (VBR+0x400 stub entered, or SPC changed)
!   3  SSR changed  -> an exception was taken
!   4  EXPEVT changed -> an exception was taken
!   5  walk counter never advanced -> the walker never ran
!   6  TSBVSEED read back non-zero -> the seed is software-visible
!   7  TSBVICT nomination constant over 16 reads -> selector not running
!   8  two different seeds gave the same 16 nominations -> the seed is
!      ignored, so the sequence is predictable from public information
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

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_fault - 0x400. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed the data page (AT off, direct physical write). ----
        mov.l   p_data_pa, r2
        mov.l   p_expect, r3
        mov.l   r3, @r2                 ! [0x00042000] = 0xA5A5A5A5

        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0                 ! TSBBR  = 0x00010006
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0                 ! TSBCFG = 0x00000061

        ! ---- Zero the WHOLE 32-byte set explicitly. Relying on the memory
        ! ---- model's zero fill for way 0 would make check A vacuous the day
        ! ---- that fill changes: way 0 must provably NOT match. ----
        mov.l   p_tsb_set, r0
        mov     #8, r2
        mov     #0, r1
1:      mov.l   r1, @r0
        add     #4, r0
        dt      r2
        bf      1b

        ! ---- Fill WAY 1 ONLY (+16/+20/+24). ----
        mov.l   p_tsb_set, r0
        mov.l   p_vpn,  r1
        mov.l   p_asid, r2
        mov.l   p_ptel_data, r3
        tsb_fill_way r0, 16, r1, r2, r3

        ! ================= B: the victim selector ========================
        ! ---- 6: TSBVSEED must be write-only. ----
        mov.l   p_vseed_reg, r8
        mov.l   p_seed_a, r1
        mov.l   r1, @r8                 ! seed = 0x13579BDF
        mov.l   @r8, r1
        tst     r1, r1
        mov     #6, r9
        bf      _fail_at                ! non-zero readback -> seed is visible

        ! ---- Collect 16 nominations for seed A into r10 (bit i = read i). ----
        bsr     _collect
         nop
        mov     r0, r10

        ! ---- 7: not stuck at a constant. All-zero or all-one over 16 reads
        ! ---- means the LFSR is not advancing (or was mutated to a fixed
        ! ---- nomination), so way 1 would never be chosen as a victim. ----
        mov     #7, r9
        tst     r10, r10
        bt      _fail_at                ! all nominations were way 0
        mov.l   p_mask16, r1
        cmp/eq  r10, r1
        bt      _fail_at                ! all nominations were way 1

        ! ---- 8: the sequence must depend on the seed. ----
        mov.l   p_seed_b, r1
        mov.l   r1, @r8                 ! seed = 0x2468ACE0
        bsr     _collect
         nop
        cmp/eq  r0, r10
        mov     #8, r9
        bt      _fail_at

        ! ================= A: way 1 is reachable ========================
        ! ---- Code page: the identity mapping that LDTLB used to install is
        ! ---- now a GLOBAL TSB entry that the walker installs on the first
        ! ---- instruction fetch after AT goes on. GLOBAL so no ASID change can
        ! ---- perturb it; U=0 (SMEP). The set address is asked of the P4 slot
        ! ---- helper (0xFF000048 -- the single tsb_ptr() implementation the
        ! ---- walker and TSBPTR also use), never hand-computed. WAY 1, so it
        ! ---- cannot displace the entries this guard places in way 0. ----
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

        ! ---- Enable AT (MMUCR.AT=1). ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Seed the no-exception sentinels. ----
        mov.l   p_sent_spc, r0
        .word   0x404E                  ! LDC r0, SPC
        mov.l   p_sent_ssr, r0
        .word   0x403E                  ! LDC r0, SSR

        ! ---- Take the miss: the walker must probe way 0 (no match), then
        ! ---- way 1 (match), install, and replay -- with NO exception. ----
        mov.l   p_testva, r0
        mov.l   @r0, r4

        ! ---- 1: right data? ----
        mov.l   p_expect, r5
        cmp/eq  r4, r5
        mov     #1, r9
        bf      _fail_at

        ! ---- 2: SPC untouched? ----
        .word   0x0042                  ! STC SPC, r0
        mov.l   p_sent_spc, r1
        cmp/eq  r0, r1
        mov     #2, r9
        bf      _fail_at

        ! ---- 3: SSR untouched? ----
        .word   0x0032                  ! STC SSR, r0
        mov.l   p_sent_ssr, r1
        cmp/eq  r0, r1
        mov     #3, r9
        bf      _fail_at

        ! ---- 4: EXPEVT still at its reset value? ----
        mov.l   p_expevt, r0
        mov.l   @r0, r1
        tst     r1, r1
        mov     #4, r9
        bf      _fail_at

        ! ---- 5: did the walker actually run? ----
        mov.l   p_walkcnt, r0
        mov.l   @r0, r1
        tst     r1, r1
        mov     #5, r9
        bt      _fail_at

        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _done
        nop

_fail_at:
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
p_data_pa:      .long 0x00042000
p_expect:       .long 0xA5A5A5A5
p_tsb_set:      .long 0x00010060        ! set for VA 0x00042000: idx 3 << 5
p_vpn:          .long 0x00042000
p_asid:         .long 0x00000000
p_ptel_data:    .long 0x000420E9        ! PA 0x00042000 | V|C|U|X|W (0xE9)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6 (SETS)
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_testva:       .long 0x00042000
p_sent_spc:     .long 0xDEADBE00
p_sent_ssr:     .long 0x40000000
p_expevt:       .long 0xFF000024
p_walkcnt:      .long 0xFF000054        ! walker counter window (P4, RO)
p_vseed_reg:    .long 0xFF00004C        ! TSBVSEED (write-only)
p_seed_a:       .long 0x13579BDF
p_seed_b:       .long 0x2468ACE0
p_mask16:       .long 0x0000FFFF

! _collect -- read TSBVICT 16 times, return the nominations packed into r0
! (bit i = the i-th read). Clobbers r0-r3 and r5. r8 must hold &TSBVSEED;
! TSBVICT is the next word up, so the P4 address is formed here rather than
! burning a second literal (and the AND mask is a register, because SH's
! AND #imm is R0-only and R0 is the accumulator).
_collect:
        mov     r8, r3
        add     #4, r3                  ! r3 = &TSBVICT (0xFF000050)
        mov     #0, r0
        mov     #16, r2
        mov     #1, r5
1:      shll    r0
        mov.l   @r3, r1
        and     r5, r1
        or      r1, r0
        dt      r2
        bf      1b
        rts
         nop


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
        tst     r9, r9                  ! integrity net: 0 is the harness PASS token
        bf      1f                      ! (sim/cpu_ctb.c test_result() accepts any 4B==0
        mov     #0x7F, r9               ! write as PASS), so _fail must never write it.
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result:      .long TEST_RESULT_ADDRESS
p_test_result_pass: .long TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH
        ! ================================================================
        ! MISS-vector stub at VBR+0x400. Reaching this at all means a real
        ! exception was taken during what should have been a stall-and-walk
        ! hit on WAY 1 -- report code 2 directly.
        ! ================================================================
        .balign 4
        .space 0x600, 0
        .balign 4
_v_fault:                                ! = VBR + 0x400
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        mov     #2, r9
        bra     _fail
        nop

        .align 2
H_mmucr:        .long 0xFF000010

        ! Force .text section alignment to 4 KB so `start` is page-aligned.
        .balign 0x1000
_pad_page:
        .space 0x1000, 0

#endif  ! CONFIG_PRIV_ARCH
