! mmumultihit.S -- S-I5: multiple TLB entries matching one lookup.
!
! Two properties are verified, reflecting the LDTLB dedup + multi-hit design:
!
!  (A) DEDUP (the common case): re-installing the SAME VPN under the SAME ASID
!      (e.g. Linux upgrading a still-resident page's permissions / dirty bit)
!      must REPLACE the entry in place -- one valid entry, newest wins -- NOT
!      leave two matching entries. core/tlb.vhd's LDTLB scans for an existing
!      VPN+ASID (or global) match and overwrites that slot before falling back
!      to NRU. Without dedup this benign re-install would manufacture a
!      duplicate that (B) would then (correctly) fault, derailing normal use.
!
!  (B) MULTI-HIT (the fatal path, S-I5): when two entries genuinely match a
!      single lookup and dedup cannot have merged them -- only possible via
!      page-size ALIASING (a large page and a smaller page inside its range
!      have DIFFERENT exact VPNs, so exact-match dedup keeps both) -- the
!      lookup must be a DEFINED, non-recoverable fault, never a silent
!      last-match-wins pick of one candidate PA. That "pick one of N PAs,
!      unspecified which" is exactly the address-confusion primitive S-I5
!      exists to deny. The multi-hit is routed (core/cpu.vhd,
!      decode/decode_core.vhm) to the EXISTING General Illegal register-model
!      exception (EXPEVT=0x180, PC<-VBR+0x100) rather than a new EXPEVT/vector
!      pair -- the decoder's system-plane immediate field was already at
!      capacity (32/32); see components_pkg.vhd's tlb_exc_kind_t comment.
!
! Construction (all under ASID A, page 0 identity kernel code W|X|C=0xC8):
!   - VPN 0x4 (VA 0x4000): installed TWICE -- PA 0x4000 then PA 0x9000. Dedup
!     collapses to ONE entry (newest, PA 0x9000).
!   - VPN 0x5 (VA 0x5000 -> PA 0x5000): single install -- negative control.
!   - VPN 0x8 large page, page_mask=0x1 (ignores VPN[1:0] -> covers VPN 0x8..
!     0xB, VA 0x8000..0xBFFF), PA 0x8000.
!   - VPN 0xA (VA 0xA000) 4KB page, PA 0xA000. Its VA lies INSIDE the large
!     page's range, so a lookup of VA 0xA000 matches BOTH (large VPN 0x8 and
!     small VPN 0xA -- different exact VPNs, so dedup left both installed).
!
!   Test A: load VA 0x4000 -- must NOT fault (dedup resolved it), and must
!     return PA 0x9000's data (newest install won), NOT PA 0x4000's.
!   Negative control: load VA 0x5000 -- must HIT, return PA 0x5000's data.
!   Test B: load VA 0xA000 -- must FAULT (General Illegal, EXPEVT=0x180 at
!     VBR+0x100), with the destination register left at its pre-fault
!     sentinel (neither matching PA's data leaked through).
!
! VBR = _v_gi - 0x100 so the General Illegal vector (VBR+0x100) hits _v_gi.
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
!   5  multi-hit load (VA 0xA000): NO exception -- multi-hit silently resolved
!      (the RED case this guard exists to catch)
!   6  multi-hit load: EXPEVT != 0x180 (General Illegal)
!   7  multi-hit load: destination register was NOT left at the pre-fault
!      sentinel (a PA's data leaked through despite the fault)

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
        ! is inside the large page above -> a VA-0xA000 lookup multi-hits.
        ! Dedup keeps both (VPN 0x8 != VPN 0xA, exact-match). ----
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

        ! ================= Test B: MULTI-HIT (VA 0xA000) ================
        ! Must FAULT General Illegal. Set expected EXPEVT and resume target.
        mov.l   p_g_exp_expevt, r0
        mov.l   c_general_illegal, r1
        mov.l   r1, @r0                 ! g_exp_expevt = 0x180
        mov.l   p_g_bad_expevt, r0
        mov     #6, r1
        mov.l   r1, @r0                 ! EXPEVT wrong -> result 6
        mov.l   p_g_resume, r0
        mov.l   p_after_multihit, r1
        mov.l   r1, @r0                 ! resume -> after_multihit

        mov.l   p_sentinel_pre, r0
        mov     r0, r8                 ! r8 = pre-fault sentinel
        mov     #5, r9                 ! sentinel: no exception -> result 5
        mov.l   c_vaa, r2
        mov.l   @r2, r8                ! FAULTS -> _v_gi, General Illegal
        bra     _fail                  ! reached only if the load did NOT fault
        nop
ENTRY(after_multihit)

        ! ---- r8 must still hold the pre-fault sentinel: neither matching
        ! PA's data was silently returned. ----
        mov.l   p_sentinel_pre, r0
        cmp/eq  r8, r0
        mov     #7, r9                 ! fail 7 = a PA's data leaked through
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
p_sentinel_d:              .long 0xD00D0000        ! at PA 0xA000 (must NOT leak on fault)
p_sentinel_pre:            .long 0xDEAD0BAD        ! pre-fault r8 value; must survive the fault
p_p1_4000:                .long 0x80004000
p_p1_9000:                .long 0x80009000
p_p1_5000:                .long 0x80005000
p_p1_a000:                .long 0x8000A000
c_va4:                    .long 0x00004000
c_va5:                    .long 0x00005000
c_vaa:                    .long 0x0000A000
c_general_illegal:        .long 0x00000180        ! EXPEVT General Illegal
p_g_exp_expevt:           .long _g_exp_expevt
p_g_bad_expevt:           .long _g_bad_expevt
p_g_resume:               .long _g_resume
p_after_multihit:         .long after_multihit
p_l_dedup_fault:          .long l_dedup_fault
p_l_negctrl_fault:        .long l_negctrl_fault

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH

ENTRY(_done)
        mov.l   p_test_result, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS

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
_g_exp_expevt:  .long 0
_g_bad_expevt:  .long 0
_g_resume:      .long 0

        ! ---- Backing-page padding: VA 0x4000..0xA000. ----
_fault_pages:
        .space 0xA000, 0

#endif  ! CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH
