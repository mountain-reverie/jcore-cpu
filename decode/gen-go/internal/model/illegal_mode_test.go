package model

import (
	"testing"
)

func TestIllegalModeNoneEmitsConstantFalse(t *testing.T) {
	_, d := buildIllegalVariant(t, "", 72, IllegalNone)
	for nib, arm := range d.Body.IllegalInstr.Arms {
		if arm.Expr != "false" {
			t.Errorf("IllegalMode none: nibble %X = %q, want \"false\"", nib, arm.Expr)
		}
	}
	for op := 0; op < 65536; op++ {
		if d.Body.IllegalInstr.Eval(uint16(op)) {
			t.Fatalf("IllegalMode none: opcode %#04x reported illegal", op)
		}
	}
}

func TestIllegalModeFullIsNonEmpty(t *testing.T) {
	_, d := buildIllegalVariant(t, "", 72, IllegalFull)
	any := false
	for _, arm := range d.Body.IllegalInstr.Arms {
		if arm.Expr != "false" {
			any = true
		}
	}
	if !any {
		t.Error("IllegalMode full: every arm is \"false\"; want real detection logic")
	}
}
