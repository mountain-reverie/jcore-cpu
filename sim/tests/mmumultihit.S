! mmumultihit.S -- S-I5: multiple TLB entries matching one lookup.
!
! Two properties are verified, reflecting the LDTLB dedup + install-time
! overlap-eviction design (jcore-soc components/cpu, task 3,
! "tlb-install-overlap"):
!
!  (A) DEDUP (the common case): re-installing the SAME VPN under the SAME ASID
!      (e.g. Linux upgrading a still-resident page's permissions / dirty bit)
!      must REPLACE the entry in place -- one valid entry, newest wins -- NOT
!      leave two matching entries. core/tlb.vhd's LDTLB scans for an existing
!      VPN+ASID (or global) match and overwrites that slot before falling back
!      to NRU.
!
!  (B) INSTALL-TIME OVERLAP EVICTION (was: "multi-hit is the defined fatal
!      path"; NO LONGER TRUE for this construction -- see below): dedup used
!      to compare VPN for EXACT equality only, so a small page installed
!      inside the range of a resident large page had a DIFFERENT exact VPN
!      and was never recognised as overlapping -- both entries stayed valid,
!      and a lookup landing in the overlap genuinely matched both, which the
!      RTL (correctly, at the time) reported as a fatal S-I5 multi-hit. Task
!      3 replaced the exact-VPN compare with a MASKED overlap compare (under
!      the intersection -- the coarser -- of the two entries' page masks),
!      so LDTLB now recognises this exact page-size-aliasing case as a
!      genuine range overlap and EVICTS the resident (large-page) entry at
!      install time, same as case (A)'s dedup. The result: this construction
!      no longer produces two coexisting matching entries at all, so the
!      lookup is a clean single hit on the newest (small-page) mapping, not
!      a fault.
!
!      The RTL's multi-hit detection itself (core/tlb.vhd tlb_match /
!      i_multihit / d_multihit, S-I5) is UNCHANGED and still present as
!      defence-in-depth: it fires if two entries ever genuinely coexist and
!      match the same lookup, e.g. through a route LDTLB's single-slot dedup
!      cannot reach (more than one pre-existing entry independently overlaps
!      a single new install -- LDTLB only evicts the first match found -- or
!      any other inconsistent SW/HW state). This guard's Test B can no
!      longer exercise the fault path through a normal install sequence,
!      because normal LDTLB installs are exactly what the fix now resolves
!      before a multi-hit can occur; it instead exercises the eviction that
!      prevents this construction from ever reaching a multi-hit.
!
! Construction (all under ASID A, page 0 identity kernel code W|X|C=0xC8):
!   - VPN 0x4 (VA 0x4000): installed TWICE -- PA 0x4000 then PA 0x9000. Dedup
!     collapses to ONE entry (newest, PA 0x9000).
!   - VPN 0x5 (VA 0x5000 -> PA 0x5000): single install -- negative control.
!   - VPN 0x8 large page, page_mask=0x1 (ignores VPN[1:0] -> covers VPN 0x8..
!     0xB, VA 0x8000..0xBFFF), PA 0x8000.
!   - VPN 0xA (VA 0xA000) 4KB page, PA 0xA000. Its VA lies INSIDE the large
!     page's range. Under the OLD exact-VPN dedup this VPN differs from the
!     large page's VPN, so both stayed resident and VA 0xA000 multi-hit.
!     Under the NEW masked-overlap dedup, this install's masked compare
!     against the resident large-page entry detects the overlap and EVICTS
!     it -- the large-page slot is overwritten with this (VPN 0xA, PA 0xA000)
!     mapping, so only ONE entry remains and the range is disjoint again.
!
!   Test A: load VA 0x4000 -- must NOT fault (dedup resolved it), and must
!     return PA 0x9000's data (newest install won), NOT PA 0x4000's.
!   Negative control: load VA 0x5000 -- must HIT, return PA 0x5000's data.
!   Test B: load VA 0xA000 -- must NOT fault (install-time overlap eviction
!     resolved it, same as Test A), and must return PA 0xA000's data (the
!     surviving, newest-installed small-page mapping), NOT PA 0x8000's data
!     and NOT a fault-time sentinel. Checking only "no fault" would pass even
!     if the TLB returned garbage or the wrong PA's data, so the loaded value
!     is checked explicitly against the small page's sentinel.
!
! VBR = _v_gi - 0x100 so the General Illegal vector (VBR+0x100) would hit
! _v_gi if any of these loads unexpectedly faulted.
!
! PTEL flag bit layout (core/tlb.vhd): bit7=W bit6=X bit5=U bit4=D bit3=C
!                                       bit2=G bit1=STALE bit0=V
! PTEL page_mask field: bits[11:8] (0x1 => ignore low 2 VPN bits, 16KB page).
!
! Result codes:
!   0  pass
!   1  dedup load (VA 0x4000) FAULTED -- re-install was not merged in place
!   2  dedup load returned wrong data -- newest install (PA 0x9000) did not win
!   3  negative control (VA 0x5000) faulted unexpectedly
!   4  negative control returned wrong data
!   5  Test B load (VA 0xA000) FAULTED -- install-time overlap eviction did
!      not resolve the large/small page overlap before the lookup (a
!      regression back toward the pre-task-3 behaviour)
!   6  retired: previously "Test B load: EXPEVT != General Illegal", from
!      when Test B was expected to fault. No longer emitted; kept out of
!      reuse so any old failure logs referencing it are not misread.
!   7  Test B load returned wrong data -- the surviving mapping was not the
!      newest (small-page, PA 0xA000) install, or stale/garbage data leaked
!      through

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
#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ---- Ensure RB=0 (bank 0). ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        nop

        ! ---- VBR = _v_gi - 0x100 (so VBR+0x100 = _v_gi, the General
        ! Illegal vector). ----
        mov.l   p_vbr_val, r0
        .word   0x402E                  ! LDC r0, VBR

        ! ---- Seed sentinels via P1 (untranslated, AT-independent):
        ! PA 0x4000=SENT_A, 0x9000=SENT_B, 0x5000=SENT_C, 0xA000=SENT_D. ----
        mov.l   p_sentinel_a, r3
        mov.l   p_p1_4000, r2
        mov.l   r3, @r2
        mov.l   p_sentinel_b, r3
        mov.l   p_p1_9000, r2
        mov.l   r3, @r2
        mov.l   p_sentinel_c, r3
        mov.l   p_p1_5000, r2
        mov.l   r3, @r2
        mov.l   p_sentinel_d, r3
        mov.l   p_p1_a000, r2
        mov.l   r3, @r2

        ! ---- ASIDR = A. ----
        mov.l   p_asid_a, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ---- Map page 0 identity, kernel-only: W|X|C = 0xC8. ----
        mov     #0, r0
        .word   0x405E                  ! LDC r0, PTEH  (VPN=0)
        mov.l   p_ptel_page0, r0
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Map VPN 0x4 (VA 0x4000 -> PA 0x4000) -- FIRST install. ----
        mov.l   p_pteh_p4, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_p4_a, r0        ! PA 0x4000 | W|C
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Map VPN 0x4 AGAIN (VA 0x4000 -> PA 0x9000), SAME ASID --
        ! dedup must overwrite the first entry in place (newest wins). ----
        mov.l   p_pteh_p4, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_p4_b, r0        ! PA 0x9000 | W|C (different PPN)
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Map VPN 0x5 (VA 0x5000 -> PA 0x5000) -- negative control. ----
        mov.l   p_pteh_p5, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_p5, r0
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Map large page VPN 0x8, page_mask=0x1 (covers VPN 0x8..0xB),
        ! PA 0x8000. ----
        mov.l   p_pteh_p8, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_p8_big, r0      ! PA 0x8000 | pageMask=1 | W|C
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Map small page VPN 0xA (VA 0xA000 -> PA 0xA000), 4KB. Its VA
        ! is inside the large page above -> this install's masked overlap
        ! compare detects the range overlap against the resident large-page
        ! entry and evicts it in place (task 3): only this mapping survives. ----
        mov.l   p_pteh_pa, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   p_ptel_pa, r0          ! PA 0xA000 | W|C
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB

        ! ---- Enable AT. ----
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! ================= Test A: DEDUP (VA 0x4000) =================
        ! Any fault here is a failure (result 1): the re-install of VPN 0x4
        ! should have merged in place, leaving a single entry -- no multi-hit.
        mov.l   p_g_exp_expevt, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0 (no fault expected)
        mov.l   p_g_bad_expevt, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! any fault -> EXPEVT-mismatch -> result 1
        mov.l   p_g_resume, r0
        mov.l   p_l_dedup_fault, r1
        mov.l   r1, @r0                 ! (fluke EXPEVT match) -> result 1 too

        mov.l   c_va4, r2
        mov.l   @r2, r8                 ! must NOT fault
        ! No fault: r8 must hold PA 0x9000's data (newest install won).
        mov.l   p_sentinel_b, r0
        cmp/eq  r8, r0
        mov     #2, r9                 ! fail 2 = newest install did not win
        bf      _fail

        ! ============ Negative control: single install (VA 0x5000) ======
        mov.l   p_g_bad_expevt, r0
        mov     #3, r1
        mov.l   r1, @r0                 ! any fault here -> result 3
        mov.l   p_g_resume, r0
        mov.l   p_l_negctrl_fault, r1
        mov.l   r1, @r0

        mov.l   c_va5, r2
        mov.l   @r2, r8
        mov.l   p_sentinel_c, r0
        cmp/eq  r8, r0
        mov     #4, r9                 ! fail 4 = wrong data on single hit
        bf      _fail

        ! ======== Test B: INSTALL-TIME OVERLAP EVICTION (VA 0xA000) =======
        ! Must NOT fault: the VPN 0xA install's masked overlap compare
        ! detected that it overlaps the resident large-page (VPN 0x8) entry
        ! and evicted it in place, so only the small-page mapping remains --
        ! this VA is a clean single hit, same shape as Test A.
        mov.l   p_g_exp_expevt, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0 (no fault expected)
        mov.l   p_g_bad_expevt, r0
        mov     #5, r1
        mov.l   r1, @r0                 ! any fault -> EXPEVT-mismatch -> result 5
        mov.l   p_g_resume, r0
        mov.l   p_l_multihit_fault, r1
        mov.l   r1, @r0                 ! (fluke EXPEVT match) -> result 5 too

        mov.l   c_vaa, r2
        mov.l   @r2, r8                 ! must NOT fault
        ! No fault: r8 must hold PA 0xA000's data (the surviving,
        ! newest-installed small-page mapping) -- NOT PA 0x8000's data, and
        ! not merely "didn't fault": a wrong/garbage PA must also be caught.
        mov.l   p_sentinel_d, r0
        cmp/eq  r8, r0
        mov     #7, r9                 ! fail 7 = surviving mapping's data wrong
        bf      _fail

        bra     _done
        nop

        ! ---- Fail landing pads for loads that must not fault. ----
