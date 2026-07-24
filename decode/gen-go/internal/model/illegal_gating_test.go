package model

import (
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/logic"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestIllegalInstrPerVariant verifies Phase 0's per-variant illegal-instruction
// gating (spec.InjectOverlayIllegals -> model.BuildBody -> Body.IllegalInstr)
// entirely at the Go unit level, independent of the C-VHDL cosim environment.
// It builds the decoder model for base J2, J2A (sh2a overlay), and J4 (sh4
// overlay) and evaluates the generated check_illegal_instruction boolean
// expression against representative opcodes drawn from each ISA:
//
//   - 0x3211: SH-2A "MOV.L @(disp12,Rm),Rn" word1 (0011 nnnn mmmm 0001,
//     n=2,m=1) -- real instruction on J2A, must trap as illegal elsewhere.
//   - 0x0038: SH-4 LDTLB (0000 0000 0011 1000) -- real instruction on J4,
//     must trap as illegal elsewhere.
//   - 0x000B: RTS, 0x300C: ADD R0,R0 -- base J2 instructions, legal on
//     every variant.
func TestIllegalInstrPerVariant(t *testing.T) {
	const (
		sh2aWord1 = 0x3211 // SH-2A MOV.L @(disp12,Rm),Rn word1
		sh4LDTLB  = 0x0038 // SH-4 LDTLB
		rts       = 0x000B // base J2 RTS
		addR0R0   = 0x300C // base J2 ADD Rm,Rn
		ldcTBR    = 0x404A // SH-2A ldc Rm,TBR (0100 mmmm 0100 1010, m=0)
		stcTBR    = 0x004A // SH-2A stc TBR,Rn (0000 nnnn 0100 1010, n=0)
		jsrnAtTBR = 0x8300 // SH-2A jsr/n @@(disp8,TBR) (1000 0011 dddddddd)
	)

	build := func(t *testing.T, overlays ...string) *Decoder {
		t.Helper()
		var s *spec.Spec
		var err error
		if len(overlays) == 0 {
			s, err = spec.Load("../../spec")
		} else {
			s, err = spec.LoadProfile("../../spec", overlays...)
		}
		if err != nil {
			t.Fatalf("load spec: %v", err)
		}
		if err := spec.InjectOverlayIllegals(s, "../../spec", []string{"sh2a", "sh4"}); err != nil {
			t.Fatalf("InjectOverlayIllegals: %v", err)
		}
		d, err := Build(s, 72)
		if err != nil {
			t.Fatalf("Build: %v", err)
		}
		if d.Body == nil || d.Body.IllegalInstr == "" {
			t.Fatal("Build did not produce a non-empty Body.IllegalInstr")
		}
		return d
	}

	// stubPrefix is the hardcoded "code(15 downto 8) = x"ff"" OR-term that
	// buildIllegalInstr (internal/model/body.go) always prepends. EvalBoolExpr's
	// grammar (internal/logic/eval.go) only supports single-bit comparisons
	// ("code(N) = '0'/'1'"), not VHDL "downto" range slices, so it cannot parse
	// this term directly. None of this test's opcodes (0x3211, 0x0038, 0x000B,
	// 0x300C) have a high byte of 0xff, so the stub term is always false for
	// them; strip it here rather than extending EvalBoolExpr's grammar for a
	// term whose value is fixed and irrelevant to the per-variant behavior
	// under test.
	const stubPrefix = `(code(15 downto 8) = x"ff") or `

	// The remainder is the QMC-reduced excluded-opcode expression, always
	// wrapped by buildIllegalInstr as "(BOOLEXPR = '1')" (a std_logic
	// comparison of the OR-chain against '1', mirroring the pattern
	// differential_test.go's stripStdLogicQuotes/preprocessExpr also work
	// around). EvalBoolExpr's comparison grammar only accepts
	// "IDENT(INT) = 'bit'", not "(expr) = 'bit'", so unwrap it: strip the
	// outer parens and the trailing " = '1'" to recover the pure boolean
	// OR-chain BOOLEXPR, which EvalBoolExpr parses directly.
	unwrapEquality := func(t *testing.T, expr string) string {
		t.Helper()
		expr = strings.TrimPrefix(expr, "(")
		expr = strings.TrimSuffix(expr, ")")
		inner, ok := strings.CutSuffix(expr, " = '1'")
		if !ok {
			t.Fatalf("IllegalInstr expression missing expected \" = '1'\" wrapper: %q", expr)
		}
		return inner
	}

	evalIllegal := func(t *testing.T, d *Decoder, opcode uint16) bool {
		t.Helper()
		expr := unwrapEquality(t, strings.TrimPrefix(d.Body.IllegalInstr, stubPrefix))
		got, err := logic.EvalBoolExpr(expr, func(sig string, bit int) int {
			if sig == "code" {
				return int((opcode >> bit) & 1)
			}
			return 0
		})
		if err != nil {
			t.Fatalf("EvalBoolExpr(%q, opcode=%#04x): %v", d.Body.IllegalInstr, opcode, err)
		}
		return got
	}

	base := build(t)
	j2a := build(t, "../../spec/sh2a")
	j4 := build(t, "../../spec/sh4")

	cases := []struct {
		variant string
		d       *Decoder
		opcode  uint16
		name    string
		want    bool
	}{
		{"base", base, sh2aWord1, "sh2a disp12 word1", true},
		{"base", base, sh4LDTLB, "sh4 LDTLB", true},
		{"base", base, rts, "RTS", false},
		{"base", base, addR0R0, "ADD R0,R0", false},

		{"base", base, ldcTBR, "ldc Rm,TBR", true},
		{"base", base, stcTBR, "stc TBR,Rn", true},
		{"base", base, jsrnAtTBR, "jsr/n @@(disp8,TBR)", true},

		{"j2a", j2a, sh2aWord1, "sh2a disp12 word1", false},
		{"j2a", j2a, sh4LDTLB, "sh4 LDTLB", true},
		{"j2a", j2a, ldcTBR, "ldc Rm,TBR", false},
		{"j2a", j2a, stcTBR, "stc TBR,Rn", false},
		{"j2a", j2a, jsrnAtTBR, "jsr/n @@(disp8,TBR)", false},

		{"j4", j4, sh2aWord1, "sh2a disp12 word1", true},
		{"j4", j4, sh4LDTLB, "sh4 LDTLB", false},
		{"j4", j4, ldcTBR, "ldc Rm,TBR", true},
		{"j4", j4, stcTBR, "stc TBR,Rn", true},
		{"j4", j4, jsrnAtTBR, "jsr/n @@(disp8,TBR)", true},
	}

	for _, c := range cases {
		got := evalIllegal(t, c.d, c.opcode)
		if got != c.want {
			t.Errorf("%s variant: check_illegal_instruction(%#04x %s) = %v, want %v",
				c.variant, c.opcode, c.name, got, c.want)
		}
	}
}
