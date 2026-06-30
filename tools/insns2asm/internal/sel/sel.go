// Package sel selects instruction subsets for phased SH MC emission.
package sel

import (
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/operand"
)

var fpGroups = map[string]bool{
	"32 Bit Floating-Point Data Transfer Instructions (FPSCR.SZ = 0)": true,
	"Floating-Point Single-Precision Instructions (FPSCR.PR = 0)":     true,
	"Floating-Point Control Instructions":                              true,
	"64 Bit Floating-Point Data Transfer Instructions (FPSCR.SZ = 1)": true,
	"Floating-Point Double-Precision Instructions (FPSCR.PR = 1)":     true,
}

var gpIntegerGroups = map[string]bool{
	"Data Transfer Instructions":        true,
	"Arithmetic Operation Instructions": true,
	"Logic Operation Instructions":      true,
	"Shift Instructions":                true,
	"Bit Manipulation Instructions":     true,
	"Branch Instructions":               true,
}

// systemRegAllow is the set of special registers (FixedReg.Fixed) accepted in
// System Control scope. Out-of-scope registers (SGR, DBR, PTEH, …) are rejected.
var systemRegAllow = map[string]bool{
	"SR": true, "GBR": true, "VBR": true, "SSR": true, "SPC": true,
	"TBR": true, "MACH": true, "MACL": true, "PR": true,
	"SGR": true, "DBR": true,
}

// sysControlMnemonics are System Control insns accepted by mnemonic (no special
// register to allow-list, or fixed operand shapes).
var sysControlMnemonics = map[string]bool{
	"nop": true, "clrt": true, "sett": true, "clrmac": true, "sleep": true,
	"rte": true, "bgnd": true, "trapa": true,
	"ldbank": true, "stbank": true, "pref": true, "resbank": true,
	"clrs": true, "sets": true, "synco": true, "ldtbl": true,
	"icbi": true, "ocbi": true, "ocbp": true, "ocbwb": true,
	"prefi": true, "movca.l": true,
}

// sysRegMoveMnemonics are the system/banked register transfer mnemonics.
var sysRegMoveMnemonics = map[string]bool{
	"ldc": true, "stc": true, "ldc.l": true, "stc.l": true,
	"lds": true, "sts": true, "lds.l": true, "sts.l": true,
}

// sysOperandClean reports whether an operand is acceptable in a System Control
// register-move insn: registers/immediates/memory shapes, banked registers, and
// only allow-listed special registers.
func sysOperandClean(o operand.Operand) bool {
	switch o.Class {
	case operand.GPR, operand.Imm, operand.R0Fixed, operand.BankReg,
		operand.MemReg, operand.MemPostInc, operand.MemPreDec:
		return true
	case operand.FixedReg:
		return systemRegAllow[o.Fixed]
	}
	return false
}

// systemControlSelected reports whether a System Control insn is in scope.
func systemControlSelected(in ir.Insn) bool {
	if in.Group != "System Control Instructions" {
		return false
	}
	if !sysControlMnemonics[in.Mnemonic] && !sysRegMoveMnemonics[in.Mnemonic] {
		return false
	}
	for _, o := range in.Operands {
		if !sysOperandClean(o) {
			return false
		}
	}
	return true
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
	case operand.BranchDisp, operand.MemTBRDisp:
		return true
	}
	return false
}

// fpSelected reports whether an instruction belongs to the SH floating-point
// ISA supported by the SH MC target: single- and double-precision plus the
// vector/matrix forms (fipr/ftrv). An instruction is selected when its group is
// an FP group and every operand is a modelled FP/GPR/immediate/memory class.
func fpSelected(in ir.Insn) bool {
	if !fpGroups[in.Group] {
		return false
	}
	for _, o := range in.Operands {
		switch o.Class {
		case operand.GPR, operand.Imm, operand.FReg, operand.FR0Fixed,
			operand.DReg, operand.XReg, operand.FVReg,
			operand.MemReg, operand.MemPostInc, operand.MemPreDec, operand.MemR0,
			operand.MemDisp:
			// ok
		case operand.FixedReg:
			if o.Fixed != "FPUL" && o.Fixed != "FPSCR" && o.Fixed != "XMTRX" {
				return false
			}
		default:
			return false
		}
	}
	return true
}

// Is1aSimple reports whether an instruction is in the supported subset:
// a single- or two-word GP-integer instruction with supported GP-integer
// operands (registers, immediates, register-only memory classes with any Fixed value).
func Is1aSimple(in ir.Insn) bool {
	if len(in.Words) > 2 {
		return false
	}
	if gpIntegerGroups[in.Group] {
		for _, o := range in.Operands {
			if !oneACleanOperand(o) {
				return false
			}
		}
		return true
	}
	if fpSelected(in) {
		return true
	}
	return systemControlSelected(in)
}
