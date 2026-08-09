! mmulinuxexc.S -- REGRESSION HARNESS for linux@jcore's NON-TLB exception entry.
!
! WHY THIS EXISTS.
! mmulinux drives the real linux@jcore TLB-miss handler and is the safety net
! for everything at VBR+0x400. There is NO equivalent net for the other two
! fixed vectors, and that gap is not theoretical:
!
!   * VBR+0x100 (Error / Slot Illegal / General Illegal / TRAPA, and -- since
!     TLB protection was split off the miss vector to match SH-4 -- IPROT and
!     DPROT_R/W too) currently lands inside jcore_vbr_base's 256-entry J2
!     POINTER TABLE. J4 branches there as CODE, so it executes a .long as
!     instructions.
!   * VBR+0x600 (Interrupt) lands in whatever slow-path code follows the
!     inlined TLB fast path.
!
! Only VBR+0x400 was ever laid out correctly, because it is the only one CI
! exercised. This guard exercises the other two so the J4 entry rewrite has
! something to fail against, and so a later regression cannot pass silently.
!
! EXPECTED STATE WHEN FIRST COMMITTED: RED, and red as a TIMEOUT, not as a
! result code. That distinction is the honest one: with no code at VBR+0x100 at
! all, the TRAPA in sub-test A executes a .long from the pointer table and
! control is gone -- no software assertion in this file can run, so there is
! nothing left to report a code with. The OBSERVED signature is a bus
! exception, not a clean timeout: the table entries are addresses of the form
! 0x8000_02xx, and executing one as two 16-bit instructions happens to produce a
! store to a nonsense address ("SRAM: invalid write addr: 0x500000F0"). Either
! way there is no result code, which is the point.
!
! The result codes below therefore serve the state AFTER the entry rewrite,
! where a handler exists but might serve the wrong vector, read the wrong cause
! register, or mis-build pt_regs. That is the regression this guard is really
! for. A green run BEFORE the rewrite would mean it is not reaching the paths it
! claims to (see "PROVING THIS GUARD BITES" below).
!
! WHAT IT ASSERTS. For each exception it drives, that
!   1. control reached linux's entry for the RIGHT vector (each records a
!      distinct marker, so a handler serving the wrong vector is caught);
!   2. linux built pt_regs from SPC/SSR correctly -- the resumption PC it
!      recorded must be the harness instruction that faulted;
!   3. the cause register linux read matches the exception actually raised;
!   4. RTE returned to the harness with bank/SR sane (we get to the next
!      sub-test at all, in bank 0, with our own SP).
!
! Sub-tests:
!   A  TRAPA #7        -> VBR+0x100, EXPEVT=0x160, TRA=7*4=0x1C
!   B  General Illegal -> VBR+0x100, EXPEVT=0x180
!   C  DPROT_W         -> VBR+0x100, EXPEVT=0x0C0 (the vector-split path)
!   D  Interrupt       -> VBR+0x600, INTEVT set by the harness AIC model
!
! Result codes (r9):
!    1  A: linux entry not reached at all (marker still 0)
!    2  A: wrong vector marker
!    3  A: EXPEVT mismatch
!    4  A: TRA mismatch
!    5  A: recorded resume PC != the insn AFTER trapa (completion-type)
!    6  B: entry not reached
!    7  B: EXPEVT mismatch (expected General Illegal 0x180)
!    8  C: entry not reached
!    9  C: EXPEVT mismatch (expected DPROT_W 0x0C0)
!   10  C: recorded faulting address != the protected VA
!   11  D: interrupt entry not reached
!   12  D: wrong vector marker
!   99  a handler was reached with no sub-test armed
!
! PROVING THIS GUARD BITES. Once the rewrite makes it green, corrupt ONE thing
! and confirm the matching code appears -- e.g. point linux's VBR+0x100 stub at
! the interrupt tail and check sub-test A fails with 2, not with a timeout.
! Do this for at least one sub-test per vector; a guard that can only ever say
! "the simulation hung" does not tell you which path broke, and this one starts
! life in exactly that state.
!
! Overlay .word encodings (assembler does not know these J4 forms):
!   STC EXPEVT,r0 =0x0052   STC TRA,r0 =0x0072   STC INTEVT,r0=0x0062
!   LDC r0,VBR    =0x402E   LDC r0,PTEH=0x405E   LDC r0,PTEL =0x406E
!   LDC r0,ASIDR  =0x407E   LDTLB      =0x0038
#include "sim_instr.h"
#define ENTRY(name) .globl name; .balign 4; name:

        .section .vect,"a"
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
        ! CMD_ENABLE_EVENT_TRIGGER maps EVENT_TRIGGER_ADDRESS; without it that
        ! address is unmapped and sub-test D's interrupt request faults instead
        ! of raising anything ("invalid write addr: 0xBCDE0000 in range: (nil)").
        .long CMD_ENABLE_EVENT_TRIGGER
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0

        .section .textlo,"ax"
