! mmuasidsh.S -- ASID takes effect in the SHADOW of LDC Rm,ASIDR (J4).
!
! WHY THIS GUARD EXISTS.
!
! Phase 4a duplicates the ASIDR register inside the datapath: a second 16-bit
! copy, exported on a dedicated port, consumed ONLY by the TLB's lookup compare
! (u_tlb.asid). The copy exists purely for placement -- the master has three
! consumers (P4 readback, tlb_walk, TLB lookup) so the placer parks its flop at
! their centroid, measured as a 3.7 ns routing hop and the largest single item
! on the j4c critical path.
!
! The replica is written from this'comb -- the same next-state value, the same
! enable, the same clock edge as the master -- so it is bit-identical to the
! master in every cycle. The natural-looking wrong implementation samples the
! master's OUTPUT instead:
!
!     if rising_edge(clk) then asidr_tlb <= mmu_regs.asidr; end if;
!
! which lags. A translated access in the shadow of LDC Rm,ASIDR then looks up
! under the PREVIOUS ASID: a wrong hit or a wrong miss, with no exception and
! no diagnostic. Nothing else in the suite covers this -- ASIDR changes only at
! a context switch, and every other guard lets it settle for several
! instructions before the next translated access.
!
! HOW DEEP THE SHADOW ACTUALLY IS -- MEASURED, from VCDs of this guard
! (10 ns clock), not assumed. This bounds what any software guard can prove:
!
!   D side.  The master takes its new value one cycle BEFORE the following
!            instruction's data access is presented (master = 0x22 at 800 ns,
!            d_va = 0x4000 at 810 ns). One cycle of structural slack: the next
!            instruction's MA cannot be pulled closer to the LDC's writeback.
!   I side.  Useless as a probe, and not for the reason one would guess: the
!            fetch stream runs FAR AHEAD of execute. Measured with the LDC at
!            0x2FFE and the next instruction at 0x3000 on a page mapped only
!            under the new ASID, the fetch of 0x3000 was presented at 1630 ns
!            while the LDC did not update ASIDR until 1730 ns -- ten cycles
!            later. That fetch misses on CORRECT hardware, so an I-side
!            construction cannot distinguish a skewed replica from a good one.
!
! CONSEQUENCE, stated plainly: a ONE-cycle lag is not observable anywhere in
! this microarchitecture -- it lands exactly on the D-side boundary and is
! absorbed by that one cycle of slack. This guard therefore pins the boundary
! at TWO cycles, which is the tightest any program can reach. The one-cycle
! case is defended by construction (this'comb) and by review, not by test.
!
! WALKER-INSTALL VERSION (L2 of "retire LDTLB"). The property, the legs and
! the timing argument above are UNCHANGED -- only how VPN 0x4 becomes resident
! changes. LDTLB could install an ASID-B entry while ASIDR held A; the walker
! cannot, because it installs only on a MISS and only under the CURRENT ASID.
! So the entry is made resident by a WARM-UP: ASIDR := B, let it settle, touch
! VA 0x4000 once (that access misses, walks, and installs the B-tagged entry),
! then ASIDR := A and settle again. Legs 1-3 then run exactly as before, with
! the entry already resident and nothing between each LDC and its access.
!
! The warm-up is also the setup oracle: it must return the sentinel (fail 2),
! so a red leg 1 can never be explained away as "the entry was never installed".
! Verdict: SAME strength. Leg 1 still measures the two-cycle boundary, leg 3
! still is the only pass path, and no assertion was dropped or loosened.
!
! LEGS. A fault carries the leg marker at P1 0x80005000; the handler reports
! that marker as the fail code when the fault was not the expected one.
!
!   1  Shadow. VPN 0x4 (VA 0x4000 -> PA 0x4000) is installed NON-GLOBAL under
!      ASID B only. With ASIDR = A, `LDC r0,ASIDR` (B) is followed IMMEDIATELY
!      by `mov.l @r2,r8` on VA 0x4000. It must HIT. Everything the load needs
!      is preloaded, so nothing sits between the LDC and the access.
!   2  Settled control: the same load after four nops. Separates "the replica
!      is skewed" (1 red, 2 green) from "the mapping was never installed"
!      (both red), so a red leg 1 cannot be waved off as a bad setup.
!   3  Negative direction: switch ASIDR back to A and immediately re-run the
!      load. It must FAULT -- a stuck-at or never-updating replica would keep
!      matching under B and sail through legs 1 and 2. The handler seeing
!      marker 3 is the ONLY pass path for the test as a whole.
!
! VBR = _v_load - 0x400, so the TLB vector (VBR+0x400) lands on _v_load.
!
! MUTATION-VERIFIED (rebuilt without -n each time):
!   this'comb -> this'register            (1-cycle lag)  -> PASS  (see above)
!   this'comb -> two-deep register chain  (2-cycle lag)  -> FAIL, code 3

#include "sim_instr.h"
#include "mmuwalk_common.inc"
#define ENTRY(name) .globl name; .balign 4; name:

! LDC Rm,ASIDR = 0100 mmmm 0111 1110 (decode/gen-go/spec/sh4/mmu.toml).
#define LDC_R0_ASIDR .word 0x407E
#define LDC_R0_PTEH  .word 0x405E
#define LDC_R0_PTEL  .word 0x406E
#define LDC_R0_VBR   .word 0x402E

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

        ! ---- VBR = _v_load - 0x400 (so VBR+0x400 = _v_load). ----
        mov.l   p_vbr_val, r0
        LDC_R0_VBR

        ! ---- Seed PA 0x4000 = SENTINEL via P1 (untranslated, AT-independent). ----
        mov.l   p_sentinel, r3
        mov.l   p_p1_4000, r2           ! 0x80004000 -> PA 0x4000
        mov.l   r3, @r2

        ! ---- leg marker = 0 (nothing reached yet); the handler reads it. ----
        mov.l   p_p1_leg, r2
        mov     #0, r1
        mov.l   r1, @r2

        ! ---- Configure the TSB (base 0x00014000, TSB_SIZE_LOG=8 -> 256 sets
        ! ---- x 32 bytes; HASH_SHIFT=6, HASH_MODE=1 puts the ASID in the
        ! ---- index, which is why each row is filled under its OWN ASID).
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Fill the TSB from the (VA, ASID, PTEL) table; each row's set
        ! ---- address is asked of the P4 helper (0xFF000048) UNDER THAT ROW'S
        ! ---- ASID, so nothing hand-computes the hash. AT is off: P0 stores.
        mov.l   p_tsbslot, r12
        mov.l   p_tab, r14
        mov.l   p_tab_end, r5
1:      mov.l   @r14+, r6               ! VA
        mov.l   @r14+, r7               ! ASID
        mov.l   @r14+, r8               ! PTEL
        mov     r7, r0
        LDC_R0_ASIDR
        nop
        nop
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8
        cmp/hs  r5, r14
        bf      1b

        ! ---- ASIDR = A for the run. ----
        mov.l   p_asid_a, r0
        LDC_R0_ASIDR
        nop
        nop
        nop
        nop

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- WARM-UP. Make VPN 0x4 resident and B-tagged. This access is the
        ! ---- one that misses, walks and installs; every later leg runs
        ! ---- against a resident entry. Marker 2, so a fault here reports the
        ! ---- setup-error code rather than the shadow code.
        mov.l   c_va4, r2
        mov.l   p_sentinel, r4
        mov.l   p_p1_leg, r5
        mov     #2, r1
        mov.l   r1, @r5
        mov.l   p_asid_b, r0
        LDC_R0_ASIDR
        nop
        nop
        nop
        nop
        mov.l   @r2, r8                 ! miss -> walk -> install (ASID B)
        cmp/eq  r8, r4
        mov     #2, r9                  ! fail 2 = the mapping is wrong, not a skew
        bt      1f
        bra     _fail_at_off
        nop
1:
        ! ---- Back to ASID A and let it settle, so leg 1 starts from A. ----
        mov.l   p_asid_a, r0
        LDC_R0_ASIDR
        nop
        nop
        nop
        nop

        ! ---- Preload everything the measured load needs, so the only thing
        ! ---- between the LDC and the translated access is the LDC itself.
        mov.l   c_va4, r2               ! r2 = 0x00004000
        mov.l   p_sentinel, r4          ! r4 = expected value
        mov.l   p_p1_leg, r5            ! r5 = P1 alias of the leg marker
        mov.l   p_asid_b, r0            ! r0 = ASID B
        mov     #1, r1
        mov.l   r1, @r5                 ! leg marker 1

        ! ================= LEG 1: the shadow access ==============
        LDC_R0_ASIDR                    ! ASID := B
        mov.l   @r2, r8                 ! <-- SHADOW ACCESS. Must HIT under B.

        cmp/eq  r8, r4
        mov     #1, r9                  ! fail 1 = shadow load did not see the new ASID
        bt      1f                      ! bt-over-bra: the stub is outside bf's +/-256B
        bra     _fail_at_off
        nop
1:

        ! ================= LEG 2: settled control ================
        mov     #2, r1
        mov.l   r1, @r5                 ! leg marker 2
        nop
        nop
        nop
        nop
        mov.l   @r2, r8                 ! same load, ASIDR long settled
        cmp/eq  r8, r4
        mov     #2, r9                  ! fail 2 = the mapping is wrong (not a skew)
        bt      2f
        bra     _fail_at_off
        nop
2:

        ! ================= LEG 3: negative direction =============
        ! p_asid_a3 is a DELIBERATE duplicate of p_asid_a, used by leg 3 alone.
        ! It gives leg 3 an expected constant of its own that can be corrupted
        ! in isolation (set it to ASID B and leg 3 stays on B, the load hits,
        ! and the guard must report fail 3) without disturbing the setup ASID.
        mov.l   p_asid_a3, r0
        mov     #3, r1
        mov.l   r1, @r5                 ! leg marker 3
        LDC_R0_ASIDR                    ! ASID := A
        mov.l   @r2, r8                 ! <-- must MISS -> _v_load with marker 3

        ! Fell through: the entry was still usable under ASID A.
        mov     #3, r9                  ! fail 3 = replica did not follow ASIDR back
        bra     _fail_at_off
        nop

        ! ---- Every in-body failure exits through here. AT is still ENABLED on
        ! ---- the fall-through paths, and _fail's own store to
        ! ---- TEST_RESULT_ADDRESS would then be translated, miss, and land in
        ! ---- the handler -- which reports the LEG MARKER instead of the fail
        ! ---- code that was just computed. Disabling AT first keeps each fail
        ! ---- code its own.
_fail_at_off:
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _fail
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_load - 0x400
p_mmucr:        .long 0xFF000010
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00014008        ! base=0x00014000, TSB_SIZE_LOG=8
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:      .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:          .long _tsb_tab
p_tab_end:      .long _tsb_tab_end
p_asid_a:       .long 0x00000011
p_asid_a3:      .long 0x00000011        ! leg 3's own copy -- see LEG 3
p_asid_b:       .long 0x00000022
p_sentinel:     .long 0xA51DA51D
p_p1_4000:      .long 0x80004000
p_p1_leg:       .long 0x80005000        ! P1 alias of PA 0x5000 (leg marker)
c_va4:          .long 0x00004000

        .balign 4
_tsb_tab:
        ! VA          ASID        PTEL
        ! Code page 0 GLOBAL identity, W|X|C|G|V, U=0 (SMEP: a kernel fetch of
        ! a U=1 page is a protection fault). Filed under ASID A because that is
        ! the ASID in force when the first fetch walks; once installed, GLOBAL
        ! makes it match under B as well, so it is never re-walked.
        .long 0x00000000, 0x00000011, 0x000000CD
        ! VPN 0x4 -> PA 0x4000, NON-global, tagged ASID B: the entry legs 1-3
        ! measure. Filed under B, found only when ASIDR = B.
        .long 0x00004000, 0x00000022, 0x000040E9
_tsb_tab_end:

#endif  ! CONFIG_PRIV_ARCH

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

#if CONFIG_PRIV_ARCH

        ! ---- TLB vector at VBR+0x400. ----
        ! A fault is EXPECTED only on leg 3. Anywhere else it is the defect this
        ! guard exists to catch, and the leg marker names which leg.
        .balign 4
        .space 0x620, 0
        .balign 4
_v_load:                                ! = VBR + 0x400
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT) before anything else
        mov.l   Hleg, r0
        mov.l   @r0, r1
        mov     #3, r2
        cmp/eq  r1, r2
        bf      _h_bad                  ! fault outside leg 3 -> report the leg
        mov.l   Hresult, r0
        mov.l   Hresult_pass, r1
        mov.l   r1, @r0
_h_pass_spin:
        bra     _h_pass_spin
        nop
_h_bad:
        ! r1 = leg marker (1 or 2, or 0 if the fault preceded every leg).
        mov     r1, r9
        tst     r9, r9                  ! never write the PASS token from a fail path
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   Hresult, r0
        mov.l   r9, @r0
_h_bad_spin:
        bra     _h_bad_spin
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Hresult:        .long TEST_RESULT_ADDRESS
Hresult_pass:   .long   TEST_PASS_MAGIC
Hleg:           .long 0x80005000        ! P1 alias of the leg marker

        ! ---- Backing store: the mapped pages (PA 0x4000, 0x5000) and the TSB
        ! ---- at PA 0x14000..0x15FFF. The walker reads the TSB by PHYSICAL
        ! ---- address and physical aliases are backed by SRAM only within the
        ! ---- loaded image extent, so the image must reach past the TSB end.
_fault_pages:
        .space 0x16000, 0

#endif  ! CONFIG_PRIV_ARCH
