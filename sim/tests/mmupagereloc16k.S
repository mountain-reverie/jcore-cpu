! mmupagereloc16k.S -- 16 KB page with a NON-IDENTITY frame (J4, cpu_cache_tb).
! Closes the coverage gap that every other large-page guard is identity (PA==VA):
! maps VA 0x10000 -> PA 0x40000 (frame != VA), pm=1. A store through a sub-region
! VA 0x12000 (offset 0x2000 within the 16 KB page) must relocate to PA 0x42000
! (frame 0x40000 + offset 0x2000). Asserts: PA 0x42000 == sentinel (variable
! frame/offset split works for a real frame substitution), PA 0x12000 == 0 (the
! VA's identity location is NOT written -> relocation actually moved it), and
! PA 0x40000 == 0 (frame base untouched). Exercises the pm>=1 (ppn_lo and not offm)
! path against a frame that differs from the VA -- which the identity guards do not.
!
! ---- walker-install version (retire-LDTLB) --------------------------------
! The 16 KB non-identity mapping now reaches the TLB through the hardware TSB
! walker. The three physical assertions are unchanged (sentinel at PA 0x42000,
! nothing at PA 0x12000, nothing at PA 0x40000), and a NEW result 4 makes the
! guard STRONGER on the axis it is named for:
!
! Under LDTLB this guard proved frame substitution but NOT that a 16 KB entry
! was doing it -- a plain 4 KB entry for VA 0x12000 -> PA 0x42000 satisfies
! every check it made. Now the guard TOUCHES the base VPN first (VA 0x10800,
! same 4 KB VPN as the only row that matters), snapshots the walk counters at
! 0xFF000054, and then requires the VA 0x12000 access NOT to have walked. If
! the page-mask term were broken, that access would miss, walk, install a 4 KB
! entry and still land on PA 0x42000 -- all three data checks would pass and
! only result 4 catches it.
!
! Setup requirements walker-only install adds, none of which LDTLB had:
!   * RB MUST be 0 -- core/cpu.vhd's walk_req is gated on dp_sr.rb = '0' and
!     the cosim starts in bank 1, so without the clear nothing ever walks and
!     the failure is silent (MMUCR reads back 1, the walk counter stays 0).
!   * Every page the CPU FETCHES from must be U=0: once an entry reaches the
!     ITLB, SMEP (core/tlb.vhd:247, kernel fetch of a user page) rejects it.
!   * The image is padded past the END of the TSB -- the walker reads the TSB
!     BY PHYSICAL ADDRESS and the cosim backs SRAM only within the loaded
!     image, so a TSB beyond it reads as nothing and every walk silently
!     misses with no fault and no data.
!   * The sub-page row for the 16 KB page is present but PROVABLY NEVER READ
!     (that is what the walk-counter check asserts). It is kept only because
!     dropping it trips the cpu_cache_tb anomaly recorded in mmupage16k.S.
!
! ---- _fail integrity net ----
! _fail writes r9 verbatim to TEST_RESULT_ADDRESS; sim/cpu_ctb.c's test_result()
! treats any 4-byte write of 0 as PASS. Since the per-sub-test fail-code globals
! start at 0 until a sub-test sets them, a fault reaching _fail BEFORE the first
! sub-test runs would otherwise silently report PASS. _fail now clamps r9==0 to
! 0x7F before the store so 0 can never leave through the fail path. Fail-code
! globals below use loud sentinels (_g_exp_* = 0xFFFFFFFF, _g_bad_* = small
! distinct values) so an early exit still names its cause.
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
ENTRY(start)
#if CONFIG_PRIV_ARCH
        ! ---- Ensure RB=0 (bank 0). core/cpu.vhd's walk_req is gated on
        ! ---- dp_sr.rb = '0' and the cosim starts in bank 1, so without this
        ! ---- NO walk is ever armed: AT comes on, nothing installs, and the
        ! ---- walk counter at 0xFF000054 never leaves zero.
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop
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
        mov.l   p_tsbslot, r12
        mov.l   p_tab, r14
        mov.l   p_tab_end, r5
1:      mov.l   @r14+, r6              ! VA
        mov.l   @r14+, r7              ! ASID
        mov.l   @r14+, r8              ! PTEL
        mov     r7, r0
        .word   0x407E                 ! LDC r0, ASIDR
        nop
        nop
        mov.l   r6, @r12               ! write VA -> helper
        mov.l   @r12, r10              ! 32-byte-aligned SET address
        tsb_fill r10, r6, r7, r8
        cmp/hs  r5, r14
        bf      1b
        bra     _run
        nop

        ! ---- Literal pool 1 (setup). `mov.l @(disp,PC)` is FORWARD-only and
        ! ---- reaches +1020 bytes, so migrated bodies need two pools.
        .align 2
p_rbclear:     .long 0xDFFFFFFF
p_tsbbr_addr:  .long 0xFF000014
p_tsbbr_val:   .long 0x00044008        ! base=0x00044000, TSB_SIZE_LOG=8
p_tsbcfg_addr: .long 0xFF000018
p_tsbcfg_val:  .long 0x00000061        ! HASH_SHIFT=6, HASH_MODE=1
p_tsbslot:     .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
p_tab:         .long _tsb_tab
p_tab_end:     .long _tsb_tab_end

        .balign 4
_tsb_tab:
        ! VA          ASID        PTEL
        .long 0x00000000, 0x00000000, 0x000000C9  ! identity code page, U=0 (SMEP)
        .long 0x00010000, 0x00000000, 0x000401E9  ! 16 KB page, frame PA 0x40000
        .long 0x00012000, 0x00000000, 0x000401E9  ! sub-page row -- never read
_tsb_tab_end:

ENTRY(_run)
        ! clear PA 0x40000 (frame base), 0x42000 (frame sub), 0x12000 (VA identity)
        mov     #0, r1
        mov.l   p_p2_frame, r2         ! 0xA0040000 -> PA 0x40000
        mov.l   r1, @r2
        mov.l   p_p2_fsub,  r3         ! 0xA0042000 -> PA 0x42000
        mov.l   r1, @r3
        mov.l   p_p2_vid,   r7         ! 0xA0012000 -> PA 0x12000 (VA's identity loc)
        mov.l   r1, @r7
        ! enable AT
        mov.l   p_mmucr, r0
        mov     #1, r4
        mov.l   r4, @r0
        ! ---- Install the 16 KB entry by touching its BASE VPN. VA 0x10800 is
        ! ---- the same 4 KB VPN as the table row, and a different cache line
        ! ---- from anything read back below.
        mov.l   q_va_base, r11
        mov.l   @r11, r12
        ! ---- Snapshot the walk counters AFTER that install. ----
        mov.l   q_walkcnt, r11
        mov.l   @r11, r13
        ! store SENTINEL through translated VA 0x12000 (offset 0x2000 in the 16KB page)
        mov.l   p_sentinel, r5         ! sentinel 0x5E91A140
        mov.l   p_va_sub, r6           ! 0x00012000
        mov.l   r5, @r6
        ! drain write-through buffer
        mov     #20, r0
1:      dt      r0
        bf      1b
        ! read back via P2
        mov.l   @r3, r8                ! PA 0x42000: expect sentinel (relocated frame+offset)
        mov.l   @r7, r10               ! PA 0x12000: expect 0 (VA identity loc untouched)
        mov.l   @r2, r11               ! PA 0x40000: expect 0 (frame base untouched)
        mov.l   p_sentinel, r0
        cmp/eq  r8, r0
        mov     #1, r9                 ! fail 1 = sub-page did not relocate to frame+offset PA 0x42000
        bf      _fail
        mov     #0, r0
        cmp/eq  r10, r0
        mov     #2, r9                 ! fail 2 = VA identity loc PA 0x12000 wrongly written (no relocation)
        bf      _fail
        mov     #0, r0
        cmp/eq  r11, r0
        mov     #3, r9                 ! fail 3 = frame base PA 0x40000 wrongly written
        bf      _fail
        ! ---- The VA 0x12000 access must NOT have walked: it can only have
        ! ---- been translated by the page-mask term of the entry installed
        ! ---- from VA 0x10800. See the header.
        mov.l   q_walkcnt, r11
        mov.l   @r11, r12
        cmp/eq  r13, r12
        mov     #4, r9                 ! fail 4 = sub-page walked, not a 16 KB hit
        bf      _fail
        bra     _done
        nop
        .align 2
q_va_base:   .long 0x00010800          ! base VPN of the 16 KB page
q_walkcnt:   .long 0xFF000054          ! [31:16]=cnt_walks [15:0]=cnt_hits
p_mmucr:     .long 0xFF000010
p_sentinel:  .long 0x5E91A140
p_p2_frame:  .long 0xA0040000
p_p2_fsub:   .long 0xA0042000
p_p2_vid:    .long 0xA0012000
p_va_sub:    .long 0x00012000
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
        ! Pad past the TSB (0x44000..0x45FFF); see the header note.
        .org 0x46000
