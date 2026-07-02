! SMP cache-coherency repro for cpu_dualcore_tb.
!
! Both cores boot from the reset vector at address 0:
!   word0 = initial PC (_start), word1 = initial SP.
! Both cores start at _start and diverge by reading the cpuid intercept
! at 0xABCD0600 (cpu0 reads 0, cpu1 reads 1).
!
! cpu1 computes seed*136 -> *result, then sets *finish=1.
! cpu0 primes+polls the cached *finish sentinel and reports via LED:
!   0x5A = OK  (observed cpu1's write through cache coherency)
!   0x7A = FAIL (premature/timeout exit)
!
! .ifdef HAZARD selects the buggy compound poll loop (Task 4).

    .section .vect, "ax"
    .align 2
    .global _vector_table
_vector_table:
    .long   _start          ! reset PC
    .long   0x0000A000       ! reset SP (cpu0 default; each role sets its own r15)

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

! ---- cpu1: compute seed*136, store to result, set finish=1 ----
cpu1_role:
    mov.l   sp1_top, r15
    mov.l   seed_addr, r2
    mov.l   @r2, r3          ! r3 = seed (7)
    mov     #136, r4
    mulu.w  r4, r3
    sts     macl, r5         ! r5 = seed*136
    mov.l   result_addr, r6
    mov.l   r5, @r6          ! *result = seed*136
    mov.l   finish_addr, r7
    mov     #1, r0
    mov.l   r0, @r7          ! *finish = 1  (snoop-invalidates cpu0's cached line)
1:  bra     1b
    nop

! ---- cpu0: seed the mailbox, poll *finish, report via LED ----
cpu0_role:
    mov.l   sp0_top, r15
    mov.l   finish_addr, r0
    mov     #0, r1
    mov.l   r1, @r0          ! *finish = 0
    mov.l   seed_addr, r0
    mov     #7, r1
    mov.l   r1, @r0          ! *seed = 7
    ! prime cpu0's cache line for *finish (read it once so it is cached as 0)
    mov.l   finish_addr, r3
    mov.l   @r3, r1

.ifdef HAZARD
    ! BUGGY shape: compound while(*finish==0 && spins<LIMIT) spins++;
    ! mirrors gcc -Os codegen: cmp/eq; mov.l @; bt.s; tst(delay slot); bt
    mov     #0, r2           ! spins
    mov.l   limit_k, r7      ! LIMIT
poll_bug:
    cmp/eq  r7, r2           ! T=(spins==LIMIT)
    mov.l   @r3, r1          ! r1 = *finish
    bt.s    poll_done        ! DELAY SLOT
    tst     r1, r1           ! delay slot: T=(*finish==0)  [T-setter -> HAZARD]
    bt      poll_cont        ! *finish==0 -> keep looping
    bra     poll_done        ! *finish!=0 -> exit (done)
    nop
poll_cont:
    bra     poll_bug
    add     #1, r2           ! spins++
poll_done:
.else
    ! FIXED shape: bounded counter, finish-check NOT in a delay slot
    mov.l   limit_k, r2      ! spins = LIMIT
poll_fix:
    mov.l   @r3, r1          ! r1 = *finish
    tst     r1, r1
    bf      poll_done        ! *finish!=0 -> done
    dt      r2               ! spins--
    bf      poll_fix         ! keep looping while spins!=0
poll_done:
.endif
    ! report: LED = 0x5A if *finish observed set (OK), else 0x7A (FAIL/premature)
    mov.l   @r3, r1
    tst     r1, r1
    mov.l   led_addr, r0
    bt      report_fail
    mov     #0x5A, r1        ! saw finish set -> OK
    mov.l   r1, @r0
    bra     hang
    nop
report_fail:
    mov     #0x7A, r1        ! premature exit -> FAIL
    mov.l   r1, @r0
hang:
    bra     hang
    nop

    .align 4
cpuid_addr:  .long 0xABCD0600
led_addr:    .long 0xABCD0000
finish_addr: .long 0x00008100
seed_addr:   .long 0x00008104
result_addr: .long 0x00008108
sp0_top:     .long 0x0000A000
sp1_top:     .long 0x0000C000
limit_k:     .long 2000