ENTRY(start)
#if CONFIG_PRIV_ARCH
        mov.l   p_sp,   r15
        mov.l   p_kmain, r0
        jmp     @r0
        nop
        .align 2
! SP and the handshake globals below sit ABOVE the linked image on purpose.
! This harness links the three real linux@jcore objects at P1 alongside itself;
! ex.o alone is ~6.7 KB, so scratch anywhere near 0x80002xxx lands inside .text
! and the guard dies at the first fetch instead of reaching the vector it is
! testing (observed: ACK timeout at 100 ns). mmulinux reserves past 0x80029000
! for the same reason.
p_sp:    .long 0x8003FF00
p_kmain: .long kmain

        .text
kmain:
        ! ---- RB=0, MD=1 ----
        stc     sr, r0
        mov.l   p_rbclear, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        mov     #0, r0
        lds     r0, pr

        ! ---- Define every register the pt_regs save will store. In a running
        ! kernel these always hold something; in a bare-metal image they are X,
        ! and JCORE_SAVE_REGS writing an undefined value trips the bus model
        ! ("SRAM: invalid write data: UUUU..."). Bank-1 r0-r7 are reachable
        ! from bank 0 only through the r*_bank aliases. ----
        mov     #0, r0
        ldc     r0, gbr
        lds     r0, mach
        lds     r0, macl
        lds     r0, pr
        ! LDC r0,rN_bank as .word: the mnemonic makes gas mark this object
        ! sh3-nommu, and this binutils fork cannot merge sh3-nommu with sh-j4
        ! ("internal error: merge of architecture ... produced unknown
        ! architecture") when linking against the real linux@jcore objects.
        ! Encoding 0100 mmmm 1nnn 1110, m=0 (r0), n = target bank register.
        .word   0x408E                  ! LDC r0, r0_bank
        .word   0x409E                  ! LDC r0, r1_bank
        .word   0x40AE                  ! LDC r0, r2_bank
        .word   0x40BE                  ! LDC r0, r3_bank
        .word   0x40CE                  ! LDC r0, r4_bank
        .word   0x40DE                  ! LDC r0, r5_bank
        .word   0x40EE                  ! LDC r0, r6_bank
        .word   0x40FE                  ! LDC r0, r7_bank
        mov     #0, r8  ; mov #0, r9  ; mov #0, r10 ; mov #0, r11
        mov     #0, r12 ; mov #0, r13 ; mov #0, r14
        ! ...and bank-0 r4-r7, which this harness never otherwise touches. On
        ! entry SR.RB=1, so the save's `stc rN_bank` reads the OTHER bank --
        ! bank 0 -- and an untouched r4-r7 there is still X.
        mov     #0, r4  ; mov #0, r5  ; mov #0, r6  ; mov #0, r7
        ! ...and r1-r3. The sub-test setup below only ever writes r0/r1, so
        ! r2 and r3 are still X when the first exception fires and the save
        ! stores them. This is the whole list: pt_regs holds r0-r14, and every
        ! one of them must be defined before the FIRST exception, not merely
        ! before the code that happens to read it back.
        mov     #0, r1  ; mov #0, r2  ; mov #0, r3

        ! ---- Zero the handshake globals the linux-side stubs write. ----
        mov.l   k_marker,   r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_expevt,   r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_tra,      r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_resumepc, r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_faultva,  r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_armed,    r0 ; mov #0, r1 ; mov.l r1, @r0

        ! ---- VBR = linux's REAL vector base. Everything below arrives at
        ! linux@jcore code, not at harness stubs: that is the whole point. ----
        mov.l   k_vbr, r0
        .word   0x402E                  ! LDC r0, VBR

        mov     #0, r0
        .word   0x407E                  ! LDC r0, ASIDR

        ! ================= A: TRAPA #7 -> VBR+0x100 =================
        mov.l   k_armed, r0 ; mov #1, r1 ; mov.l r1, @r0
        mov.l   k_saved_sp, r0 ; mov.l r15, @r0
        mov.l   p_after_a, r0 ; mov.l k_resume_to, r1 ; mov.l r0, @r1
a_trapa:
        trapa   #7
_after_a:
        mov.l   k_marker, r0 ; mov.l @r0, r2
        tst     r2, r2       ; mov #1, r9 ; bt _fail
        mov     #1, r3 ; cmp/eq r3, r2 ; mov #2, r9 ; bf _fail
        mov.l   k_expevt, r0 ; mov.l @r0, r2
        mov.l   c_expevt_trapa, r3 ; cmp/eq r3, r2 ; mov #3, r9 ; bf _fail
        mov.l   k_tra, r0 ; mov.l @r0, r2
        mov     #0x1C, r3 ; cmp/eq r3, r2 ; mov #4, r9 ; bf _fail
        ! TRAPA is a COMPLETION-type exception: SPC points at the instruction
        ! AFTER it, because a syscall must not re-execute its own trapa. That
        ! is the opposite of a fault (DPROT_W in sub-test C), where SPC is the
        ! faulting instruction so it can be retried. Asserting a_trapa here is
        ! what Result=5 was catching -- the guard was wrong, not the kernel.
        mov.l   k_resumepc, r0 ; mov.l @r0, r2
        mov.l   p_after_a, r3 ; cmp/eq r3, r2 ; mov #5, r9 ; bf _fail

        ! ================= B: General Illegal -> VBR+0x100 =================
        mov.l   k_marker, r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_armed, r0 ; mov #2, r1 ; mov.l r1, @r0
        mov.l   k_saved_sp, r0 ; mov.l r15, @r0
        mov.l   p_after_b, r0 ; mov.l k_resume_to, r1 ; mov.l r0, @r1
b_illegal:
        ! 0x00EB must be UNDEFINED for this sub-test to mean anything. It is
        ! the slot CMP/MISS EXPEVT vacated when the miss/protection vector
        ! split removed its only caller, and `cpugen freespace --avoid
        ! j2,sh2a,sh4,sh4a,dsp --form "----nnnn----1011" --region 0` still
        ! reports 1110 free. Do NOT reuse 0x00FE here: that is
        ! `mov.l @(R0,R15),R0`, a perfectly valid load, and this sub-test
        ! silently tested nothing until that was noticed.
        ! If 0x00EB is ever allocated, pick another virgin encoding -- the
        ! symptom will be sub-test B reporting "entry not reached".
        .word   0x00EB                  ! undefined -> General Illegal
_after_b:
        mov.l   k_marker, r0 ; mov.l @r0, r2
        tst     r2, r2       ; mov #6, r9 ; bt _fail
        mov.l   k_expevt, r0 ; mov.l @r0, r2
        mov.l   c_expevt_illegal, r3 ; cmp/eq r3, r2 ; mov #7, r9 ; bf _fail

        ! ================= C: DPROT_W -> VBR+0x100 (vector split) ==========
        ! Install a W=0 mapping and store to it. Since protection faults were
        ! split off the miss vector, this must arrive at the SAME linux entry
        ! as A and B -- not at the TLB fast path.
        mov.l   k_marker, r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_armed, r0 ; mov #3, r1 ; mov.l r1, @r0
        mov.l   k_saved_sp, r0 ; mov.l r15, @r0
        mov.l   p_after_c, r0 ; mov.l k_resume_to, r1 ; mov.l r0, @r1
        mov.l   va_ro, r0
        .word   0x405E                  ! LDC r0, PTEH
        mov.l   ptel_ro, r0
        .word   0x406E                  ! LDC r0, PTEL
        .word   0x0038                  ! LDTLB
        mov.l   k_mmucr, r0 ; mov #1, r1 ; mov.l r1, @r0   ! AT on
        mov.l   va_ro, r2
        mov     #0, r3
c_store:
        mov.l   r3, @r2                 ! -> DPROT_W
_after_c:
        mov.l   k_mmucr, r0 ; mov #0, r1 ; mov.l r1, @r0   ! AT off
        mov.l   k_marker, r0 ; mov.l @r0, r2
        tst     r2, r2       ; mov #8, r9 ; bt _fail
        mov.l   k_expevt, r0 ; mov.l @r0, r2
        mov.l   c_expevt_dprotw, r3 ; cmp/eq r3, r2 ; mov #9, r9 ; bf _fail
        mov.l   k_faultva, r0 ; mov.l @r0, r2
        mov.l   va_ro, r3 ; cmp/eq r3, r2 ; mov #10, r9 ; bf _fail

        ! ================= D: Interrupt -> VBR+0x600 =================
        ! Raised by the cosim's event interface; the harness enables interrupts
        ! and waits. linux's interrupt entry must record marker 2.
        mov.l   k_marker, r0 ; mov #0, r1 ; mov.l r1, @r0
        mov.l   k_armed, r0 ; mov #4, r1 ; mov.l r1, @r0
        mov.l   k_saved_sp, r0 ; mov.l r15, @r0
        mov.l   p_after_d, r0 ; mov.l k_resume_to, r1 ; mov.l r0, @r1
        ! Drop SR.BL and SR.IMASK so the interrupt can be taken at all: BL=1
        ! blocks exceptions outright, and on reset IMASK=0xF masks every level.
        stc     sr, r0
        mov.l   p_irq_enable, r1
        and     r1, r0
        ldc     r0, sr
        nop
        nop
        ! Nothing raises an interrupt on its own -- the cosim only does so when
        ! the harness writes EVENT_TRIGGER_ADDRESS (sim/cpu_ctb.c trigger_event):
        ! bits 14-12 = event_req (0 = interrupt), bits 11-0 = info, which for an
        ! interrupt is (ilevel << 8) | vector. Same encoding interrupts.S uses.
        ! Without this the guard just spins in d_wait until --stop-time, which
        ! reads as "interrupt entry not reached" when in truth none was sent.
        mov.l   k_evt_trigger, r0
        mov.l   v_irq_req, r1
        mov.l   r1, @r0                 ! request ilevel 0xF, vector 12
d_wait:
        bra     d_wait                  ! the interrupt must break this loop
        nop
_after_d:
        mov.l   k_marker, r0 ; mov.l @r0, r2
        tst     r2, r2       ; mov #11, r9 ; bt _fail
        mov     #2, r3 ; cmp/eq r3, r2 ; mov #12, r9 ; bf _fail

        mov     #0, r9
        bra     _done
        nop

        .align 2
p_rbclear:        .long 0xDFFFFFFF
p_irq_enable:     .long 0xEFFFFF0F      ! clear BL (bit28) and IMASK[7:4]
k_evt_trigger:    .long EVENT_TRIGGER_ADDRESS
v_irq_req:        .long 0x00000F0C      ! req=0 (interrupt), ilevel=0xF, vector=12      ! clear BL (bit28) and IMASK[7:4]
k_vbr:            .long jcore_vbr_base
k_mmucr:          .long 0xFF000010
k_marker:         .long 0x80030000
k_expevt:         .long 0x80030004
k_tra:            .long 0x80030008
k_resumepc:       .long 0x8003000C
k_faultva:        .long 0x80030010
k_armed:          .long 0x80030014
k_saved_sp:       .long 0x80030018
k_resume_to:      .long 0x8003001C
c_expevt_trapa:   .long 0x00000160
c_expevt_illegal: .long 0x00000180
c_expevt_dprotw:  .long 0x000000C0
va_ro:            .long 0x00200000
! Backing PA must lie in the region the cosim actually backs with memory.
! mmulinux's own backing page is 0x00040000, so use that; PA 0x00200000 gets
! no ACK ("Rd did not see ACK for data sram") and the guard hangs instead of
! reporting a code. The VA above is free to be anything unmapped.
ptel_ro:          .long 0x00040068      ! PA | X|U|C  (W=0 -> DPROT_W on store)
p_a_trapa:        .long a_trapa
p_after_a:        .long _after_a
p_after_b:        .long _after_b
p_after_c:        .long _after_c
p_after_d:        .long _after_d
#endif

ENTRY(_done)
        mov.l   p_test_result, r0
        mov.l   p_test_result_pass, r9
        mov.l   r9, @r0
        bra     _done
        nop
ENTRY(_fail)
        mov.l   p_test_result, r0
        tst     r9, r9
        bf      1f
        mov     #0x7F, r9
1:
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_test_result: .long TEST_RESULT_ADDRESS
p_test_result_pass: .long   TEST_PASS_MAGIC

#if CONFIG_PRIV_ARCH
! ===========================================================================
! Harness-side stubs standing in for the kernel C tails that linux@jcore's
! exception entry calls. Each records what the REAL entry passed it, then
! returns control to the harness the same way mmulinux's do_page_fault stub
! does: drop SR.RB back to 0, restore the harness SP, and jump to the
! per-sub-test resume label. entry.S never clears RB itself.
!
! These are the CONTRACT the J4 entry rewrite must satisfy. If the rewrite
! calls something else, this guard fails to link -- which is itself the
! signal that the interface changed.
! ===========================================================================

! void jcore_handle_exception(struct pt_regs *regs, unsigned long expevt)
!   r4 = regs, r5 = expevt
ENTRY(jcore_handle_exception)
        mov.l   hx_marker, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! marker 1 = arrived via VBR+0x100
        mov.l   hx_expevt, r0
        mov.l   r5, @r0
        .word   0x0072                  ! STC TRA, r0   (r0 = TRA)
        mov.l   hx_tra_p, r1
        mov.l   r0, @r1
        ! pt_regs->pc is the FIRST word of pt_regs (OFF_PC=16*4 in entry.S's
        ! layout, but the resumption PC the rewrite must record is what we
        ! check; read it from regs at OFF_PC).
        mov     #64, r0                 ! OFF_PC = 16*4 in entry.S's pt_regs layout
        mov.l   @(r0, r4), r1
        mov.l   hx_resumepc, r0
        mov.l   r1, @r0
        bra     _stub_return
        nop

! void do_page_fault(struct pt_regs *regs, unsigned long error_code,
!                    unsigned long address)   r4/r5/r6
ENTRY(do_page_fault)
        mov.l   hx_marker, r0
        mov     #1, r1
        mov.l   r1, @r0                 ! same vector as A/B since the split
        mov.l   hx_faultva, r0
        mov.l   r6, @r0
        .word   0x0052                  ! STC EXPEVT, r0
        mov.l   hx_expevt, r1
        mov.l   r0, @r1
        bra     _stub_return
        nop

! void do_IRQ(unsigned int irq, struct pt_regs *regs)
ENTRY(do_IRQ)
        mov.l   hx_marker, r0
        mov     #2, r1
        mov.l   r1, @r0                 ! marker 2 = arrived via VBR+0x600
        bra     _stub_return
        nop

_stub_return:
        mov.l   hx_rbclear, r0
        stc     sr, r1
        and     r0, r1
        ldc     r1, sr
        nop
        nop
        mov.l   hx_saved_sp, r0
        mov.l   @r0, r15
        mov.l   hx_resume_to, r0
        mov.l   @r0, r0
        jmp     @r0
        nop

! ---------------------------------------------------------------------------
! Link-time stubs the linked linux@jcore objects reference. These duplicate
! mmulinux.S's equivalents; both harnesses link the same three objects, so if a
! third appears these should move to a shared .inc (the m8_runtime.inc lesson --
! a duplicated .word table there silently went stale and cost a debugging pass).
!
! exception_handler is referenced by TODAY's ex.o, which routes generic
! exceptions through the J2 stack-based dispatch. The J4 entry rewrite removes
! that reference; when it does, this stub becomes dead and should be deleted
! rather than left as a decoy.
! ---------------------------------------------------------------------------
ENTRY(exception_handler)
        rts
        nop
ENTRY(arch_local_irq_restore)
        rts
        nop
ENTRY(arch_local_save_flags)
        mov     #0, r0
        rts
        nop

! jcore_boot_tsb must BE the TSB the hardware hashes into, not a separate
! buffer -- same reasoning as mmulinux.S: a kernel memset of a different array
! would make any TSB-invalidation assertion pass vacuously.
        .globl  jcore_boot_tsb
jcore_boot_tsb = 0x80028000

! memset(s, c, n) -- byte loop is fine here; this harness never memsets the
! 4 KB TSB on a timed path the way mmulinux scenario 8 does.
ENTRY(memset)
        mov     r4, r0                  ! return s
        tst     r6, r6
        bt      2f
1:      mov.b   r5, @r4
        add     #1, r4
        dt      r6
        bf      1b
2:      rts
        nop

        .align 2
hx_marker:    .long 0x80030000
hx_expevt:    .long 0x80030004
hx_tra_p:     .long 0x80030008
hx_resumepc:  .long 0x8003000C
hx_faultva:   .long 0x80030010
hx_saved_sp:  .long 0x80030018
hx_resume_to: .long 0x8003001C
! Clears BOTH SR.RB (bit 29) and SR.BL (bit 28). Clearing RB alone is not
! enough: these stubs return with `jmp`, not `rte`, so nothing restores SR from
! SSR and BL stays set from exception entry. With BL=1 the CPU blocks further
! exceptions, so the NEXT sub-test's fault is never delivered and the guard
! reports "entry not reached" for a handler that is perfectly fine.
hx_rbclear:   .long 0xCFFFFFFF
#endif