ENTRY(l_dedup_fault)
        mov     #1, r9
        bra     _fail
        nop
ENTRY(l_negctrl_fault)
        mov     #3, r9
        bra     _fail
        nop
ENTRY(l_multihit_fault)
        mov     #5, r9
        bra     _fail
        nop

        .align 2
p_rbclear:              .long 0xDFFFFFFF
p_vbr_val:               .long _v_gi - 0x100
p_mmucr:                  .long 0xFF000010
p_ptel_page0:             .long 0x000000C8        ! W|X|C, kernel-only identity code page
p_pteh_p4:                .long 0x00004000
p_ptel_p4_a:              .long 0x000040C8        ! PA 0x4000 | W|C -- first install
p_ptel_p4_b:              .long 0x000090C8        ! PA 0x9000 | W|C -- re-install (dedup)
p_pteh_p5:                .long 0x00005000
p_ptel_p5:                .long 0x000050C8        ! PA 0x5000 | W|C -- negative control
p_pteh_p8:                .long 0x00008000
p_ptel_p8_big:            .long 0x000081C8        ! PA 0x8000 | pageMask=1 | W|C -- large page
p_pteh_pa:                .long 0x0000A000
p_ptel_pa:                .long 0x0000A0C8        ! PA 0xA000 | W|C -- 4KB inside large page
p_asid_a:                 .long 0x00000011
p_sentinel_a:              .long 0xA51DA51D        ! at PA 0x4000 (must NOT be returned)
p_sentinel_b:              .long 0xB33FB33F        ! at PA 0x9000 (dedup: newest -> returned)
p_sentinel_c:              .long 0xC0FFEE00        ! at PA 0x5000 (negative control)
p_sentinel_d:              .long 0xD00D0000        ! at PA 0xA000 (surviving install, must be returned)
p_p1_4000:                .long 0x80004000
p_p1_9000:                .long 0x80009000
p_p1_5000:                .long 0x80005000
p_p1_a000:                .long 0x8000A000
c_va4:                    .long 0x00004000
c_va5:                    .long 0x00005000
c_vaa:                    .long 0x0000A000
p_g_exp_expevt:           .long _g_exp_expevt
p_g_bad_expevt:           .long _g_bad_expevt
p_g_resume:               .long _g_resume
p_l_dedup_fault:          .long l_dedup_fault
p_l_negctrl_fault:        .long l_negctrl_fault
p_l_multihit_fault:       .long l_multihit_fault

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

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

