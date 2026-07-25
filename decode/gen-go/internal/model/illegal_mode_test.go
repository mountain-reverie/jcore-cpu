package model

import (
	"strings"
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
	if got := d.Body.IllegalInstr; got != "false" {
		t.Errorf("IllegalMode none: IllegalInstr = %q, want %q", got, "false")
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
	if strings.TrimSpace(d.Body.IllegalInstr) == "" || d.Body.IllegalInstr == "false" {
		t.Errorf("IllegalMode full: IllegalInstr = %q, want a real expression", d.Body.IllegalInstr)
	}
}
