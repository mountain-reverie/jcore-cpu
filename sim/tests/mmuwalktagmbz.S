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
! M2 -- the `bus_d(11 downto 0) = x"000"` term deleted from st_tag_hi
!       (contract R2's exact wording):
!         mmuwalktagmbz     RED, Result=33 (0x21)  <- ITS OWN CODE
!         mmuwalkcoarsetag  PASS   mmupmtlbmask  PASS
!         mmupmrawvpn       PASS   mmupmmixzero  PASS
!
! M1 -- st_tag_hi ALSO accepts a 16 KB-granular tag (C1's mutation):
!       mmuwalktagmbz PASS. Correct and worth stating: this row's tag is the
!       CANONICAL VA with a dirty MBZ field, so a coarser compare does not
!       rescue it -- only deleting the MBZ term does.
!
! M3 -- page_mask hardwired to "0000": RED, Result=39 (0x27), phase 2 data.
! M4 -- vpn_compare_mask("0000") off n=0: PASS.
! M6 -- data read before tag_hi: RED via p_walk_read_order (global invariant).
!
! RESTORED: pristine RTL, PASS.
! All runs: docker ghcr.io/mountain-reverie/jcore-cpu-ci:latest, CPU_VARIANT=j4,
! SIM_TOP=cpu_tb, --stop-time=120us, measured 2026-08-22. Every mutation run
! REBUILT the cosim (never `-n`, which skips the build and measures stale
! hardware). To re-apply any mutation you need BOTH halves of
! docs/mmu/group-c-locks.md: section 3 (the edits, one row per mutation)
! and section 9 (the run). That file also carries the full cross-table
! and, per row, whether it has been independently reproduced or rests on
! this record alone.
!
!
#define CTAG_BASE   0x20
#define CTAG_TRIP1  0xE7
#define CTAG_BADTAG 0x00045001          /* canonical VA, MBZ field non-zero */
#include "mmuwalkcoarsetag.S"
