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
! NOTE: this file emits NO code -- only macro definitions. `mmuwalk_pool` emits
! the literal pool the PASS/FAIL macros reference; invoke it AFTER their last
! use in a function (SH mov.l @(disp,PC) is forward-only, +1020 bytes).

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
