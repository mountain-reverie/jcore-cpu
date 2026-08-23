! mmuwalkitakeover.S -- DRIVER for p_walk_takeover (core/cpu.vhd). Lane cpu_tb.
!
! READ THE DIVISION OF LABOUR FIRST.
! =================================
! The property under test is "on an I-SIDE TSB walk, the one cycle before the
! walker owns the data bus carries no core D access". Violating it means the
! core's access is driven onto the EXTERNAL bus, acked there, withheld from the
! datapath and then replayed after the walk -- i.e. committed twice. On the
! plain SRAM this suite runs on a double-committed access is IDEMPOTENT and
! leaves no software-visible trace whatsoever, so NO .S file can detect it.
!
! The DETECTOR is therefore `p_walk_takeover` in core/cpu.vhd, a permanently
! asserted, simulation-only monitor. THIS FILE IS THE DRIVER: its job is to put
! a core D access as close to the I-side takeover window as the pipeline
! permits, so the monitor has the hardest case to observe. Its own result codes
! say nothing about the window; they assert ordinary, software-visible things.
!
! WHY THE MONITOR IS EXPECTED TO STAY SILENT (and why that is not vacuity).
! core/cpu.vhd's p_walk_own comment carries the four-step proof: an I-side walk
! holds walk_supp_i from its ARMING cycle, dp_inst_i.ack is gated on it, the
! fetch is therefore never transferred, datapath.vhm's slot gate
! (`slot_inst_en = '0'`) never opens, and so no new D access can be launched
! for the whole walk -- while walk_i_miss already required sig_db_o.en='0' on
! the arming cycle itself. The monitor exists because every one of those four
! steps lives in a different place and any of them can be relaxed by accident.
!
! THE SHAPE THIS GUARD BUILDS
!   - VA 0x00009000 is present in the TSB and absent from the TLB, and holds
!     the continuation of the test. Branching to it forces an I-SIDE walk.
!   - The three instructions before that branch are stores, the LAST of them in
!     the branch's DELAY SLOT -- so a D access is live on the bus in the cycles
!     immediately around the branch-target fetch that misses. That is the
!     closest legal approach to the window: the walk cannot even ARM until
!     sig_db_o.en falls, so "one cycle later" is the whole hazard.
!   - The stores are `mov.l Rm,@-Rn` (pre-decrement). A bus-level double commit
!     is invisible, but a re-EXECUTION is not: the pointer would move by more
!     than three words. Check 0x61 pins that independently of the monitor.
!
! IDENTITY MAPPING (CLAUDE.md "Never identity-map the page under test").
! The page under test is the TARGET code page and it is NOT identity-mapped:
! VA 0x00009000 -> PA 0x00008000 (`p_ptel_tgt`), i.e. .tlbtext is linked at
! 0x00008000 by sh32_tlbtext.x and executed 4 KB higher. Nothing is linked at
! PA 0x00009000, so with an inert MMU the branch fetches zeros and the run
! cannot reach any check. Moving the frame needs only p_ptel_tgt/p_vpn_tgt/
! p_target, so identity was NOT forced here. The .text code page IS identity,
! forced by the flat image load (README-identity-mapping.md category (b)); its
! independent witnesses are the target page's relocation above and check 0x66,
! which asserts P4_TSBCNT MOVED across the branch. Deliberately a did-it-move
! test and not an exact delta: between the snapshot and the check the walker
! services the target page's I-side miss AND the D-side misses for .tlbtext's
! own PC-relative literal pool, so the exact count is a property of the literal
! layout rather than of the mechanism under test. Moving is what discharges the
! witness -- an inert MMU leaves it at zero.
!
! P5 (VA-backing). The only VAs dereferenced under AT=1 are in the .text page
! and in .tlbtext at VA 0x0000_9xxx -- both inside the cosim's 16 MB backed
! window. The scratch buffer is deliberately addressed through P1
! (0x8002_0000), which is FIXED-TRANSLATE, never consulted in the TLB and
! folded to PA 0x0002_0000 by g_dstore_squash, so it can neither miss nor put
! an out-of-window VA on the bus. P1 was chosen precisely so the store burst
! adds bus traffic and nothing else: a translated scratch page would inject its
! own D-side walks into the window under test.
!
! RESULT CODES (base 0x60)
!   0x61  the scratch pointer did not move by exactly three words -- a store
!         was re-executed or dropped
!   0x62  the FIRST store's word is wrong
!   0x63  the SECOND store's word is wrong
!   0x64  the DELAY-SLOT store's word is wrong
!   0x65  SPC moved -- an exception was taken where the walker should have
!         resolved the fetch
!   0x66  P4_TSBCNT did not move across the branch -- no walk happened, or the
!         counter is dead
!   0x69  fell through the jmp -- the target was never executed
!   0x6A  the MISS vector was reached: the walker did not install VA 0x9000
!   0x7F  _fail reached with r9 == 0 (should be unreachable)
!
! MUTATION EVIDENCE
! =================
! (measured in ghcr.io/mountain-reverie/jcore-cpu-ci:latest, CPU_VARIANT=j4,
!  SIM_TOP=cpu_tb, --stop-time=80us. G1-G4 mutate THIS FILE, so each rebuilt
!  the image against unmodified RTL; M-I1 mutates the RTL and rebuilt the whole
!  cosim, never `-n`. PRISTINE and RESTORED runs bracket the set: both PASS.)
!
!   G1  p_ptel_tgt V bit cleared (0x000080C9 -> 0x000080C8): the walker rejects
!       the entry (tlb_walk.vhd st_data needs bus_d(0)='1'), no install, the
!       branch-target fetch raises IMISS.            => Result=106 (0x6A)
!   G4  p_vpn_tgt 0x00009000 -> 0x0000A000: the TSB row is filed in another
!       set under another tag, so the probe of VA 0x9000's set finds nothing
!       and both ways are rejected.                  => Result=106 (0x6A)
!       (G1 and G4 share a code deliberately -- they are the same defect,
!       "the walker did not install the page under test", reached two ways.)
!   G2  p_val3 changed in the store but not in t_val3: the delay-slot store's
!       word no longer matches.                      => Result=100 (0x64)
!   G3  p_scratch moved by 4 without moving t_scratch_end: the pointer lands
!       one word off.                                => Result=97  (0x61)
!
! MONITOR LIVENESS -- THE EVIDENCE THAT THIS FILE IS NOT VACUOUS
! =============================================================
! G1-G4 prove the guard's own checks bite. They do NOT prove it reaches the
! window under test -- that is what the monitor watches, and a driver that
! never gets near the window would pass every one of them. The proof is that
! the monitor FIRES ON THIS IMAGE once the property is broken.
!
!   M-I1  core/cpu.vhd: `dp_inst_i.ack <= inst_i.ack and not walk_supp_i`
!         reduced to `dp_inst_i.ack <= inst_i.ack`. That is step (3) of the
!         four-step proof at p_walk_own -- the single term that freezes the
!         pipeline for the duration of an I-side walk -- so removing it lets a
!         D access start inside the un-owned window.
!
!         RESULT: the run ends at 720 ns with
!
!           ../core/cpu.vhd:786:9:@720ns:(assertion failure):
!           I-SIDE WALK TAKEOVER WINDOW OCCUPIED: a core D ...
!           instance: /cpu_tb/cpu1/g_tlb_walk/p_walk_takeover
!
!         A NAMED, self-identifying failure that cannot be confused with any
!         other guard's, and at 720 ns it is ~165x inside the 120us stop-time:
!         the assertion firing, not a timeout. The monitor is a global
!         invariant, so the same mutation also fires it on mmuwalkiside
!         (730 ns) and mmuimiss (560 ns) -- this image is simply the one built
!         to approach the window deliberately rather than incidentally.
!         (Line 786 is where p_walk_takeover's assert sat at the time of the
!         run; comments added since have moved it. The instance path is the
!         stable identifier.)
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

        ! ---- ASIDR = 0 (the set address depends on it). ----
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop

        ! ---- TSB way 0: the TARGET page, VA 0x00009000 -> PA 0x00008000.
        ! ---- The set address is asked of the P4 helper (0xFF000048, the same
        ! ---- tsb_ptr() the walker uses), never hand-computed. ----
        mov.l   p_tsbslot_reg, r12
        mov.l   p_vpn_tgt, r6
        mov     #0, r7
        mov.l   p_ptel_tgt, r8
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8

        ! ---- TSB way 1: the identity CODE page, so the first fetch after AT
        ! ---- goes on is walked in. WAY 1 so that even a hash collision with
        ! ---- the target entry above leaves both resident. G=1, U=0 (SMEP). ----
        mov.l   p_pteh_code, r6
        mov     #0, r7
        mov.l   p_ptel_code, r8
        mov.l   r6, @r12
        mov.l   @r12, r10
        tsb_fill_way r10, 16, r6, r7, r8

        ! ---- Seed the SPC sentinel, then enable AT. ----
        mov.l   p_sent_spc, r0
        .word   0x404E                  ! LDC r0, SPC
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Snapshot the walker counters AFTER the code page has been walked
        ! ---- in, so the delta check below sees the TARGET page's walk only. ----
        mov.l   p_walkcnt, r0
        mov.l   @r0, r11

        ! ---- The takeover shape. Everything is in registers before the burst,
        ! ---- so the only D traffic between here and the branch-target fetch
        ! ---- is the three stores themselves. ----
        mov.l   p_scratch, r4
        mov.l   p_val1, r1
        mov.l   p_val2, r2
        mov.l   p_val3, r3
        mov.l   p_target, r0
        mov.l   r1, @-r4
        mov.l   r2, @-r4
        jmp     @r0
        mov.l   r3, @-r4                ! DELAY SLOT: live D access across the
                                        ! branch-target fetch that misses

        mov     #0x69, r9               ! fell through -> target never executed
        bra     _ret_home
        nop

