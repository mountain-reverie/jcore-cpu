// Package gas emits a minimal binutils sh-opc.h delta containing only the
// J-core-only instructions (parity mode: SH instructions are assumed present
// upstream and skipped).
package gas

import (
	"fmt"
	"strings"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/operand"
)

// EmitDelta renders the J-core-only instructions as sh_table entries.
func EmitDelta(insns []ir.Insn) (string, error) {
	var b strings.Builder
	for _, in := range insns {
		if !in.Arch.IsJCoreOnly() {
			continue
		}
		args := make([]string, 0, len(in.Operands)+1)
		for _, o := range in.Operands {
			code, err := argCode(o)
			if err != nil {
				return "", fmt.Errorf("gas: %s: %w", in.Mnemonic, err)
			}
			args = append(args, code)
		}
		args = append(args, "0") // sh_table arg arrays are zero-terminated
		nib, err := nibbles(in)
		if err != nil {
			return "", fmt.Errorf("gas: %s: %w", in.Mnemonic, err)
		}
		fmt.Fprintf(&b, "{%q,{%s},{%s},%s},\n",
			in.Mnemonic, strings.Join(args, ","), nib, in.Arch.GASMask())
	}
	return b.String(), nil
}

func argCode(o operand.Operand) (string, error) {
	switch o.Class {
	case operand.GPR:
		if o.Letter == 'n' {
			return "A_REG_N", nil
		}
		return "A_REG_M", nil
	case operand.Imm:
		return "A_IMM", nil
	case operand.MemReg:
		if o.Letter == 'n' {
			return "A_IND_N", nil
		}
		return "A_IND_M", nil
	case operand.MemPostInc:
		if o.Letter == 'n' {
			return "A_INC_N", nil
		}
		return "A_INC_M", nil
	case operand.MemPreDec:
		if o.Letter == 'n' {
			return "A_DEC_N", nil
		}
		return "A_DEC_M", nil
	case operand.MemDisp:
		if o.Letter == 'd' && hasLetter(o, 'n') {
			return "A_DISP_REG_N", nil
		}
		return "A_DISP_REG_M", nil
	case operand.MemR0:
		if o.Letter == 'n' {
			return "A_IND_R0_REG_N", nil
		}
		return "A_IND_R0_REG_M", nil
	case operand.R0Fixed:
		return "A_R0", nil
	case operand.FixedReg:
		return "A_" + o.Fixed, nil
	}
	return "", fmt.Errorf("gas: unhandled operand class %v (token %q)", o.Class, o.Token)
}

// hasLetter is a placeholder hook for disp-register disambiguation; for the
// Phase-1 set disp operands carry their base in the token, so default to N.
func hasLetter(operand.Operand, byte) bool { return true }

// nibbles renders the first word's four nibbles as upstream codes.
func nibbles(in ir.Insn) (string, error) {
	w := in.Words[0]
	out := make([]string, 4)
	for n := 0; n < 4; n++ {
		hi := n * 4
		// If all four bits in the nibble are fixed, render the hex digit.
		allFixed := true
		val := 0
		for k := 0; k < 4; k++ {
			bit := w[hi+k]
			if !bit.Fixed {
				allFixed = false
				break
			}
			val = val<<1 | bit.Val
		}
		if allFixed {
			out[n] = fmt.Sprintf("0x%X", val)
			continue
		}
		// Operand nibble: render the upstream nibble code for its letter.
		switch w[hi].Letter {
		case 'n':
			out[n] = "REG_N"
		case 'm':
			out[n] = "REG_M"
		case 'i':
			out[n] = "IMM0_4"
		case 'd':
			out[n] = "DISP0_4"
		default:
			return "", fmt.Errorf("gas: unhandled nibble letter %q in %s", w[hi].Letter, in.Mnemonic)
		}
	}
	return strings.Join(out, ","), nil
}
