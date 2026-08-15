! mmusmpasid.S -- dual-core, MMU-on, SAME-ASID cross-core isolation guard (J4).
!
! Property under test: two cores running the SAME 12-bit ASID_TAG must not be
! able to consume each other's TSB rows. Linux allocates ASIDs per-CPU
! (asid_cache is per-CPU, cpu_context is indexed by cpu), so two cores hand the
! same ASID to different address spaces as a matter of course. That is only
! sound if the thing tagged by that ASID -- the TSB -- is per-CPU too.
!
! Construction:
!   both cores: ASIDR = 0x0011, page 0 mapped GLOBAL identity (code), and
!               VA 0x4000 mapped NON-global under ASID 0x0011 -- but cpu0 maps
!               it to PA 0x4000 and cpu1 to PA 0x5000, holding different
!               sentinels. Each core must read ITS OWN sentinel.
!   cpu0 TSB @ 0x00014000, cpu1 TSB @ 0x00016000 (per-core).
!   With -DSHARED_TSB=1 cpu1 uses 0x00014000 instead: one shared
!   TSB, both rows hash to the same set and land in the same way, and the
!   rendezvous guarantees the loser reads the winner's PA. That flavour MUST
!   fail -- run_mmusmpasid.sh asserts it does. It is the proof this guard has
!   teeth.
!
! Ordering: fill TSB (AT off) -> rendezvous (AT off) -> AT on -> single load ->
! AT off -> compare and report. AT is off for every result store because
! TEST_RESULT_ADDRESS is a P0 address and would otherwise be translated.
!
! Scratch words live at absolute addresses in the 0x8000 window, touched only
! with AT off, so they need no mapping of their own.

#include "sim_instr.h"
#include "mmuwalk_common.inc"

#define ENTRY(name) .globl name; .balign 4; name:

! Must match JCORE_BOOT_TSB_SIZE_LOG in the kernel's cpu/mmu_context.h: a TSB
! of 2^8 = 256 SETS of 32 bytes = 8192 bytes. TSB_SIZE_LOG counts SETS, not
! entries -- sizing it as 16 << LOG would give hardware half the region it
! indexes. cpu0's TSB at 0x14000 therefore ends at 0x15FFF and cpu1's 0x16000
! does not overlap it.
#define JCORE_TSB_SIZE_LOG      8

! ---- absolute scratch (AT off only) ----
#define RDV0            0x00008000      ! cpu0 "my TSB is filled"
#define RDV1            0x00008004      ! cpu1 "my TSB is filled"
#define CPU1_RESULT     0x00008008      ! cpu1 leg outcome: magic = ok

#define RDV_MAGIC       0x5A5A0001
#define CPU1_OK_MAGIC   0x5A5A0002

#define SENTINEL0       0xC0DE0000
#define SENTINEL1       0xC0DE0001

        .section .vect, "ax"
        .align 2
        .long   _start                  ! reset PC (both cores)
        .long   0x0000A000              ! reset SP
        .long   _start
        .long   0x0000A000
        .rept 60
        .long   0
        .endr
        .long   SIM_INSTR_MAGIC
        .long   _sim_instr_end
        .long   _done
        .long   _fail
        .long   CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .section .text
ENTRY(_start)
#if CONFIG_PRIV_ARCH
        ! ---- RB=0 (bank 0), so r0-r7 are the bank this code assumes. ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR so that VBR+0x400 (the single TLB vector) = _v_fault. ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- branch on core id ----
        mov.l   p_cpuid, r0
        mov.l   @r0, r1
        tst     r1, r1
        bt      cpu0_role
        bra     cpu1_role
        nop

        .align 2
p_rbclear:      .long 0xDFFFFFFF
p_vbr_val:      .long _v_fault - 0x400
p_cpuid:        .long 0xABCD0600

! ============================ cpu0 ============================
cpu0_role:
        ! seed PA 0x4000 = SENTINEL0 through P1 (untranslated).
        mov.l   p_p1_4000, r2
        mov.l   p_sent0, r3
        mov.l   r3, @r2

        mov.l   p_tsb0, r11             ! my TSB base
        mov.l   p_tab0, r14
        mov.l   p_tab0_end, r5
        bsr     tsb_load
        nop

        ! rendezvous: publish, then wait (bounded) for the peer.
        mov.l   p_rdv0, r0
        mov.l   p_rdv_magic, r1
        mov.l   r1, @r0
        mov.l   p_rdv1, r3
        mov.l   p_wait_limit, r2
