// Package sel selects instruction subsets for phased SH MC emission.
package sel

import (
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/operand"
)

var gpIntegerGroups = map[string]bool{
	"Data Transfer Instructions":        true,
	"Arithmetic Operation Instructions": true,
	"Logic Operation Instructions":      true,
	"Shift Instructions":                true,
	"Bit Manipulation Instructions":     true,
}

// oneACleanOperand reports whether an operand class is supported by the current
// SH MC target (1a register/immediate + 1b-i register-only memory). Scaled
// displacement (MemDisp/MemPC/MemGBR) and the non-GP classes remain unsupported.
func oneACleanOperand(o operand.Operand) bool {
	switch o.Class {
	case operand.GPR, operand.Imm, operand.R0Fixed,
		operand.MemReg, operand.MemPostInc, operand.MemPreDec,
		operand.MemR0, operand.MemR0GBR:
		return true
	}
	return false
}

// Is1aSimple reports whether an instruction is in the supported subset:
// a single-word GP-integer instruction with supported single-word GP-integer
// operands (registers, immediates, register-only memory classes with any Fixed value).
func Is1aSimple(in ir.Insn) bool {
	if !gpIntegerGroups[in.Group] {
		return false
	}
	if len(in.Words) != 1 {
		return false
	}
	for _, o := range in.Operands {
		if !oneACleanOperand(o) {
			return false
		}
	}
	return true
}
