! mmudspcprobe_latem.S -- MAC.L @Rm+,@Rn+ variant of mmudspcprobe_late.S.
!
! The dual-pointer late-access form: slot 0 reads @Rn (pre-warmed), slot 1
! reads @Rm (cold) -- so the fault lands on the LATE access, the arm under
! test. Verified on the two BASES rather than a destination register; MAC has
! no GPR destination. See mmudspcprobe_late.S's FORM SELECTION block.
#define DSLOT_FORM FORM_MACL
#include "mmudspcprobe_late.S"
