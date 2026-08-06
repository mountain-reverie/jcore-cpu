! mmudspcprobe_latec.S -- CAS.L Rm,Rn,@R0 variant of mmudspcprobe_late.S.
!
! Same harness, same tripwires, same composite encoding, same non-vacuity
! check; the ONLY difference is the delay-slot instruction. See
! mmudspcprobe_late.S's header for what this measures and why every
! late-access form needs its own file instead of an argument by analogy.
!
! Defect 7 regression lock for the LOCKED-RMW form: CAS.L's read is slot 1.
! Pre-fix this form did not merely mis-restart, it hung the bus mid-lock
! ("Rd did not see ACK for data sram").
#define DSLOT_FORM FORM_CASL
#include "mmudspcprobe_late.S"
