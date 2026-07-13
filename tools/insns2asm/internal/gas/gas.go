// Package gas emits a minimal binutils sh-opc.h delta containing only the
// J-core-only instructions (parity mode: SH instructions are assumed present
// upstream and skipped).
package gas

import (
	"fmt"
	"regexp"
	"sort"
	"strings"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/operand"
)

// EmitDelta renders the J-core-only instructions as sh_table entries.
//
// Entries are grouped by mnemonic (stable sort, preserving insns.json order
// within a mnemonic and the relative order of first appearance across
// mnemonics) so that a distinct mnemonic (e.g. ldtlb.rn) is never interleaved
// into another mnemonic's entries when the delta is spliced into upstream
// sh-opc.h: gas's mnemonic matcher requires all sh_table entries sharing a
// mnemonic to be contiguous.
func EmitDelta(insns []ir.Insn) (string, error) {
	jcoreOnly := make([]ir.Insn, 0, len(insns))
	for _, in := range insns {
		if in.Arch.IsJCoreOnly() {
			jcoreOnly = append(jcoreOnly, in)
		}
	}
	groupOrder := make(map[string]int)
	for _, in := range jcoreOnly {
		m := strings.ToLower(in.Mnemonic)
		if _, ok := groupOrder[m]; !ok {
			groupOrder[m] = len(groupOrder)
		}
	}
	sort.SliceStable(jcoreOnly, func(i, j int) bool {
		return groupOrder[strings.ToLower(jcoreOnly[i].Mnemonic)] < groupOrder[strings.ToLower(jcoreOnly[j].Mnemonic)]
	})

	var b strings.Builder
	for _, in := range jcoreOnly {
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
			strings.ToLower(in.Mnemonic), strings.Join(args, ","), nib, in.Arch.GASMask())
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
		if o.Fixed == "R0" {
			// Fixed @R0 indirect (e.g. cas.l): a dedicated operand type that
			// does not bind a register field (A_IND_M/N would overwrite reg_m).
			return "A_IND_0", nil
		}
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
	case operand.BranchDisp:
		if o.Width == 12 {
			return "A_BDISP12", nil
		}
		return "A_BDISP8", nil
	case operand.BankReg:
		return "A_REG_B", nil
	case operand.MemTBRDisp:
		return "A_DISP_TBR", nil
	case operand.CP0Reg:
		if o.Letter == 'n' {
			return "A_CP0_REG_N", nil
		}
		return "A_CP0_REG_M", nil
	case operand.CPIReg:
		if o.Letter == 'n' {
			return "A_CPI_REG_N", nil
		}
		return "A_CPI_REG_M", nil
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
			out[n] = fmt.Sprintf("HEX_%X", val)
			continue
		}
		// Partially-fixed nibble (e.g. "1nnn"/"1mmm"): the banked-register
		// field Rn_BANK/Rm_BANK, upstream nibble code REG_B, regardless of
		// whether the variable bits are the n or m letter.
		anyFixed := false
		var letter byte
		for k := 0; k < 4; k++ {
			bit := w[hi+k]
			if bit.Fixed {
				anyFixed = true
			} else if letter == 0 {
				letter = bit.Letter
			}
		}
		if anyFixed {
			out[n] = "REG_B"
			continue
		}
		// Fully-variable operand nibble: render the upstream nibble code.
		switch letter {
		case 'n':
			out[n] = "REG_N"
		case 'm':
			out[n] = "REG_M"
		case 'i':
			out[n] = "IMM0_4"
		case 'd':
			out[n] = "DISP0_4"
		default:
			return "", fmt.Errorf("gas: unhandled nibble letter %q in %s", letter, in.Mnemonic)
		}
	}
	return strings.Join(out, ","), nil
}

// Augmentation describes an arch-mask OR-in to apply to an EXISTING upstream
// sh-opc.h sh_table line, keyed by mnemonic + nibble-tuple (a stable proxy
// for the line's opcode encoding).
type Augmentation struct {
	Mnemonic string
	Nibbles  string // e.g. "HEX_4,REG_N,HEX_3,HEX_E"
	Flag     string // e.g. "arch_j4_up"
}

// Augmentations returns, for every instruction that already exists upstream
// on an SH variant but is ALSO implemented on J4 (arch.Set.IsSharedJ4Augment),
// the arch-mask augmentation to apply to its existing sh-opc.h line. Unlike
// EmitDelta these are NOT new lines: the instruction already has an upstream
// sh_table entry, which needs arch_j4_up OR'd into its existing mask.
func Augmentations(insns []ir.Insn) ([]Augmentation, error) {
	var out []Augmentation
	for _, in := range insns {
		if !in.Arch.IsSharedJ4Augment() {
			continue
		}
		nib, err := nibbles(in)
		if err != nil {
			return nil, fmt.Errorf("gas: augmentation %s: %w", in.Mnemonic, err)
		}
		out = append(out, Augmentation{
			Mnemonic: strings.ToLower(in.Mnemonic),
			Nibbles:  nib,
			Flag:     "arch_j4_up",
		})
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Mnemonic != out[j].Mnemonic {
			return out[i].Mnemonic < out[j].Mnemonic
		}
		return out[i].Nibbles < out[j].Nibbles
	})
	return out, nil
}

// regNibbleRe matches any of the upstream register-nibble codes; for
// matching purposes (not generation) REG_N/REG_M/REG_B are interchangeable,
// since upstream sh-opc.h conventionally names the sole register-field
// nibble of an ldc/stc-to-control-register form REG_N regardless of whether
// insns.json's mnemonic calls the operand Rm or Rn.
var regNibbleRe = regexp.MustCompile(`REG_[NMB]`)

func normalizeNibbles(s string) string { return regNibbleRe.ReplaceAllString(s, "REG_X") }

// ApplyAugmentations OR's each augmentation's Flag into the arch mask of its
// matching sh_table line (identified by mnemonic + nibble tuple, with the
// register-field nibble letter (N/M/B) ignored) within src. It is
// idempotent: a line already carrying Flag is left unchanged, and unmatched
// augmentations are reported so callers can detect drift against upstream
// sh-opc.h. Returns the patched text and the number of lines changed.
func ApplyAugmentations(src string, augs []Augmentation) (string, int, error) {
	lines := strings.Split(src, "\n")
	changed := 0
	for _, aug := range augs {
		needle := "{" + normalizeNibbles(aug.Nibbles) + "}"
		mnemonicNeedle := `"` + aug.Mnemonic + `"`
		matched := false
		for i, line := range lines {
			if !strings.Contains(line, mnemonicNeedle) || !strings.Contains(normalizeNibbles(line), needle) {
				continue
			}
			matched = true
			if strings.Contains(line, aug.Flag) {
				continue // already applied: idempotent no-op
			}
			idx := strings.LastIndex(line, "},")
			if idx < 0 {
				return "", 0, fmt.Errorf("gas: augmentation %s/%s: line has no trailing \"},\": %q", aug.Mnemonic, aug.Nibbles, line)
			}
			lines[i] = line[:idx] + "|" + aug.Flag + line[idx:]
			changed++
		}
		if !matched {
			return "", 0, fmt.Errorf("gas: augmentation %s/%s: no matching upstream sh_table line found", aug.Mnemonic, aug.Nibbles)
		}
	}
	return strings.Join(lines, "\n"), changed, nil
}
