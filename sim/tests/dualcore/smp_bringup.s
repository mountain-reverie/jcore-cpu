! SMP bringup guard for cpu_dualcore_tb: proves (a) spin-table secondary
! release via a software-supplied entry PC, and (b) IPI delivery through the
! real work.icache_modereg entity's int0/int1 pulse (bit 28), auto-clearing.
!
! Mirrors the smp-j2.c contract:
!   release: writel(entry, 0x8000); writel(1, 0xabcd0640)
!   ipi:     writel(readl(ipi_base+cpu) | (1<<28), ipi_base+cpu)
! Here ipi_base = 0xABCD00C0 (word0/cpu0 @ 0xC0, word1/cpu1 @ 0xC4), the
! address window decoded to work.icache_modereg in cpu_dualcore_tb.vhd.
!
! cpu0 (cpuid==0):
!   1. writes the address of cpu1_entry to the release mailbox (0x8000)
!   2. writes 1 to the release-enable register (0xabcd0640)
!   3. polls a scratch sentinel until cpu1 (running from the PC cpu0 supplied,
!      not a hardcoded address) writes RELEASE_MAGIC there
!   4. sends an IPI to cpu1 (bit 28 @ 0xABCD00C4)
!   5. polls until cpu1's ISR sets ipi_hits to 1 (bounded), then checks it is
!      still exactly 1 after cpu1 continues running for a while (proves the
!      int1 pulse auto-cleared -- if it hadn't, cpu1 would keep re-entering
!      the ISR and ipi_hits would climb past 1)
!   6. reports PASS/FAIL to TEST_RESULT_ADDRESS (0xBCDE0010): r9=0 pass
!
! cpu1 (cpuid==1):
!   parks in a bounded spin waiting for the release enable, then jumps to
!   the PC cpu0 wrote to the mailbox (cpu1_entry below, but reached only via
!   that indirection -- proving the real entry-PC path, not a fixed address).
!   Installs its own VBR/vector table, then spins waiting for the IPI.

    .section .vect, "ax"
    .align 2
    .long   _start          ! word0: reset PC
    .long   0x0000A000      ! word1: reset SP
    .long   _start           ! word2 (unused slot, mirrors excguard.S layout)
    .long   0x0000A000       ! word3
    .rept 60
    .long   0
    .endr
    .long   0x3321AACC       ! SIM_INSTR_MAGIC
    .long   _sim_instr_end
    .long   _done
    .long   _fail_loop
    .long   3                ! CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

    .section .text
    .align 2
    .global _start
_start:
    mov.l   cpuid_addr, r0
    mov.l   @r0, r1          ! r1 = cpu id (0 or 1)  [cpuid intercept]
    tst     r1, r1
    bt      cpu0_role        ! id==0 -> cpu0
    bra     cpu1_role
    nop

! =================== cpu1: parked, then released, then IPI'd ===================
cpu1_role:
    mov.l   sp1_top, r15

    ! install our own vector table so we can field the IPI at vec 0x14
    mov.l   vbr_table_addr, r0
    ldc     r0, vbr

    ! SR.IMASK resets to 0xF (all interrupts masked, like real SH hardware) --
    ! clear ONLY the IMASK nibble (bits 7:4) so our IPI (lvl=1) can be taken;
    ! must NOT touch MD/RB/BL (bits 30/29/28) via a blind ldc #0,sr, since RB
    ! selects the live R0-R7 register bank and flipping it would swap in the
    ! (uninitialized) other bank out from under this running code.
    stc     sr, r0
    mov.l   sr_imask_clear_k, r1
    and     r1, r0
    ldc     r0, sr

    ! init scratch state
    mov.l   ipi_hits_addr, r0
    mov     #0, r1
    mov.l   r1, @r0          ! ipi_hits = 0

    ! wait (bounded) for the release-enable flag
    mov.l   release_en_addr, r3
    mov.l   wait_limit_k, r2
wait_release:
    mov.l   @r3, r1
    tst     r1, r1
    bf      released         ! enable != 0 -> go
    dt      r2
    bf      wait_release
    ! timed out waiting for release -> fail
    mov.l   led_addr, r0
    mov     #0x11, r1
    mov.l   r1, @r0
    bra     cpu1_fail
    nop

released:
    mov.l   led_addr, r0
    mov     #0x12, r1
    mov.l   r1, @r0
    ! jump through the mailbox-supplied entry PC (NOT a hardcoded address)
    mov.l   release_pc_addr, r0
    mov.l   @r0, r1
    jmp     @r1
    nop

! reached only by indirect jump through the cpu0-supplied entry PC
    .align 2
    .global cpu1_entry
cpu1_entry:
    mov.l   led_addr, r0
    mov     #0x13, r1
    mov.l   r1, @r0
    mov.l   release_magic_k, r1
    mov.l   release_sentinel_addr, r0
    mov.l   r1, @r0          ! prove we executed the supplied PC

    ! now just wait (bounded) for the IPI to land + be handled once
    mov.l   ipi_wait_limit_k, r2
ipi_wait:
    mov.l   ipi_hits_addr, r0
    mov.l   @r0, r1
    tst     r1, r1
    bf      ipi_seen         ! hits != 0 -> ISR ran at least once
    dt      r2
    bf      ipi_wait
    bra     cpu1_fail
    nop

ipi_seen:
    ! give the (already-cleared) pulse plenty of cycles to misbehave if it
    ! didn't actually auto-clear (would cause repeated ISR entry)
    mov.l   settle_k, r2
settle:
    dt      r2
    bf      settle
1:  bra     1b
    nop

