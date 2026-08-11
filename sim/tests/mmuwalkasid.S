! mmuwalkasid.S -- ASID is folded into the TSB SET INDEX, not just the tag.
!
! Phase-2 Task 3 security guard. Before this change the TSB index was a
! function of the VPN alone, so the same VA in two different address spaces
! always landed in the same set. A TSB hit costs ~7 cycles against ~79.5 for a
! miss -- an 11x timing signal -- which turned that collision into a
! deterministic, targeted cross-address-space eviction primitive: to evict a
! victim's entry for VA X, touch VA X. Folding ASID into the index destroys
! that primitive; an attacker must now search for a colliding VA without
! knowing the victim's ASID.
!
! The guard reads the P4 TSB-slot helper (0xFF000048, core/datapath.vhm
! P4_TSBSLOT -> core/datapath_pkg.vhd tsb_ptr(), the single implementation the
! walker and TSBPTR also use) for ONE fixed VA under FOUR different ASIDs and
! checks (a) each answer against the hand-computed formula and (b) that the
! answers differ from each other.
!
! Config: TSBBR=0x00010006 (base 0x00010000, TSB_SIZE_LOG=6),
!         TSBCFG=0x00000061 (HASH_SHIFT=6, HASH_MODE=1)  -- same as
!         mmutsbslot.S / mmuwalkmiss.S / mmuwalkhit.S.
!
!   vpn  = VA >> 12
!   a1   = asid xor (asid << 5)
!   amix = a1 xor (a1 >> 9)
!   hash = (vpn xor (vpn >> HASH_SHIFT)) xor amix
!   idx  = hash and ((1 << TSB_SIZE_LOG) - 1)
!   slot = (TSBBR and not 0xF) or (idx << 4)
!
! VA 0x00042000 throughout: vpn=0x42, vpn^(vpn>>6)=0x43.
!   ASID 0x0000: amix=0x00000 -> idx=0x43&0x3F=0x03 -> 0x00010030
!   ASID 0x0001: amix=0x00021 -> idx=0x62&0x3F=0x22 -> 0x00010220
!   ASID 0x0055: amix=0x00AB5 -> idx=0xAF6&0x3F=0x36 -> 0x00010330
!   ASID 0x1234: amix=0x25A85 -> idx=...&0x3F=0x1D  -> 0x000101D0
!
! A tsb_ptr() that ignores ASID returns 0x00010030 for all four, so the
! mutation fails at result code 2.
!
! Result codes:
!   1  ASID 0x0000 -> 0x00010030          (agrees with mmutsbslot.S)
!   2  ASID 0x0001 -> 0x00010220
!   3  ASID 0x0055 -> 0x00010330
!   4  ASID 0x1234 -> 0x000101D0
!   5  the four slot addresses are not pairwise distinct
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

        .text
ENTRY(start)
#if CONFIG_PRIV_ARCH

        ! ---- TSBBR / TSBCFG. No AT needed: the helper reads the CSRs and
        ! ---- translates nothing. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        mov.l   p_slot_reg, r8          ! r8 = &JCORE_TSB_SLOT (0xFF000048)
        mov.l   p_va, r10               ! r10 = the one VA used for every case

        ! ---- Case 1: ASID = 0x0000 ----
        mov     #0, r0
        .word   0x407E                  ! LDC R0,ASIDR
        nop
        nop
        mov.l   r10, @r8
        mov.l   @r8, r4                 ! r4 = slot(VA, ASID=0x0000)
        mov.l   p_exp0, r2
        cmp/eq  r4, r2
        mov     #1, r9
        bf      _fail

        ! ---- Case 2: ASID = 0x0001 ----
        mov     #1, r0
        .word   0x407E                  ! LDC R0,ASIDR
        nop
        nop
        mov.l   r10, @r8
        mov.l   @r8, r5                 ! r5 = slot(VA, ASID=0x0001)
        mov.l   p_exp1, r2
        cmp/eq  r5, r2
        mov     #2, r9
        bf      _fail

        ! ---- Case 3: ASID = 0x0055 ----
        mov     #0x55, r0
        .word   0x407E                  ! LDC R0,ASIDR
        nop
        nop
        mov.l   r10, @r8
        mov.l   @r8, r6                 ! r6 = slot(VA, ASID=0x0055)
        mov.l   p_exp2, r2
        cmp/eq  r6, r2
        mov     #3, r9
        bf      _fail

        ! ---- Case 4: ASID = 0x1234 ----
        mov.l   p_asid3, r0
        .word   0x407E                  ! LDC R0,ASIDR
        nop
        nop
        mov.l   r10, @r8
        mov.l   @r8, r7                 ! r7 = slot(VA, ASID=0x1234)
        mov.l   p_exp3, r2
        cmp/eq  r7, r2
        mov     #4, r9
        bf      _fail

        ! ---- Case 5: the security property itself -- the SAME VA must not
        ! ---- map to the same set in different address spaces. Checked
        ! ---- pairwise so this fires even if the expectations above were
        ! ---- somehow all satisfied by a degenerate function. ----
        mov     #5, r9
        cmp/eq  r4, r5
        bt      _fail
        cmp/eq  r4, r6
        bt      _fail
        cmp/eq  r4, r7
        bt      _fail
        cmp/eq  r5, r6
        bt      _fail
        cmp/eq  r5, r7
        bt      _fail
        cmp/eq  r6, r7
        bt      _fail

        mov     #0, r9
        bra     _done
        nop

        .align 2
p_tsbbr_addr:  .long 0xFF000014
p_tsbbr_val:   .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr: .long 0xFF000018
p_tsbcfg_val:  .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_slot_reg:    .long 0xFF000048        ! core/datapath.vhm P4_TSBSLOT

p_va:   .long 0x00042000
p_asid3: .long 0x00001234
p_exp0: .long 0x00010030
p_exp1: .long 0x00010220
p_exp2: .long 0x00010330
p_exp3: .long 0x000101D0
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
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC
