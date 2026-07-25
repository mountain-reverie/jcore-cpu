package model

import (
	"strings"
	"testing"

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
			d, err := Build(s, 72, IllegalFull)
			if err != nil {
				t.Fatalf("Build: %v", err)
			}
			defined := definedSet(s)

			for op := 0; op < 65536; op++ {
				if !defined[op] {
					continue
				}
				if d.Body.IllegalInstr.Eval(uint16(op)) {
					t.Fatalf("opcode %#04x is defined but reported illegal", op)
				}
			}
		})
	}
}

// TestIllegalCoversEveryHole is the completeness half: every encoding the
// loaded spec does not define must be reported illegal, for every variant.
func TestIllegalCoversEveryHole(t *testing.T) {
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
			d, err := Build(s, 72, IllegalFull)
			if err != nil {
				t.Fatalf("Build: %v", err)
			}
			defined := definedSet(s)
			holes, trapped := 0, 0
			for op := 0; op < 65536; op++ {
				if defined[op] {
					continue
				}
				holes++
				if d.Body.IllegalInstr.Eval(uint16(op)) {
					trapped++
				}
			}
			if trapped != holes {
				t.Errorf("%s: trapped %d of %d holes; want all", tc.name, trapped, holes)
			}
			if holes == 0 {
				t.Fatal("no holes found — definedSet is wrong")
			}
		})
	}
}
