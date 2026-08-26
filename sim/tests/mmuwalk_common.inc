! mmuwalk_common.inc -- shared harness for the walker guards.
!
! Provides:
!   PASS / FAILn  macros writing TEST_RESULT_ADDRESS then spinning
!   tsb_fill / tsb_fill_way  macros: write one way of a 32-byte TSB set
!   Lresult / Lmmucr / Ltsbbr / Ltsbcfg literal pool
!
! TSB SET format (Phase-2 Task 4): one 32-byte line, two 16-byte ways.
!   way 0: +0  tag_hi = VPN (VA & PAGE_MASK)
!          +4  tag_lo = ASID_TAG
!          +8  data   = PTEL
!          +12 reserved
!   way 1: +16 / +20 / +24 / +28, same order
! tsb_ptr() (core/datapath_pkg.vhd) now returns the 32-byte-aligned SET
! address, and TSB_SIZE_LOG counts SETS.
!
! NOTE: this file emits NO code of its own -- only macro definitions, so a
! guard that includes it and invokes nothing is unchanged by it. `mmuwalk_pool`
! emits the literal pool the PASS/FAIL macros reference; invoke it AFTER their
! last use in a function (SH mov.l @(disp,PC) is forward-only, +1020 bytes).
! The GUARD BOILERPLATE block at the end of this file is the same deal: those
! macros DO emit code, but only where they are invoked.

        .macro  FAIL code
        mov.l   Lresult, r0
        mov     #\code, r1
        mov.l   r1, @r0
1:      bra     1b
        nop
        .endm

        .macro  PASS
        mov.l   Lresult, r0
        mov.l   Lpass, r1
        mov.l   r1, @r0
1:      bra     1b
        nop
        .endm

        ! tsb_fill_way rset, woff, rvpn, rasid, rptel
        ! \woff is the WAY BYTE OFFSET inside the 32-byte set: 0 for way 0,
        ! 16 for way 1. Writes data first, tag_lo second, tag_hi LAST. tag_hi
        ! is the commit point because the walker compares it first (design
        ! spec section 6.2), so a walker landing mid-sequence must never see a
        ! matching tag over a half-written entry.
        .macro  tsb_fill_way rset, woff, rvpn, rasid, rptel
        mov.l   \rptel, @(\woff + 8, \rset)
        mov.l   \rasid, @(\woff + 4, \rset)
        mov.l   \rvpn,  @(\woff + 0, \rset)
        .endm

        ! tsb_fill rset, rvpn, rasid, rptel -- way 0 of the set. Kept as the
        ! short form because most guards only care that SOME way holds the
        ! entry, and the walker probes way 0 first.
        .macro  tsb_fill rslot, rvpn, rasid, rptel
        tsb_fill_way \rslot, 0, \rvpn, \rasid, \rptel
        .endm

        .macro  mmuwalk_pool
        .align 2
Lresult:  .long TEST_RESULT_ADDRESS
Lpass:    .long TEST_PASS_MAGIC
Lmmucr:   .long 0xFF000010
Ltsbbr:   .long 0xFF000014
Ltsbcfg:  .long 0xFF000018
        .endm

