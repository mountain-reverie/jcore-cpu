package model

import (
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestIllegalModeNoneEmitsConstantFalse(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatalf("load spec: %v", err)
	}
	d, err := Build(s, 72, IllegalNone)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
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
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatalf("load spec: %v", err)
	}
	d, err := Build(s, 72, IllegalFull)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
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
