package microcode

import (
	"fmt"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// WritesPC reports whether any of the instruction's slots asserts wrpc_z, i.e.
// whether it writes PC through the dedicated write-PC control. Measured: this is
// exactly BRA/BRAF/BSR/BSRF/JMP/JSR/RTS/RTE and TRAPA, on both the J2 and J4
// profiles — but NOT the conditional branches, which redirect via zbus="T(PC)"
// + if_addy="ZBUS".
func WritesPC(in spec.Instr) (bool, error) {
	for _, slot := range in.Slots {
		if len(slot) == 0 {
			continue // trailing empty slot = cycle terminator
		}
		am, err := AssignSlot(in, slot)
		if err != nil {
			return false, fmt.Errorf("%s: %w", in.Name, err)
		}
		if am[SigWrpcZ] == "1" {
			return true, nil
		}
	}
	return false, nil
}

// IsSlotIllegal reports whether the instruction must raise a slot illegal
// instruction exception when placed in a branch delay slot, on the profile the
// instruction was loaded from (spec.Instr.SlotIllegal is variant-dependent —
// the sh4 overlay patches it onto the PC-relative fetches).
//
// This is THE definition of the set: it drives both check_illegal_delay_slot in
// the generated decoder (model.BuildBody) and the per-variant `.exceptions`
// annotation in docs/insns.json (internal/insns). Keep it single-sourced —
// a second copy of this rule is how the conditional branches went missing.
func IsSlotIllegal(in spec.Instr) (bool, error) {
	if in.SlotIllegal {
		return true, nil
	}
	return WritesPC(in)
}
