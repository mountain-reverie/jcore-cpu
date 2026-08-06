! mmudspcprobe_latew.S -- MOV.W @Rm+,Rn variant of mmudspcprobe_late.S.
!
! Same harness, same tripwires, same composite encoding, same non-vacuity
! check; the ONLY difference is the delay-slot instruction. See
! mmudspcprobe_late.S's header for what this measures and why every
! late-access form needs its own file instead of an argument by analogy.
!
! Defect 7 regression lock for MOV.W @Rm+,Rn (access launches in slot 1).
#define DSLOT_FORM FORM_MOVW
#include "mmudspcprobe_late.S"
