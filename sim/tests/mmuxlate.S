! mmuxlate.S -- LDTLB + address-translation integration test (J4+MMU_ARCH).
!
! Installs a TLB entry mapping VA=PA (identity, P0 range) and verifies a
! load through the translated P0 address returns the value written via P1
! (direct physical, no TLB).
!
! result 0 = pass; nonzero = failure code:
!   1  AT=0 direct load sanity failed (ROM or .bss not readable)
!   2  LDTLB + AT=1 load returned wrong value (TLB miss or bad translation)
!
! LDC r0,PTEH  = 0100 0000 0101 1110 = 0x405E
! LDC r0,PTEL  = 0100 0000 0110 1110 = 0x406E
! LDC r0,ASIDR = 0100 0000 0111 1110 = 0x407E
! LDTLB        = 0000 0000 0011 1000 = 0x0038
! MMUCR P4 address = 0xFF000010, AT bit = bit 0

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
#if CONFIG_MMU_ARCH

        ! --- Test A: AT=0 sanity: write and read phys_buf directly -----
        ! phys_buf is in .bss (P0 range); read it via phys_buf directly.
        ! At reset AT=0 so this is a direct physical access.
        mov.l   p_testval, r4          ! r4 = 0xBEEFCAFE
        mov.l   p_physbuf, r5          ! r5 = &phys_buf (PA in P0 range)
        mov.l   r4, @r5                ! *phys_buf = 0xBEEFCAFE (AT=0, direct)
        mov.l   @r5, r6
        cmp/eq  r4, r6
        mov     #1, r9
        bf      _fail

        ! --- Test B: install TLB entry, enable AT, load via P0 VA -----
        ! We use an identity map: VA = PA = &phys_buf.
        ! PA is in P0 range (< 0x80000000), so TLB translation applies.
        ! VPN = VA[31:12]; PPN = PA[31:10]; flags = 0xE8 (w+x+u+c).
        !
        ! Compute PTEH = (PA & ~0xFFF):
        mov     r5, r0
        mov.l   p_vpn_mask, r1         ! r1 = 0xFFFFF000
        and     r1, r0                 ! r0 = PA & ~0xFFF = VPN<<12 (ASID=0)
        .word   0x405E                 ! LDC r0,PTEH

        ! Compute PTEL = (PA >> 10) | 0xE8:
        ! PPN field is bits[28:10] of PTEL = PA[28:10] at position [28:10].
        ! SH-4 PTEL: bits[28:10]=PPN (19 bits), bits[7:0]=protection flags.
        ! PTEL = (PA >> 10) << 10 | flags is NOT right.
        ! Actually PTEL[28:10] = PA[28:10] and PTEL[7:0] = flags.
        ! So PTEL = (PA & 0x1FFFFC00) | 0xE8
        mov     r5, r0
        mov.l   p_ppn_mask, r3         ! 0x1FFFFC00
        and     r3, r0                 ! r0 = PA & 0x1FFFFC00 (PPN field)
        or      #0xE8, r0              ! won't work for > 8-bit OR...
        ! or #0xE8,r0: sh2-elf or-imm works since 0xE8 fits in 8-bit sign-extended.
        .word   0x406E                 ! LDC r0,PTEL

        ! ASIDR = 0 (ASID field of PTEH was 0; ASIDR.ASID must match)
        mov     #0, r0
        .word   0x407E                 ! LDC r0,ASIDR

        ! LDTLB: write PTEH/PTEL/ASIDR into TLB
        .word   0x0038                 ! LDTLB

        ! Enable AT: MMUCR.AT = 1 (P4 address 0xFF000010)
        mov.l   p_mmucr, r0
        mov     #1, r1
        mov.l   r1, @r0

        ! Load from VA (= PA = r5 = &phys_buf) via P0 (TLB-translated)
        mov.l   @r5, r7
        cmp/eq  r4, r7
        mov     #2, r9
        bf      _fail_at1

        ! Disable AT before _done (avoid unmapped accesses)
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0

        bra     _done
        nop

_fail_at1:
        ! Disable AT first, then fall through to _fail
        mov.l   p_mmucr, r0
        mov     #0, r1
        mov.l   r1, @r0
        bra     _fail
        nop

        .align 2
p_testval:  .long 0xBEEFCAFE
p_physbuf:  .long phys_buf
p_vpn_mask: .long 0xFFFFF000
p_ppn_mask: .long 0xFFFFFC00
p_mmucr:    .long 0xFF000010

#else
        bra     _done
        nop
#endif

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

        .bss
        .balign 4
phys_buf: .space 4
