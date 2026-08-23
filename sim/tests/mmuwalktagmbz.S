! mmuwalktagmbz.S -- CONTRACT LOCK C2 (docs/mmu/pagemask-walker-contract.md
! sections 2/C1, 6/R2 and 7.2). Lane 1, cpu_tb.
!
! C1 says `tag_hi[11:0]` are RESERVED, MUST BE ZERO, and R2 says the walker's
! `bus_d(11 downto 0) = x"000"` term is the ENFORCEMENT of that -- the one
! thing keeping those twelve bits available for a future architectural use.
! A row that is perfect in every other respect but sets `tag_hi[11:0] = 0x001`
! MUST be rejected.
!
! This file is a three-line parameterisation of mmuwalkcoarsetag.S: the ONLY
! difference is the deliberately-wrong tag value written into the row, and the
! result-code base. Keeping one harness means the C1 and C2 locks cannot drift
! apart in their setup, their counter accounting or their identity discipline
! -- the same reason mmudspcprobe_late{b,w,c,m,mw} share one harness.
!
! RESULT CODES (base 0x20; see mmuwalkcoarsetag.S for the full descriptions)
!   0x21  phase 1: NO exception -- the MBZ term did not reject the row.
!                  THIS IS THE MUTATION CODE.
!   0x22..0x25  phase 1: EXPEVT / TEA / cnt_hits moved / cnt_walks did not move
!   0x26..0x28  phase 2: refault / wrong data / no walk hit
!   0xE7  phase 1 TRIP (contract P2 fallback range: phase 1 -> 0xE7,
!         phase 2 -> 0xE8)
!   0xD1  unexpected GENERAL exception
!
! MUTATION EVIDENCE
! =================
!   (see the block at the end of mmuwalkcoarsetag.S's header)
!
#define CTAG_BASE   0x20
#define CTAG_TRIP1  0xE7
#define CTAG_BADTAG 0x00045001          /* canonical VA, MBZ field non-zero */
#include "mmuwalkcoarsetag.S"