! ===========================================================================
! GUARD BOILERPLATE.
!
! Everything below emits code, but only where a guard INVOKES it -- this file
! still contributes nothing to a guard that does not. The pieces were factored
! out of sim/tests/mmucapd.S and mmucapi.S, which between them carried ~230
! byte-identical lines of vector table, exit path, TLB flush and TSB seeding.
! Two copies of a thing is where a divergence hides, and the seeding loop in
! particular is the part a guard most needs to be able to trust.
!
! They are deliberately register-passing rather than literal-pool-prefix
! passing (the FLUSH_TLB pfx style mmudrain.S uses): SH-2 PC-relative loads
! reach only +1020 bytes, so a macro that emits its own pool constrains where
! the caller may expand it. Passing a register that the caller already loaded
! moves that problem to the caller, who can see their own pool.
! ===========================================================================

        ! mmu_vect_block <stack> -- the reset/exception vector table plus the
        ! sim_instr block the cosim scans for. Leaves the assembler in .text.
        ! Requires: start, _done, _fail, and sim_instr.h.
        .macro  mmu_vect_block stack
        .section .vect
        .long   start
        .long   \stack
        .long   start
        .long   \stack
        .rept   60
        .long   0
        .endr
        .long   SIM_INSTR_MAGIC
        .long   _sim_instr_end
        .long   _done
        .long   _fail
        .long   CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0
        .text
        .endm

        ! mmu_done_fail <pfx> -- the standard exit pair.
        ! _done writes TEST_PASS_MAGIC; _fail writes r9, with the integrity net
        ! that rewrites a zero to 0x7F. The net matters because a guard that
        ! falls into _fail without setting r9 would otherwise be
        ! indistinguishable from a pass -- 0x7F is what a debugger sees then.
        ! <pfx> namespaces the two literals so several macros can coexist.
        .macro  mmu_done_fail pfx
        .globl  _done
        .balign 4
_done:
        mov.l   \pfx\()_tr, r0
        mov.l   \pfx\()_trp, r9
        mov.l   r9, @r0
        bra     _done
        nop
        .globl  _fail
        .balign 4
_fail:
        mov.l   \pfx\()_tr, r0
        tst     r9, r9
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
\pfx\()_tr:     .long TEST_RESULT_ADDRESS
\pfx\()_trp:    .long TEST_PASS_MAGIC
        .endm

        ! mmu_flush_at <rmmucr> -- leg-boundary TLB reset. <rmmucr> must
        ! already hold 0xFF000010. AT goes off FIRST: a TI pulse taken with
        ! AT=1 unmaps the executing page and the next fetch double-faults with
        ! no way back (mmudrain.S trap 4). Clobbers r1.
        .macro  mmu_flush_at rmmucr
        mov     #0, r1
        mov.l   r1, @\rmmucr            ! AT off: translation bypassed
        mov     #4, r1
        mov.l   r1, @\rmmucr            ! MMUCR.TI: invalidate every entry
        mov     #0, r1
        mov.l   r1, @\rmmucr            ! TI released
        mov     #1, r1
        mov.l   r1, @\rmmucr            ! AT on -- the code pages re-walk in
        .endm

        ! mmu_vec_handlers <pfx> <pagealign> <gen_code> <tlb_code>
        ! <pagealign> is a parameter for the same reason mmu_seed_routine's
        ! <pagesz> is -- this file is #included, so a reference to the caller's
        ! PAGE_SZ resolves at include time and breaks for a guard that defines
        ! it afterwards. 4 KB is the architectural page size and nothing here
        ! wants anything else today; the parameter is for consistency, not for
        ! an anticipated caller.
        !
        ! The VBR block for a guard that expects NO exception at all: _vecblk
        ! is PAGE-aligned, so `.space 0x100` lands the general handler exactly
        ! at VBR+0x100 and the `.balign 0x400` lands the TLB handler exactly at
        ! VBR+0x400 (the general body is far shorter than 0x300 bytes). Each
        ! drops MMUCR.AT and reports its code.
        !
        ! Both run with SR.RB=1. r9 is NOT banked, so the code survives into
        ! _fail; r0/r1 are, so bank 0's copies are untouched.
        .macro  mmu_vec_handlers pfx, pagealign, gen_code, tlb_code
        .balign \pagealign
_vecblk:
        .space  0x100, 0
_v_gen:                                 ! VBR + 0x100
        mov.l   \pfx\()g_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov     #\gen_code, r9
        mov.l   \pfx\()g_fail, r0
        jmp     @r0
        nop
        .align 2
