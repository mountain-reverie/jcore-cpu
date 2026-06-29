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
//
// Fixed-register memory operands @R0/@-R15/@R15+ (MemReg/MemPreDec/MemPostInc
// with Fixed != "") are now supported via constrained operand classes
// (MemR0Fixed/MemDecR15/MemIncR15). @(R0,GBR) (MemR0GBR) is kept as a literal.
func oneACleanOperand(o operand.Operand) bool {
	switch o.Class {
	case operand.GPR, operand.Imm, operand.R0Fixed, operand.MemR0, operand.MemR0GBR, operand.MemDisp, operand.MemGBR, operand.MemPC:
		return true
	case operand.MemReg, operand.MemPostInc, operand.MemPreDec:
		return true
	}
	return false
}

// Is1aSimple reports whether an instruction is in the supported subset:
// a single- or two-word GP-integer instruction with supported GP-integer
// operands (registers, immediates, register-only memory classes with any Fixed value).
func Is1aSimple(in ir.Insn) bool {
	if !gpIntegerGroups[in.Group] {
		return false
	}
	if len(in.Words) > 2 {
		return false
	}
	for _, o := range in.Operands {
		if !oneACleanOperand(o) {
			return false
		}
	}
	return true
}
