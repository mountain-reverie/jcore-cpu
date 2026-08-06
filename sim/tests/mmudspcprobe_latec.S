! mmudspcprobe_latec.S -- CAS.L Rm,Rn,@R0 variant of mmudspcprobe_late.S.
!
! Same harness, same tripwires, same composite encoding, same non-vacuity
! check; the ONLY difference is the delay-slot instruction. See
! mmudspcprobe_late.S's header for what this measures and why every
! late-access form needs its own file instead of an argument by analogy.
!
! Defect 7 regression lock for the LOCKED-RMW form: CAS.L's read is slot 1.
! Measured Result=65793 (0x00010101) pre-fix, PASS after. The pre-fix run also
! emitted a "Rd did not see ACK for data sram" warning; do NOT read that as a
! bus-lock symptom -- that warning turned out to be an unreliable indicator
! elsewhere in this suite (see the CAS.L retraction in sim/mmu_sim.sh), and the
! composite is what this guard actually asserts on.
#define DSLOT_FORM FORM_CASL
#include "mmudspcprobe_late.S"
