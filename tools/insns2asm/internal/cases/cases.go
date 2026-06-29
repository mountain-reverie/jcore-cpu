// Package cases synthesizes (asm, expected-bytes) round-trip test cases from
// the IR, sweeping register operands across all 16 values (rm != rn within a
// case) and immediates across boundary values.
package cases

import (
	"fmt"
	"strings"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/llvm"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/operand"
)

// Case is one round-trip test vector.
type Case struct {
	Asm string // llvm-mc-acceptable assembly text
	Hex string // big-endian bytes, space-separated, e.g. "61 23"
}

// immBoundariesFor returns boundary values for an immediate field of the given width.
func immBoundariesFor(width int) []int {
	if width <= 3 {
		max := (1 << uint(width)) - 1
		return []int{0, 1, 2, max}
	}
	if width <= 8 {
		return []int{0, 0x7f, 0x80, 0xff}
	}
	// wider (e.g. 20-bit movi20): use unsigned field-value boundaries
	max := (1 << uint(width)) - 1
	return []int{0, 1, max >> 1, max}
}

// immFieldWidth returns the total bit-width of the immediate field letter
// summed across all words.
func immFieldWidth(in ir.Insn, letter byte) int {
	total := 0
	for _, f := range in.Fields {
		if f.Letter == letter {
			total += f.Width
		}
	}
	return total
}

// regLetters returns the operand letters that bind a register field, in order.
func regLetters(in ir.Insn) []byte {
	var ls []byte
	for _, o := range in.Operands {
		switch o.Class {
		case operand.GPR, operand.MemReg, operand.MemPostInc, operand.MemPreDec, operand.MemR0:
			if o.Letter != 0 {
				ls = append(ls, o.Letter)
			}
		case operand.MemDisp:
			// For MemDisp, add the base register letter only (disp letter is handled separately)
			if o.BaseLetter != 0 {
				ls = append(ls, o.BaseLetter)
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

// dispLetters returns displacement field letters with their max field width.
func dispLetters(in ir.Insn) map[byte]int {
	result := make(map[byte]int)
	for _, o := range in.Operands {
		switch o.Class {
		case operand.MemDisp, operand.MemPC, operand.MemGBR:
			if o.Letter != 0 {
				result[o.Letter] = o.Width
			}
		}
	}
	return result
}

// dispBoundariesFor returns boundary values for a displacement field of the given width.
func dispBoundariesFor(width int) []int {
	max := (1 << uint(width)) - 1 // 2^width - 1
	if width <= 4 {
		// For small fields, include 0, 1, 2, and max
		return []int{0, 1, 2, max}
	}
	if width == 12 {
		// SH-2A two-word forms: start sweep at 16 (> disp4 max 15) so generated asm
		// text is unambiguous with the 16-bit disp4 forms that share the same syntax.
		return []int{16, 0x7ff, 0x800, max}
	}
	// For larger fields, include 0, some mid-range values, and max
	return []int{0, 0x7f, 0x80, max}
}

// Synthesize builds the operand-value sweep for one instruction.
func Synthesize(in ir.Insn) []Case {
	regs := regLetters(in)
	immL, hasImm := immLetter(in)
	disps := dispLetters(in)

	// Compute the number of sweep iterations
	n := 16
	if len(regs) == 0 && !hasImm && len(disps) == 0 {
		n = 1 // no operands: one fixed case
	}

	// Compute the max number of boundary values across all displacement fields
	maxDispBoundaries := 0
	for _, width := range disps {
		boundaries := dispBoundariesFor(width)
		if len(boundaries) > maxDispBoundaries {
			maxDispBoundaries = len(boundaries)
		}
	}

	// If we have displacement fields, use the max number of boundaries
	if len(disps) > 0 && maxDispBoundaries > n {
		n = maxDispBoundaries
	}

	var out []Case
	for k := 0; k < n; k++ {
		vals := map[byte]int{}
		for i, l := range regs {
			vals[l] = (k + i) % 16
		}
		if hasImm {
			immWidth := immFieldWidth(in, immL)
			boundaries := immBoundariesFor(immWidth)
			vals[immL] = boundaries[k%len(boundaries)]
		}
		for dispL, width := range disps {
			boundaries := dispBoundariesFor(width)
			vals[dispL] = boundaries[k%len(boundaries)]
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
		parts[i] = surfaceWithMnemonic(in.Mnemonic, o, vals)
	}
	return in.Mnemonic + " " + strings.Join(parts, ", ")
}

// surfaceWithMnemonic renders one operand's assembly text, with access to the
// instruction mnemonic for scale-aware displacement rendering.
func surfaceWithMnemonic(mnemonic string, o operand.Operand, vals map[byte]int) string {
	switch o.Class {
	case operand.MemDisp:
		baseval := vals[o.BaseLetter]
		scale := llvm.ScaleOf(mnemonic)
		byteDisp := vals[o.Letter] * scale
		return fmt.Sprintf("@(%d,r%d)", byteDisp, baseval)
	case operand.MemPC:
		scale := llvm.ScaleOf(mnemonic)
		byteDisp := vals[o.Letter] * scale
		return fmt.Sprintf("@(%d,pc)", byteDisp)
	case operand.MemGBR:
		scale := llvm.ScaleOf(mnemonic)
		byteDisp := vals[o.Letter] * scale
		return fmt.Sprintf("@(%d,gbr)", byteDisp)
	default:
		return surface(o, vals[o.Letter])
	}
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
		if o.Width <= 8 {
			return fmt.Sprintf("#%d", int8(val))
		}
		// Wide immediate (e.g. movi20 20-bit): print unsigned field value
		// so the printed number equals the field value encoded in the hex.
		return fmt.Sprintf("#%d", val)
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

// renderHex computes the big-endian bytes for all words with fields filled.
// For a multi-word instruction, later words hold the lower-order bits of a
// field that spans words (e.g. movi20: word0 holds imm[19:16], word1 holds
// imm[15:0]).  The shift into the full value is:
//   shift = (15-i) - field.Lo + sum_of_widths_of_fields_in_later_words
func renderHex(in ir.Insn, vals map[byte]int) string {
	var parts []string
	for wi, w := range in.Words {
		var v uint16
		for i := 0; i < 16; i++ {
			bit := w[i]
			var b uint16
			if bit.Fixed {
				b = uint16(bit.Val)
			} else {
				p := 15 - i
				shift := bitShiftInVal(in, bit.Letter, wi, p)
				b = uint16((vals[bit.Letter] >> shift) & 1)
			}
			v = (v << 1) | b
		}
		parts = append(parts, fmt.Sprintf("%02x %02x", byte(v>>8), byte(v)))
	}
	return strings.Join(parts, " ")
}

// bitShiftInVal returns the right-shift to apply to vals[letter] to extract
// the bit at word-relative position p = 15-i within wordIdx.
// Fields in later words hold the lower-order bits of a multi-word field.
func bitShiftInVal(in ir.Insn, letter byte, wordIdx int, p int) int {
	var thisLo int
	laterWidth := 0
	for _, f := range in.Fields {
		if f.Letter != letter {
			continue
		}
		if f.Word == wordIdx {
			thisLo = f.Lo
		} else if f.Word > wordIdx {
			laterWidth += f.Width
		}
	}
	return (p - thisLo) + laterWidth
}
