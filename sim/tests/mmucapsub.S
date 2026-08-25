! mmucapsub.S -- NON-BASE-FIRST touches of superpage mappings, under DTLB
! capacity pressure. Lane 1, cpu_tb.
!
! A three-line parameterisation of sim/tests/mmucapd.S -- same harness, same
! legs, same result codes, same probe windows. See
! docs/mmu/tlb-capacity-suite.md for the suite as a whole. Only two constants
! change:
!
!   CAP_PM       = 1  -- every mapping under test is a 16 KB superpage
!                       (page_offset_mask(pm=1) sources PA bits 13:12 from
!                        the VA, core/components_pkg.vhd), so one mapping is
!                        four 4 KB sub-pages and still exactly ONE TLB entry.
!   CAP_FIRSTSUB = 3  -- the FIRST touch of every mapping is its LAST sub-page.
!                       No mapping in this build is ever entered through its
!                       own first PAGE_SIZE.
!
! WHY THIS IS A DIFFERENT TEST, not a re-run
! ==========================================
! With CAP_FIRSTSUB = 3 the harness's leg-L probe pair becomes the property
! this file exists for:
!
!   probe 1 (code 0x23)  touching sub-page 3 of an evicted mapping walks the
!                        TSB. The row it hits is TAGGED WITH SUB-PAGE 3's OWN
!                        VPN -- the TSB is 4 KB-granular by contract (C1:
!                        core/tlb_walk.vhd compares bus_d(31:12) against
!                        va_reg(31:12); tsb_ptr() hashes VA[31:12]) -- while
!                        its PTEL carries the MAPPING BASE's PPN and pm=1.
!   probe 2 (code 0x25)  touching sub-page 0 immediately afterwards must be a
!                        plain TLB hit: NO further walk, and the data must be
!                        the base sub-page's own frame.
!
! That pair is only satisfiable if the walker installs the RAW faulting VPN
! and the match path masks it by the entry's own page_mask. It is the property
! mmupmrawvpn.S locks for a single mapping and a single unaligned touch; this
! file puts it under 24 mappings and forced eviction, which is where an
! install-time mask or a hardwired page_mask stops being an argument and starts
! being a measurement.
!
! The base-VA re-sweep (leg F, code 0x31) then re-walks all 24 mappings through
! their SUB-PAGE 0 rows, so both tag granularities are exercised against the
! same PTEL in one run.
!
! WORKING SET. 24 mappings x 16 KB = 384 KB of VA, one DTLB entry each, against
! a 16-entry DTLB. The alias window is _frames + 0x0040_0000 upward and stays
! well inside the cosim's 16 MB backed window (P5); see mmucapd.S's header.
!
! NON-VACUITY. Group C, exactly as the harness. The harness's own M1/M2 (DTLB
! `entries` 16 -> 32 and 16 -> 4) apply unchanged. Two further mutations are
! specific to THIS parameterisation, and BOTH leave mmucapd -- which is pm=0
! throughout -- green. That split is the whole point: neither shortcut is
! visible to a base-page guard.
!
!   M3  core/tlb.vhd install path (the "assume one page size" shortcut):
!         ram(idx).page_mask <= ptel(11 downto 8);   ->   <= "0000";
!       MEASURED: FAIL mmucapsub, Result=17 (0x11); mmucapd PASS.
!       NOTE the code, which is EARLIER than the probe pair and was not what
!       this file first predicted. With pm forced to 0 the entry's
!       page_offset_mask is empty, so PA bits 13:12 come from the (zero) PPN
!       instead of the VA and the very first sub-page-3 touch in leg S reads
!       the mapping BASE's frame. The relocation breaks before the coverage
!       property is ever reached. Recorded as measured, not as predicted.
!
!   M4  core/tlb.vhd tlb_match (the "match at 4 KB granularity regardless of
!       size" shortcut):
!         ... and vpn_compare_mask(entry.page_mask) ...
!                                    ->  ... and vpn_compare_mask("0000") ...
!       Relocation is untouched, so leg S still passes: every first touch
!       matches its own VPN exactly. Probe 2's touch of sub-page 0 then finds
!       no matching entry and walks.
!       MEASURED: FAIL mmucapsub, Result=37 (0x25); mmucapd PASS.
!       This is the mutation that pins probe 2 specifically.
!
! RESULT CODES: identical to mmucapd.S; see its header.
!
#define CAP_PM       1
#define CAP_FIRSTSUB 3
#include "mmucapd.S"
