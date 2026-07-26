package model

import (
	"testing"
)

// TestIllegalArmsIsolatedPerNibble is the churn-containment guarantee: adding
// instructions via an overlay must leave the arms of untouched top nibbles
// textually identical, so an SH-2A or SH-4 addition cannot move base J2's
// decode logic in an unrelated nibble.
func TestIllegalArmsIsolatedPerNibble(t *testing.T) {
	base, bd := buildIllegalVariant(t, "", 72, IllegalFull)

	for _, ov := range []string{"sh2a", "sh4"} {
		t.Run(ov, func(t *testing.T) {
			s, od := buildIllegalVariant(t, ov, 72, IllegalFull)

			// Which nibbles does this overlay actually add instructions to?
			touched := map[int]bool{}
			baseNames := map[string]bool{}
			for _, in := range base.Instrs {
				baseNames[in.Name] = true
			}
			for _, in := range s.Instrs {
				if baseNames[in.Name] || in.Plane == "system" {
					continue
				}
				pat := in.Opcode
				for len(pat) > 0 && pat[0] == ' ' {
					pat = pat[1:]
				}
				if len(pat) < 4 {
					continue
				}
				nib := 0
				for i := 0; i < 4; i++ {
					nib <<= 1
					if pat[i] == '1' {
						nib |= 1
					}
				}
				touched[nib] = true
			}
			if len(touched) == 0 {
				t.Fatalf("%s overlay added no instructions — test is vacuous", ov)
			}

			for nib := 0; nib < 16; nib++ {
				if touched[nib] {
					continue
				}
				if bd.Body.IllegalInstr.Arms[nib].Expr != od.Body.IllegalInstr.Arms[nib].Expr {
					t.Errorf("nibble %X untouched by %s but its arm changed:\n base: %s\n  %s: %s",
						nib, ov, bd.Body.IllegalInstr.Arms[nib].Expr, ov,
						od.Body.IllegalInstr.Arms[nib].Expr)
				}
			}
		})
	}
}
