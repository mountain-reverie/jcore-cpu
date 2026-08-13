! mmuxlate.S -- address-translation integration test (J4).
!
! WALKER-INSTALL VERSION (L2 of "retire LDTLB"). Same property, STRONGER
! evidence: the old version had a genuine pre-existing vacuity, fixed here.
!
! ---- what it tested, and why that was vacuous -----------------------------
! The old guard installed an IDENTITY entry (VA == PA) with LDTLB, enabled AT,
! and required a load through the translated P0 address to return the value
! written earlier with AT off. But this MMU does not relocate the bus -- the
! TLB emits PA tags only, so under an identity map the load returns the right
! value WHETHER OR NOT the translation ever happened. The assertion "the value
! came back" was therefore satisfied by an MMU that did nothing at all. Nothing
! in the old guard could tell the two apart.
!
! A non-identity map cannot repair this: with no bus relocation there is no
! observable difference in the returned data for ANY map. The observable that
! does exist is the walker's own counters, so the witness moves there.
!
! ---- what this guard tests NOW ---------------------------------------------
! Unchanged in substance: a load through a translated P0 VA must succeed and
! return the value seeded through the P1 alias. Added, and load-bearing:
!
!  * WALK WITNESS. 0xFF000054 ([31:16]=cnt_walks [15:0]=cnt_hits) is sampled
!    immediately before the translated load and again after. The data page has
!    NO resident TLB entry at that point (it is touched for the first time
!    under AT), so a real translation MUST cost exactly one walk and one hit.
!    cnt_walks not advancing (result 3) means the access was never translated
!    -- precisely the state the old guard could not see. cnt_hits not advancing
!    (result 4) means the walker looked but refused the entry, so the load's
!    correct value came from somewhere other than an installed translation.
!  * NO-FAULT WITNESS. Any exception during the translated access lands in
!    _fault_trap (result 5) instead of wandering; the guard's PASS path cannot
!    be reached through the handler.
!
! Verdict: STRONGER. The old assertion is kept and a positive witness that the
! MMU actually did the translation is added on top.
!
! ---- layout ---------------------------------------------------------------
! Code page: VA 0x0000..0x3FFF, GLOBAL 16 KB identity (size slot 1), W|X|C,
! U=0 -- a kernel fetch of a U=1 page is an SMEP protection fault.
! Data page under test: VA 0x4000, 4 KB, W|X|C|V, U=0, NOT global; it carries
! the only row the translated load can use.
! TSB: base 0x00014000, TSB_SIZE_LOG=8 (256 sets x 32 bytes), HASH_SHIFT=6,
! HASH_MODE=1; slot addresses come from the P4 helper at 0xFF000048.
!
! PTEL bits (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C bit2=G bit1=STALE
! bit0=V, bits[10:8]=page-size slot. A TSB row MUST set V.
!
! Result codes:
!   0  pass
!   1  AT=0 direct load sanity failed (the P1 seed did not read back)
!   2  AT=1 load through the translated VA returned the wrong value
!   3  the translated load did not cost a walk -- it was never translated
!   4  the walker walked but counted no hit -- nothing was installed
!   5  an exception was taken during the translated access
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's test_result()
! treats any 4-byte write of 0 as PASS, so _fail clamps r9==0 to 0x7F.
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

        ! ---- Ensure RB=0 (bank 0). core/cpu.vhd's walk_req is gated on
        ! ---- dp_sr.rb = '0' and the cosim starts in bank 1, so without this
        ! ---- NO walk is ever armed and nothing installs.
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_trap - 0x400 so every TLB vector lands in _fault_trap.
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Test A: AT=0 sanity. Seed the data page through the P1 alias
        ! ---- (untranslated) and read it back untranslated.
        mov.l   p_testval, r4           ! r4 = 0xBEEFCAFE
        mov.l   p_p1_4000, r5           ! r5 = 0x80004000 (P1 alias of PA 0x4000)
        mov.l   r4, @r5
        mov.l   @r5, r6
        cmp/eq  r4, r6
        bt      1f
        mov     #1, r9
        bra     _fail
        nop
1:
        ! ---- Configure the TSB. ----
        mov.l   p_tsbbr_addr, r0
        mov.l   p_tsbbr_val, r1
        mov.l   r1, @r0
        mov.l   p_tsbcfg_addr, r0
        mov.l   p_tsbcfg_val, r1
        mov.l   r1, @r0

        ! ---- Fill the TSB from the (VA, ASID, PTEL) table; each row's set
        ! ---- address comes from the P4 helper under that row's ASID, so no
        ! ---- hash is hand-computed. AT is off: plain P0 stores.
        mov.l   p_tsbslot, r12          ! r12 = 0xFF000048
        mov.l   p_tab, r14
        mov.l   p_tab_end, r5
1:      mov.l   @r14+, r6               ! VA
        mov.l   @r14+, r7               ! ASID
        mov.l   @r14+, r8               ! PTEL
        mov     r7, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   r6, @r12                ! write VA -> helper
        mov.l   @r12, r10               ! r10 = 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8
        cmp/hs  r5, r14
        bf      1b

        bra     _run
        nop

        ! ---- Literal pool 1 (setup). `mov.l @(disp,PC)` is FORWARD-only and
        ! ---- reaches +1020 bytes, so migrated bodies need two pools.
        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_trap - 0x400
p_testval:      .long 0xBEEFCAFE
p_p1_4000:      .long 0x80004000
p_tsbbr_addr:   .long 0xFF000014
p_tsbbr_val:    .long 0x00014008        ! base=0x00014000, TSB_SIZE_LOG=8
p_tsbcfg_addr:  .long 0xFF000018
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:      .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:          .long _tsb_tab
p_tab_end:      .long _tsb_tab_end

        .balign 4
_tsb_tab:
        ! VA          ASID        PTEL
        .long 0x00000000, 0x00000000, 0x000001CD  ! code 16K global W|X|C|V U=0
        .long 0x00001000, 0x00000000, 0x000001CD
        .long 0x00002000, 0x00000000, 0x000001CD
        .long 0x00003000, 0x00000000, 0x000001CD
        ! The page under test: identity, 4 KB, W|X|C|V, U=0, NOT global.
        .long 0x00004000, 0x00000000, 0x000040C9
_tsb_tab_end:

ENTRY(_run)
        ! ---- ASIDR = 0, then enable AT (MMUCR.AT=1). ----
        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR
        nop
        nop
        mov.l   q_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ---- Snapshot the walker counters, then take the FIRST translated
        ! ---- access to VA 0x4000. It has no resident entry, so a genuine
        ! ---- translation costs exactly one walk and one hit.
        mov.l   q_walkcnt, r0
        mov.l   @r0, r10
        mov     r10, r11
        shlr16  r10                     ! r10 = cnt_walks before
        extu.w  r11, r11                ! r11 = cnt_hits before

        mov.l   q_va4, r5
        mov.l   @r5, r7                 ! THE translated load

        ! ---- Disable AT before checking, so the checks themselves cannot
        ! ---- perturb the counters or fault.
        mov.l   q_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        ! ---- Walk witness FIRST: it is the check the old guard lacked, and
        ! ---- checking it before the data compare keeps it from being masked
        ! ---- by the compare in every scenario where both would fire.
        mov.l   q_walkcnt, r0
        mov.l   @r0, r1
        mov     r1, r2
        shlr16  r1                      ! r1 = cnt_walks now
        extu.w  r2, r2                  ! r2 = cnt_hits now
        cmp/eq  r10, r1
        bf      1f
        mov     #3, r9                  ! no walk: the load was never translated
        bra     _fail
        nop
1:      cmp/eq  r11, r2
        bf      1f
        mov     #4, r9                  ! walked but installed nothing
        bra     _fail
        nop
1:
        ! ---- The original assertion: the translated load returned the value
        ! ---- seeded through the P1 alias.
        mov.l   q_testval, r4
        cmp/eq  r4, r7
        bt      1f
        mov     #2, r9
        bra     _fail
        nop
1:
        bra     _done
        nop

        ! ---- Literal pool 2 (test body). ----
        .align 2
q_mmucr:        .long 0xFF000010
q_walkcnt:      .long 0xFF000054        ! [31:16]=cnt_walks [15:0]=cnt_hits
q_va4:          .long 0x00004000
q_testval:      .long 0xBEEFCAFE

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
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH

        ! ---- Catch-all TLB vector at VBR+0x400. No exception is expected at
        ! ---- any point; taking one means the map is wrong, not that the
        ! ---- property held, so it is a LOUD failure and never a PASS path.
        .balign 4
        .space 0x620, 0
        .balign 4
_v_trap:                                ! = VBR + 0x400
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        mov     #5, r9
        bra     _fail
        nop

        .align 2
Hmmucr:         .long 0xFF000010

        ! ---- Backing store: the mapped data page (PA 0x4000) and the TSB at
        ! ---- PA 0x14000..0x15FFF. The walker reads the TSB by PHYSICAL
        ! ---- address, and physical aliases are backed by SRAM only within the
        ! ---- loaded image extent, so the image must reach past the TSB.
_fault_pages:
        .space 0x16000, 0

#endif  ! CONFIG_PRIV_ARCH