! Return trampoline. Entered from .tlbtext with AT still ON, at a .text address
! the identity code-page mapping covers; only then is AT switched off, which is
! safe here because .text really is identity (VA == PA).
ENTRY(_ret_home)
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        tst     r9, r9
        bf      1f
        mov.l   p_done, r0
        jmp     @r0
        nop
1:
        mov.l   p_fail, r0
        jmp     @r0
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_fault - 0x400
p_mmucr:        .long 0xFF000010
p_walkcnt:      .long 0xFF000054        ! P4_TSBCNT [31:16]=walks [15:0]=hits
p_pteh_code:    .long start
p_ptel_code:    .long start + 0x000000CD ! identity: PPN=start, G=1, U=0 (SMEP)
p_tsbslot_reg:  .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00010006        ! base=0x00010000, TSB_SIZE_LOG=6
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_vpn_tgt:      .long 0x00009000        ! VA under test -- NOT the frame
p_ptel_tgt:     .long 0x000080C9        ! PA 0x00008000 | W|X|C|V, U=0 (SMEP)
p_sent_spc:     .long 0xDEADBE00
p_scratch:      .long 0x80020010        ! P1 alias of PA 0x00020010
p_val1:         .long 0x11112222
p_val2:         .long 0x33334444
p_val3:         .long 0x55556666
p_target:       .long _target + 0x1000  ! .tlbtext is linked at PA 0x00008000
p_done:         .long _done
p_fail:         .long _fail

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
        ! MISS-vector stub at VBR+0x400. Reaching it means the walker did not
        ! install VA 0x00009000 and the fetch raised IMISS instead -- code 0x6A.
        .balign 4
        .space 0x600, 0
        .balign 4
