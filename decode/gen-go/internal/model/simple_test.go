package model

import (
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestBuildSimpleProductionInstructionCount(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if d.Simple == nil {
		t.Fatal("Build did not produce Simple")
	}
	// 160 instructions in the production spec — 154 normal + 6 system.
	// The simple decoder table dispatches on both planes; system entries
	// drive the interrupt/exception if_issue + dispatch slots.
	if got := len(d.Simple.Instructions); got != 160 {
		t.Errorf("Simple has %d instructions, want 160", got)
	}
	// All patterns must be 17 chars (1 plane bit + 16 opcode bits).
	for i, in := range d.Simple.Instructions {
		if len(in.StdMatchPattern) != 17 {
			t.Errorf("instr %d (%s) pattern length = %d, want 17",
				i, in.Name, len(in.StdMatchPattern))
		}
	}
	// At least one system-plane instruction must have a pattern starting
	// with '1' (the plane=system bit).
	var foundSystem bool
	for _, in := range d.Simple.Instructions {
		if len(in.StdMatchPattern) > 0 && in.StdMatchPattern[0] == '1' {
			foundSystem = true
			break
		}
	}
	if !foundSystem {
		t.Error("no system-plane instruction in Simple.Instructions (plane bit '1' missing)")
	}
}