\pfx\()g_mmucr: .long 0xFF000010
\pfx\()g_fail:  .long _fail
        .balign 0x400
_v_cap:                                 ! VBR + 0x400
        mov.l   \pfx\()t_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        mov     #\tlb_code, r9
        mov.l   \pfx\()t_fail, r0
        jmp     @r0
        nop
        .align 2
\pfx\()t_mmucr: .long 0xFF000010
\pfx\()t_fail:  .long _fail
        .endm

        ! mmu_seed_routine <pfx> <pagesz> -- emits `_seed`, which writes one
        ! TSB row per 4 KB page of a VA range. Call it with AT OFF; the row
        ! writes are then plain P0 stores.
        !
        ! <pagesz> is a PARAMETER rather than a reference to the includer's
        ! PAGE_SZ on purpose: this file is #included, so cpp expands the macro
        ! BODY at include time, and a guard that defines PAGE_SZ after the
        ! #include (the natural order) leaves the token undefined -- which
        ! surfaces as `undefined reference to PAGE_SZ' from the LINKER, a long
        ! way from the cause. Measured while writing this.
        !
        !   r1  first VA          (4 KB aligned)
        !   r2  end VA, exclusive
        !   r3  PPN mask -- 0xFFFFF000 for 4 KB pages, ~(MAP_SPAN-1) for a
        !       superpage, which folds every sub-page's row onto the MAPPING
        !       BASE's PPN so they install as ONE entry
        !   r4  VA-to-PA delta    (0 for an identity range)
        !   r5  PTEL flag bits
        !   r9  the setup-failure code to report if a set is full
        !
        !   PA   = (VA - r4) and r3
        !   PTEL = PA or r5
        !
        ! Per-4-KB rows are the CONTRACT, not a convenience: core/tlb_walk.vhd
        ! compares bus_d(31 downto 12) against va_reg(31 downto 12) and
        ! core/datapath_pkg.vhd's tsb_ptr() hashes VA[31:12], so a superpage
        ! needs one row per sub-page, each tagged with that sub-page's own VPN.
        !
        ! Two-way insert: way 0 unless it already holds a valid entry. A THIRD
        ! colliding VPN is a harness problem, not a CPU defect, and jumps to
        ! _setup_full with the caller's r9 rather than silently evicting a row
        ! the run depends on.
        !
        ! Clobbers r0, r1, r6, r7, r8, r12. Preserves r9. Returns via RTS, so
        ! the caller must not already be inside a JSR.
        ! Requires: _setup_full, and the tsb_fill macro above.
        .macro  mmu_seed_routine pfx, pagesz
        .globl  _seed
        .balign 4
_seed:
        mov.l   \pfx\()_slot, r12
        mov.l   \pfx\()_psz, r8
1:      mov     r1, r6
        sub     r4, r6                  ! r6 = PA of this 4 KB page
        and     r3, r6                  ! r6 = PA the PTEL should carry
        or      r5, r6                  ! r6 = PTEL
        mov.l   r1, @r12                ! ask the P4 slot helper for this VA
        mov.l   @r12, r7                ! r7 = 32-byte-aligned SET address
        mov.l   @(8, r7), r0
        tst     #1, r0                  ! way 0 data word: V clear?
        bt      3f
        add     #16, r7                 ! try way 1
        mov.l   @(8, r7), r0
        tst     #1, r0
        bt      3f
        mov.l   \pfx\()_full, r0        ! both ways occupied
        jmp     @r0
        nop
3:      mov     #0, r0                  ! ASID_TAG = 0
        tsb_fill r7, r1, r0, r6
        add     r8, r1
        cmp/hs  r2, r1
        bf      1b
        rts
        nop
        .align 2
\pfx\()_slot:   .long 0xFF000048        ! P4_TSBSLOT: tsb_ptr(VA, ASIDR)
\pfx\()_psz:    .long \pagesz
\pfx\()_full:   .long _setup_full
        .endm