_v_fault:                                ! = VBR + 0x400
        mov.l   H_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! AT off
        mov     #0x6A, r9
        bra     _fail
        nop

        .align 2
H_mmucr:        .long 0xFF000010

        ! Force .text alignment to 4 KB so `start` is page-aligned.
        .balign 0x1000
_pad_page:
        .space 0x1000, 0

! ======================================================================
! Translated-only code. Linked at 0x00008000 by sh32_tlbtext.x and REACHED at
! VA 0x00009000 -- absent from the TLB, resolvable only by the I-side walk this
! guard exists to drive. Reaching _target at all is the central observation.
!
! Every literal load below is `mov.l @(disp,PC)` off the 0x9xxx PC, so it is a
! D-side access to the same translated page: the DTLB copy is walked in here.
! ======================================================================
        .section .tlbtext, "ax"
        .balign 4
_target:
        ! ---- 0x61: the pointer moved by exactly three words.
        mov.l   t_scratch_end, r5
        cmp/eq  r4, r5
        bt      1f
        mov     #0x61, r9
        bra     _t_home
        nop
1:
        ! ---- 0x64/0x63/0x62: each store's word, youngest first.
        mov.l   @r4, r5
        mov.l   t_val3, r6
        cmp/eq  r5, r6
        bt      2f
        mov     #0x64, r9
        bra     _t_home
        nop
2:
        mov.l   @(4,r4), r5
        mov.l   t_val2, r6
        cmp/eq  r5, r6
        bt      3f
        mov     #0x63, r9
        bra     _t_home
        nop
3:
        mov.l   @(8,r4), r5
        mov.l   t_val1, r6
        cmp/eq  r5, r6
        bt      4f
        mov     #0x62, r9
        bra     _t_home
        nop
4:
        ! ---- 0x65: SPC untouched -> no exception was entered on the way here.
        .word   0x0042                  ! STC SPC, r0
        mov.l   t_sent_spc, r5
        cmp/eq  r0, r5
        bt      5f
        mov     #0x65, r9
        bra     _t_home
        nop
5:
        ! ---- 0x66: the counters MOVED across the branch. A delta, not a
        ! ---- snapshot compared for equality: a dead counter fails this.
        mov.l   t_walkcnt, r0
        mov.l   @r0, r5
        cmp/eq  r5, r11
        bf      6f
        mov     #0x66, r9
        bra     _t_home
        nop
6:
        mov     #0, r9
_t_home:
        mov.l   t_ret, r0
        jmp     @r0
        nop

        .align 2
        ! p_scratch (0x80020010) minus three words: the three `mov.l Rm,@-R4`
        ! stores each pre-decrement by 4, so r4 must land exactly here. Written
        ! out rather than computed because the whole point of check 0x61 is to
        ! compare against a value derived INDEPENDENTLY of the pointer chain --
        ! deriving it from p_scratch would make a re-executed store agree with
        ! itself. Keep the two in step by hand; G3 in the header is the
        ! mutation that proves the check notices when they disagree.
t_scratch_end:  .long 0x80020004
t_val1:         .long 0x11112222
t_val2:         .long 0x33334444
t_val3:         .long 0x55556666
t_sent_spc:     .long 0xDEADBE00
t_walkcnt:      .long 0xFF000054
t_ret:          .long _ret_home

#endif  ! CONFIG_PRIV_ARCH
