! mmuwalk_common.inc -- shared harness for the walker guards.
!
! Provides:
!   PASS / FAILn  macros writing TEST_RESULT_ADDRESS then spinning
!   tsb_fill      macro: write a TSB slot in TODAY's format
!   Lresult / Lmmucr / Ltsbbr / Ltsbcfg literal pool
!
! TSB slot format this phase (unchanged from master):
!   +0 tag_hi = VPN (VA & PAGE_MASK)
!   +4 tag_lo = ASID_TAG
!   +8 data   = PTEL
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

        ! tsb_fill rslot, rvpn, rasid, rptel
        ! Writes data first, tag_lo second, tag_hi LAST. tag_hi is the commit
        ! point because the walker compares it first (design spec section 6.2).
        .macro  tsb_fill rslot, rvpn, rasid, rptel
        mov.l   \rptel, @(8, \rslot)
        mov.l   \rasid, @(4, \rslot)
        mov.l   \rvpn,  @(0, \rslot)
        .endm

        .macro  mmuwalk_pool
        .align 2
Lresult:  .long TEST_RESULT_ADDRESS
Lpass:    .long TEST_PASS_MAGIC
Lmmucr:   .long 0xFF000010
Ltsbbr:   .long 0xFF000014
Ltsbcfg:  .long 0xFF000018
        .endm
