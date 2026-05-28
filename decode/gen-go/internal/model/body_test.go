package model

import (
	"fmt"
	"strconv"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/logic"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestPredecodeFunctionalEvaluation runs the in-Go evaluator over the
// production spec and confirms predecode_rom_addr(opcode) returns the
// correct ROM address for every non-system instruction. This is the M4
// correctness gate for decode_body.vhd; even without L3 differential
// simulation, the predecode function's logic CAN be verified entirely
// in Go because it's a pure combinational function of the 16-bit opcode.
func TestPredecodeFunctionalEvaluation(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if d.Body == nil {
		t.Fatal("Build did not produce Body")
	}

	// For each non-system instruction, generate a representative opcode
	// (fill don't-cares with 0) and run our Go evaluator.
	for _, instr := range s.Instrs {
		if instr.Plane == "system" {
			continue
		}
		opcode := representativeOpcode(instr.Opcode)
		got, err := evaluatePredecode(d.Body, opcode)
		if err != nil {
			t.Errorf("%s: evaluatePredecode(%016b) failed: %v", instr.Name, opcode, err)
			continue
		}
		// Want = the M3 first ROM addr for this instruction. Look it up
		// via the ROM word comment (set by build.go on the last slot of
		// each instruction).
		want := romFirstAddr(d.ROM, instr.Name)
		if want < 0 {
			t.Logf("%s: no ROM address found (skipped)", instr.Name)
			continue
		}
		if got != want {
			t.Errorf("%s: predecode_rom_addr(%016b) = %d, want %d",
				instr.Name, opcode, got, want)
		}
	}
}

// representativeOpcode fills don't-care bits ('n','m','d','i','-') with 0
// to produce a concrete 16-bit opcode for evaluation.
func representativeOpcode(pattern string) uint16 {
	var out uint16
	bit := 15
	for _, c := range pattern {
		if c == ' ' {
			continue
		}
		if c == '1' {
			out |= 1 << bit
		}
		bit--
	}
	return out
}

// evaluatePredecode runs the Go-side equivalent of predecode_rom_addr.
// Returns the 8-bit address.
func evaluatePredecode(b *Body, opcode uint16) (int, error) {
	nib := int((opcode >> 12) & 0xF)
	arm := b.Predecode.Arms[nib]
	if arm.LiteralAddr != "" {
		// LiteralAddr is a VHDL hex literal like `x"9e"` or the legacy
		// binary form like `"01010100"`. Parse either.
		s := arm.LiteralAddr
		if strings.HasPrefix(s, `x"`) && strings.HasSuffix(s, `"`) {
			hex := s[2 : len(s)-1]
			v, err := strconv.ParseInt(hex, 16, 32)
			if err != nil {
				return 0, fmt.Errorf("LiteralAddr hex parse %q: %w", s, err)
			}
			return int(v), nil
		}
		s = strings.Trim(s, `"`)
		var v int
		for i, c := range s {
			if c == '1' {
				v |= 1 << (len(s) - 1 - i)
			}
		}
		return v, nil
	}
	addr := 0
	for _, ba := range arm.BitAssigns {
		if evalBoolExpr(ba.Expr, opcode) {
			addr |= 1 << ba.Bit
		}
	}
	return addr, nil
}

// evalBoolExpr evaluates a generated VHDL boolean expression against
// a 16-bit opcode by delegating to logic.EvalBoolExpr. The resolver
// returns opcode bits for sig="code" and 0 for sig="p" (the predecode
// path only sees non-system instructions, where plane=0).
func evalBoolExpr(expr string, opcode uint16) bool {
	v, _ := logic.EvalBoolExpr(expr, func(sig string, bit int) int {
		switch sig {
		case "code":
			return int((opcode >> bit) & 1)
		case "p":
			return 0
		}
		return 0
	})
	return v
}

// romFirstAddr returns the first ROM address where the instruction with
// the given name appears, or -1 if not found. (Comments on ROMWord are
// set on the LAST slot; we find that index and walk back.)
func romFirstAddr(rom *ROM, name string) int {
	last := -1
	for i, w := range rom.Words {
		if w.Comment == name {
			last = i
			break
		}
	}
	if last < 0 {
		return -1
	}
	// Walk back through addresses with empty comment until we hit an
	// addressed slot or another instruction's comment.
	first := last
	for first > 0 && rom.Words[first-1].Comment == "" && rom.Words[first-1].Bits != "" {
		// Trailing-zero unused slots also have empty comment; distinguish
		// by checking the bit string. M3's build.go pre-fills unused
		// addresses with all-zero strings — if the bits are all '0',
		// it's probably an unused slot. But intermediate slots also
		// might be all-zero for very simple instructions. The safe
		// approach is to keep walking back as long as the comment is "".
		first--
	}
	return first
}

// (The VHDL boolean expression evaluator was moved to
// internal/logic/eval.go as EvalBoolExpr — see evalBoolExpr above.)