1:      mov.l   @r3, r1
        mov.l   p_rdv_magic, r0
        cmp/eq  r0, r1
        bt      2f
        dt      r2
        bf      1b
        mov     #0x10, r9               ! 0x10 = peer never reached rendezvous
        bra     _fail
        nop

2:      bsr     at_on
        nop
        mov.l   c_va4, r2
        mov.l   @r2, r8                 ! the load under test
        bsr     at_off
        nop

        mov.l   p_sent0, r0
        cmp/eq  r8, r0
        bt      3f
        mov     #0x11, r9               ! 0x11 = cpu0 read the PEER's page
        bra     _fail
        nop

        ! my leg passed; wait (bounded) for cpu1's leg, then report once.
3:      mov.l   p_cpu1_result, r3
        mov.l   p_wait_limit, r2
4:      mov.l   @r3, r1
        mov.l   p_cpu1_ok, r0
        cmp/eq  r0, r1
        bt      _done
        dt      r2
        bf      4b
        mov     #0x12, r9               ! 0x12 = cpu1 never reported ok
        bra     _fail
        nop

        .align 2
p_p1_4000:      .long 0x80004000
p_sent0:        .long SENTINEL0
p_tsb0:         .long 0x00014000
p_tab0:         .long _tab0
p_tab0_end:     .long _tab0_end
p_rdv0:         .long RDV0
p_rdv1:         .long RDV1
p_rdv_magic:    .long RDV_MAGIC
p_wait_limit:   .long 0x00040000
c_va4:          .long 0x00004000
p_cpu1_result:  .long CPU1_RESULT
p_cpu1_ok:      .long CPU1_OK_MAGIC

