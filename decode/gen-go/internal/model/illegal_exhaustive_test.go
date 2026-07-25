package model

import (
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/logic"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// definedSet returns, for every 16-bit encoding, whether some non-system
// instruction in s defines it. system-plane entries are microcode-only and
// their opcode fields are placeholders, so they are excluded: a placeholder
// overlapping a real instruction is harmless, one overlapping a hole leaves
// it a hole.
func definedSet(s *spec.Spec) [65536]bool {
	var defined [65536]bool
	for _, in := range s.Instrs {
		if in.Plane == "system" {
			continue
		}
		pat := strings.ReplaceAll(in.Opcode, " ", "")
		if len(pat) != 16 {
			continue
		}
		for op := 0; op < 65536; op++ {
			match := true
			for i := 0; i < 16; i++ {
				bit := (op >> uint(15-i)) & 1
				if (pat[i] == '0' && bit != 0) || (pat[i] == '1' && bit != 1) {
					match = false
					break
				}
			}
			if match {
				defined[op] = true
			}
		}
	}
	return defined
}

// evalIllegal evaluates a generated VHDL boolean expression for one opcode.
func evalIllegal(t *testing.T, expr string, op uint16) bool {
	t.Helper()
	v, err := logic.EvalBoolExpr(expr, func(sig string, bit int) int {
		if sig != "code" {
			t.Fatalf("unexpected sig %q in expression", sig)
		}
		return int((op >> uint(bit)) & 1)
	})
	if err != nil {
		t.Fatalf("eval %q: %v", expr, err)
	}
	return v
}

// TestIllegalNeverTrapsDefinedOpcodes is the safety half of correctness: no
// encoding that the loaded spec defines may be reported illegal. It must hold
// for every variant, both before and after the switch to exhaustive coverage.
func TestIllegalNeverTrapsDefinedOpcodes(t *testing.T) {
	for _, tc := range []struct {
		name     string
		overlays []string
	}{
		{"base", nil},
		{"sh2a", []string{"../../spec/sh2a"}},
		{"sh4", []string{"../../spec/sh4"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var s *spec.Spec
			var err error
			if len(tc.overlays) == 0 {
				s, err = spec.Load("../../spec")
			} else {
				s, err = spec.LoadProfile("../../spec", tc.overlays...)
			}
			if err != nil {
				t.Fatalf("load: %v", err)
			}
			if err := spec.InjectOverlayIllegals(s, "../../spec", []string{"sh2a", "sh4"}); err != nil {
				t.Fatalf("InjectOverlayIllegals: %v", err)
			}
			d, err := Build(s, 72, IllegalFull)
			if err != nil {
				t.Fatalf("Build: %v", err)
			}
			defined := definedSet(s)

			// Preprocess the expression once per variant. The stub prefix
			// "code(15 downto 8) = x"ff") or " cannot be parsed by EvalBoolExpr
			// (it uses VHDL range syntax). Strip it; it only affects opcodes
			// with high byte 0xff, which are genuinely illegal per spec.
			const stubPrefix = `(code(15 downto 8) = x"ff") or `
			expr := strings.TrimPrefix(d.Body.IllegalInstr, stubPrefix)

			// Unwrap the "(BOOLEXPR = '1')" wrapper: trim outer parens and
			// the trailing " = '1'" suffix to recover the pure OR-chain.
			expr = strings.TrimPrefix(expr, "(")
			expr = strings.TrimSuffix(expr, ")")
			inner, ok := strings.CutSuffix(expr, " = '1'")
			if !ok {
				t.Fatalf("IllegalInstr missing \" = '1'\" wrapper: %q", d.Body.IllegalInstr)
			}
			expr = inner

			for op := 0; op < 65536; op++ {
				// Skip opcodes with high byte 0xff; the stub covers those
				// and they are all genuinely illegal.
				if (op >> 8) == 0xff {
					continue
				}
				if !defined[op] {
					continue
				}
				if evalIllegal(t, expr, uint16(op)) {
					t.Fatalf("opcode %#04x is defined but reported illegal", op)
				}
			}
		})
	}
}