cpu1_fail:
    mov.l   ipi_hits_addr, r0
    mov     #0xFF, r1
    mov.l   r1, @r0          ! poison value so cpu0's checks fail loudly
1:  bra     1b
    nop

! IPI ISR: vec 0x14 (VBR + 0x50)
    .align 2
cpu1_isr:
    mov.l   ipi_hits_addr, r0
    mov.l   @r0, r1
    add     #1, r1
    mov.l   r1, @r0          ! ipi_hits++
    rte
    nop

! =================== cpu0: spin-table release + IPI send + verify ===================
cpu0_role:
    mov.l   sp0_top, r15

    ! init mailbox/sentinels
    mov.l   release_en_addr, r0
    mov     #0, r1
    mov.l   r1, @r0          ! release_en = 0
    mov.l   release_sentinel_addr, r0
    mov.l   r1, @r0          ! sentinel = 0
    mov.l   ipi_hits_addr, r0
    mov.l   r1, @r0          ! ipi_hits = 0 (cpu0's own view before cpu1 inits it too)

    ! 1) writel(entry, 0x8000)
    mov.l   cpu1_entry_addr, r1
    mov.l   release_pc_addr, r0
    mov.l   r1, @r0

    ! 2) writel(1, 0xabcd0640)
    mov.l   release_en_addr, r0
    mov     #1, r1
    mov.l   r1, @r0

    ! 3) poll for cpu1's sentinel write (proves the supplied PC executed)
    mov.l   release_sentinel_addr, r3
    mov.l   wait_limit_k, r2
poll_sentinel:
    mov.l   @r3, r1
    mov.l   release_magic_k, r4
    cmp/eq  r4, r1
    bt      sentinel_seen
    dt      r2
    bf      poll_sentinel
    mov.l   led_addr, r0
    mov     #1, r1
    mov.l   r1, @r0
    bra     cpu0_fail
    nop

sentinel_seen:
    ! 4) send IPI to cpu1: word1 (0xABCD00C4) |= bit28
    mov.l   ipi_bit28_k, r1
    mov.l   ipi1_addr, r0
    mov.l   r1, @r0

    ! read back the register: bits 31:2 are a fixed pattern + dc1_en/ic1_en,
    ! bit 28 is not part of the read mux at all (icache_modereg never exposes
    ! it), so any read already shows it low -- combined with the ipi_hits
    ! single-shot check below this still proves the pulse behaved as a pulse.
    mov.l   @r0, r5
    mov.l   bit28_mask, r6
    and     r6, r5
    mov.l   readback_ok_addr, r0
    mov.l   r5, @r0          ! store observed (masked) bit 28 for the report

    ! 5) poll for cpu1's ISR hit, then make sure it stays at exactly 1
    mov.l   ipi_hits_addr, r3
    mov.l   wait_limit_k, r2
poll_hit:
    mov.l   @r3, r1
    tst     r1, r1
    bf      hit_seen
    dt      r2
    bf      poll_hit
    mov.l   led_addr, r0
    mov     #2, r1
    mov.l   r1, @r0
    bra     cpu0_fail
    nop

hit_seen:
    mov     #1, r7
    cmp/eq  r7, r1
    bt      hit_ok
    mov.l   led_addr, r0
    mov     #3, r1
    mov.l   r1, @r0
    bra     cpu0_fail
    nop
hit_ok:

    ! let cpu1 run further; if int1 had NOT auto-cleared, cpu1 would keep
    ! re-trapping and hits would climb above 1 well before this settles
    mov.l   settle_k, r2
settle0:
    dt      r2
    bf      settle0

    mov.l   @r3, r1          ! re-read hits
    cmp/eq  r7, r1
    bt      still_ok
    mov.l   led_addr, r0
    mov     #4, r1
    mov.l   r1, @r0
    bra     cpu0_fail
    nop
still_ok:

    ! all good
    mov.l   led_addr, r0
    mov     #0x5A, r1
    mov.l   r1, @r0
    mov.l   p_test_result, r0
    mov     #0, r9
    mov.l   r9, @r0
_done:
    bra     _done
    nop

cpu0_fail:
    mov.l   p_test_result, r0
    mov     #1, r9
    mov.l   r9, @r0
_fail_loop:
    bra     _fail_loop
    nop

    .align 4
cpuid_addr:            .long 0xABCD0600
p_test_result:         .long 0xBCDE0010
led_addr:              .long 0xABCD0000

release_pc_addr:       .long 0x00008000   ! spin-table entry-PC mailbox
release_en_addr:       .long 0xABCD0640   ! spin-table release-enable
release_sentinel_addr: .long 0x00008010   ! cpu1 writes this to prove it ran
release_magic_k:       .long 0xC1C1C1C1
ipi_hits_addr:         .long 0x00008014   ! ISR hit counter
ipi1_addr:             .long 0xABCD00C4   ! icache_modereg word1 (int1)
ipi_bit28_k:           .long 0x10000000
bit28_mask:            .long 0x10000000
readback_ok_addr:      .long 0x00008018

sr_imask_clear_k:      .long 0xFFFFFF0F   ! clears SR bits 7:4 (IMASK) only
cpu1_entry_addr:       .long cpu1_entry
vbr_table_addr:        .long vbr_table
sp0_top:               .long 0x0000A000
sp1_top:               .long 0x0000C000
wait_limit_k:          .long 3000
ipi_wait_limit_k:      .long 3000
settle_k:              .long 500

    .align 2
    .global vbr_table
vbr_table:
    .rept 0x14
    .long cpu1_fail            ! any unexpected exception -> fail loudly
    .endr
    .long cpu1_isr              ! vec 0x14: IPI
    .rept (0x40 - 0x15)
    .long cpu1_fail
    .endr