! ============================ cpu1 ============================
cpu1_role:
        mov.l   p_sp1, r15              ! own stack, clear of cpu0's

        mov.l   p_p1_5000, r2
        mov.l   p_sent1, r3
        mov.l   r3, @r2

        mov.l   p_tsb1, r11             ! my TSB base (or cpu0's, if SHARED_TSB)
        mov.l   p_tab1, r14
        mov.l   p_tab1_end, r5
        bsr     tsb_load
        nop

        mov.l   p_rdv1b, r0
        mov.l   p_rdv_magicb, r1
        mov.l   r1, @r0
        mov.l   p_rdv0b, r3
        mov.l   p_wait_limitb, r2
1:      mov.l   @r3, r1
        mov.l   p_rdv_magicb, r0
        cmp/eq  r0, r1
        bt      2f
        dt      r2
        bf      1b
        mov     #0x20, r9               ! 0x20 = peer never reached rendezvous
        bra     _fail
        nop

2:      bsr     at_on
        nop
        mov.l   c_va4b, r2
        mov.l   @r2, r8
        bsr     at_off
        nop

        mov.l   p_sent1, r0
        cmp/eq  r8, r0
        bt      3f
        mov     #0x21, r9               ! 0x21 = cpu1 read the PEER's page
        bra     _fail
        nop

3:      mov.l   p_cpu1_resultb, r0
        mov.l   p_cpu1_okb, r1
        mov.l   r1, @r0
5:      bra     5b                      ! cpu0 reports for both
        nop

        .align 2
p_sp1:          .long 0x00009000
p_p1_5000:      .long 0x80005000
p_sent1:        .long SENTINEL1
p_tsb1:
#ifdef SHARED_TSB
        .long 0x00014000        ! DELIBERATELY BROKEN: shared TSB
#else
        .long 0x00016000
#endif
p_tab1:         .long _tab1
p_tab1_end:     .long _tab1_end
p_rdv1b:        .long RDV1
p_rdv0b:        .long RDV0
p_rdv_magicb:   .long RDV_MAGIC
p_wait_limitb:  .long 0x00040000
c_va4b:         .long 0x00004000
p_cpu1_resultb: .long CPU1_RESULT
p_cpu1_okb:     .long CPU1_OK_MAGIC

! ==================== shared subroutines ====================
! tsb_load: r11 = TSB base, r14 = table start, r5 = table end.
! Programs TSBBR/TSBCFG for r11, sets ASIDR, and fills one way-0 row per
! (VA, ASID, PTEL) triple. Clobbers r0,r1,r6,r7,r8,r10,r12.
ENTRY(tsb_load)
        mov     r11, r1
        add     #JCORE_TSB_SIZE_LOG, r1 ! base | TSB_SIZE_LOG (base is aligned)
        mov.l   p_tsbbr, r0
        mov.l   r1, @r0
        mov.l   p_tsbcfg_val, r1
        mov.l   p_tsbcfg, r0
        mov.l   r1, @r0

        mov.l   p_tsbslot, r12
1:      mov.l   @r14+, r6               ! VA
        mov.l   @r14+, r7               ! ASID_TAG
        mov.l   @r14+, r8               ! PTEL
        mov     r7, r0
        .word   0x407E                  ! LDC r0, ASIDR  (slot hash is ASID-dependent)
        nop
        nop
        mov.l   r6, @r12                ! write VA to the P4 slot helper
        mov.l   @r12, r10               ! read back the 32-byte SET address
        tsb_fill r10, r6, r7, r8
        cmp/hs  r5, r14
        bf      1b
        rts
        nop

        .align 2
p_tsbbr:        .long 0xFF000014
p_tsbcfg:       .long 0xFF000018
p_tsbslot:      .long 0xFF000048
p_tsbcfg_val:   .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1

ENTRY(at_on)
        mov.l   p_mmucr_on, r0
        mov     #1, r1                  ! AT=1
        rts
         mov.l  r1, @r0

ENTRY(at_off)
        mov.l   p_mmucr_off, r0
        mov     #0, r1
        rts
         mov.l  r1, @r0

        .align 2
p_mmucr_on:     .long 0xFF000010
p_mmucr_off:    .long 0xFF000010

! Any exception at all is a failure here: nothing in this guard is supposed to
! fault. VBR+0x400 is the single TLB vector; VBR+0x100 catches the rest.
        .balign 4
ENTRY(_v_fault)
        mov.l   p_mmucr_v, r0           ! drop AT before the P0 result store
        mov     #0, r1
        mov.l   r1, @r0
        mov     #0x7E, r9
        bra     _fail
        nop

        .align 2
p_mmucr_v:      .long 0xFF000010

        ! NOTE: mmuwalk_pool (Lresult/Lpass/Lmmucr/Ltsbbr/Ltsbcfg) is emitted
        ! ONCE, after _fail at the bottom of the file. Emitting it here too
        ! would redefine every label in it. Everything above therefore uses
        ! locally-declared p_* literals, split into several small pools so
        ! every `mov.l p_x, rN` stays within the +1020-byte forward-only
        ! PC-relative reach; only _done and _fail use the shared pool, and
        ! they sit immediately before it.

        ! Row 1: code page 0, GLOBAL identity (W|X|C|G|V) so instruction fetch
        ! survives with AT on. Row 2: VA 0x4000, non-global, ASID 0x0011 --
        ! the entry under test. Both cores use the SAME ASID on purpose.
        .balign 4
_tab0:
        .long 0x00000000, 0x00000011, 0x000000CD
        .long 0x00004000, 0x00000011, 0x000040E9
_tab0_end:
_tab1:
        .long 0x00000000, 0x00000011, 0x000000CD
        .long 0x00004000, 0x00000011, 0x000050E9  ! same VA/ASID, PA 0x5000
_tab1_end:

#endif  ! CONFIG_PRIV_ARCH

ENTRY(_done)
        mov.l   Lresult, r0
        mov.l   Lpass, r1
        mov.l   r1, @r0
        bra     _done
        nop

ENTRY(_fail)
        ! Clamp 0 to 0x7F: cpu_ctb.c treats a 4-byte write of 0 as PASS, so a
        ! fail path that stored 0 would report a spurious pass.
        tst     r9, r9
        bf      1f
        mov     #0x7F, r9
1:      mov.l   Lresult, r0
        mov.l   r9, @r0
2:      bra     2b
        nop
        mmuwalk_pool
