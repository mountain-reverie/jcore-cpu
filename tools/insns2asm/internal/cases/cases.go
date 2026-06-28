// Package cases synthesizes (asm, expected-bytes) round-trip test cases from
// the IR, sweeping register operands across all 16 values (rm != rn within a
// case) and immediates across boundary values.
package cases

import (
	"fmt"
	"strings"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/encoding"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/operand"
)

// Case is one round-trip test vector.
type Case struct {
	Asm string // llvm-mc-acceptable assembly text
	Hex string // big-endian bytes, space-separated, e.g. "61 23"
}

var immBoundaries = []int{0x00, 0x7f, 0x80, 0xff}

// regLetters returns the operand letters that bind a register field, in order.
func regLetters(in ir.Insn) []byte {
	var ls []byte
	for _, o := range in.Operands {
		switch o.Class {
		case operand.GPR, operand.MemReg, operand.MemPostInc, operand.MemPreDec, operand.MemR0:
			if o.Letter != 0 {
				ls = append(ls, o.Letter)
			}
		}
	}
	return ls
}

func immLetter(in ir.Insn) (byte, bool) {
	for _, o := range in.Operands {
		if o.Class == operand.Imm && o.Letter != 0 {
			return o.Letter, true
		}
	}
	return 0, false
}

// Synthesize builds the operand-value sweep for one instruction.
func Synthesize(in ir.Insn) []Case {
	regs := regLetters(in)
	immL, hasImm := immLetter(in)
	n := 16
	if len(regs) == 0 && !hasImm {
		n = 1 // no operands: one fixed case
	}
	var out []Case
	for k := 0; k < n; k++ {
		vals := map[byte]int{}
		for i, l := range regs {
			vals[l] = (k + i) % 16
		}
		if hasImm {
			vals[immL] = immBoundaries[k%len(immBoundaries)]
		}
		out = append(out, Case{Asm: renderAsm(in, vals), Hex: renderHex(in, vals)})
	}
	return out
}

// SynthesizeAll concatenates the sweeps of all instructions.
func SynthesizeAll(insns []ir.Insn) []Case {
	var out []Case
	for _, in := range insns {
		out = append(out, Synthesize(in)...)
	}
	return out
}

// renderAsm builds mnemonic + space + comma-joined surface(operand).
func renderAsm(in ir.Insn, vals map[byte]int) string {
	if len(in.Operands) == 0 {
		return in.Mnemonic
	}
	parts := make([]string, len(in.Operands))
	for i, o := range in.Operands {
		parts[i] = surface(o, vals[o.Letter])
	}
	return in.Mnemonic + " " + strings.Join(parts, ", ")
}

// surface renders one operand's assembly text as the SH AsmParser accepts it.
// Kept in sync (by convention) with the C++ InstPrinter PrintMethods; the
// objdump leg of the 3-way oracle validates the agreement.
func surface(o operand.Operand, val int) string {
	switch o.Class {
	case operand.R0Fixed:
		return "r0"
	case operand.GPR:
		return fmt.Sprintf("r%d", val)
	case operand.Imm:
		return fmt.Sprintf("#%d", int8(val))
	case operand.MemReg:
		if o.Fixed != "" {
			return "@" + strings.ToLower(o.Fixed)
		}
		return fmt.Sprintf("@r%d", val)
	case operand.MemPostInc:
		if o.Fixed != "" {
			return "@" + strings.ToLower(o.Fixed) + "+"
		}
		return fmt.Sprintf("@r%d+", val)
	case operand.MemPreDec:
		if o.Fixed != "" {
			return "@-" + strings.ToLower(o.Fixed)
		}
		return fmt.Sprintf("@-r%d", val)
	case operand.MemR0:
		return fmt.Sprintf("@(r0,r%d)", val)
	case operand.MemR0GBR:
		return "@(r0,gbr)"
	}
	return o.Token
}

// renderHex computes the big-endian bytes for one word with fields filled.
// For MSB-first word index i (absolute bit position p = 15-i), the field bit
// offset within the field is shift = p - f.Lo = (15-i) - f.Lo.
func renderHex(in ir.Insn, vals map[byte]int) string {
	w := in.Words[0]
	var v uint16
	for i := 0; i < 16; i++ {
		bit := w[i] // index 0 = MSB (bit15)
		var b uint16
		if bit.Fixed {
			b = uint16(bit.Val)
		} else {
			f := fieldFor(in, bit.Letter)
			shift := (15 - i) - f.Lo
			b = uint16((vals[bit.Letter] >> shift) & 1)
		}
		v = (v << 1) | b
	}
	return fmt.Sprintf("%02x %02x", byte(v>>8), byte(v))
}

func fieldFor(in ir.Insn, letter byte) encoding.Field {
	for _, f := range in.Fields {
		if f.Letter == letter {
			return f
		}
	}
	return encoding.Field{}
}
