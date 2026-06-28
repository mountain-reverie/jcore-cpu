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

// oneACleanOperand reports whether an operand is clean for Phase-2b-1a
// (literal-text addressing): registers, immediates, bare R0, and variable-base
// indirect forms only. Fixed-register memory, pre-decrement, and indexed forms
// are deferred to Phase-2b-1b.
func oneACleanOperand(o operand.Operand) bool {
	switch o.Class {
	case operand.GPR, operand.Imm, operand.R0Fixed:
		return true
	case operand.MemReg, operand.MemPostInc:
		// variable-base only; fixed-register memory (@R0, @R15+) -> 1b
		return o.Fixed == ""
	}
	// MemPreDec, MemR0, MemR0GBR, and everything else -> deferred to 1b
	return false
}

// Is1aSimple reports whether an instruction is in the Phase-2b-1a subset:
// a single-word GP-integer instruction with only register / immediate /
// plain-indirect / post-increment operands (no displacement, no two-word,
// no fixed-register memory, no pre-decrement, no indexed).
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