#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

        ! ---- General Illegal handler at VBR+0x100. Disables AT, verifies
        ! EXPEVT == g_exp_expevt (distinguishing S-I5's multi-hit dispatch
        ! from any other trap), then resumes at the caller-selected _g_resume
        ! label. A load that must NOT fault points _g_resume at a fail pad. ----
        .balign 4
        .space 0x100, 0
        .balign 4
_v_gi:                                   ! = VBR + 0x100
        mov.l   Hmmucr, r0
        mov     #0, r1
        mov.l   r1, @r0                 ! MMUCR = 0 (disable AT)
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   Hexp_expevt, r1
        mov.l   @r1, r1
        cmp/eq  r0, r1
        bf      _h_bad_expevt
        mov.l   Hresume, r0
        mov.l   @r0, r0                 ! r0 = resume label address
        .word   0x404E                  ! LDC r0, SPC
        rte
        nop

_h_bad_expevt:
        mov.l   Hbad_expevt, r0
        mov.l   @r0, r9                 ! r9 = fail code (EXPEVT mismatch)
        bra     _fail
        nop

        .align 2
Hmmucr:         .long 0xFF000010
Hexp_expevt:    .long _g_exp_expevt
Hresume:        .long _g_resume
Hbad_expevt:    .long _g_bad_expevt

        ! ---- Handler globals. ----
        .balign 4
_g_exp_expevt:  .long 0xFFFFFFFF        ! sentinel: unset (a real sub-test always overwrites)
_g_bad_expevt:  .long 0x5A              ! loud fail-code sentinel: names an early fault
_g_resume:      .long 0

        ! ---- Backing-page padding: VA 0x4000..0xA000. ----
_fault_pages:
        .space 0xA000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
