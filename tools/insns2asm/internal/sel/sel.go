// Package sel selects instruction subsets for phased SH MC emission.
package sel

import (
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/operand"
)

var oneASimpleClasses = map[operand.Class]bool{
	operand.GPR:        true,
	operand.R0Fixed:    true,
	operand.Imm:        true,
	operand.MemReg:     true,
	operand.MemPostInc: true,
	operand.MemPreDec:  true,
	operand.MemR0:      true,
	operand.MemR0GBR:   true,
}

// Is1aSimple reports whether an instruction is in the Phase-2b-1a subset:
// a single-word GP-integer instruction with only register / immediate /
// plain-indirect / indexed operands (no displacement, no two-word).
func Is1aSimple(in ir.Insn) bool {
	if len(in.Words) != 1 {
		return false
	}
	for _, o := range in.Operands {
		if !oneASimpleClasses[o.Class] {
			return false
		}
	}
	return true
}
