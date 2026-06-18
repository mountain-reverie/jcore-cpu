// decode/gen-go/internal/spec/profile_test.go
package spec

import "testing"

func TestApplyDropsMovesNamedInstr(t *testing.T) {
	s := &Spec{Instrs: []Instr{
		{Name: "ADD Rm, Rn", Opcode: "0011 nnnn mmmm 1100"},
		{Name: "CAS.L Rm, Rn, @R0", Opcode: "0010 nnnn mmmm 0011"},
	}}
	if err := ApplyDrops(s, []string{"CAS.L Rm, Rn, @R0"}); err != nil {
		t.Fatal(err)
	}
	if len(s.Instrs) != 1 || s.Instrs[0].Name != "ADD Rm, Rn" {
		t.Fatalf("CAS.L not removed from Instrs: %+v", s.Instrs)
	}
	if len(s.Dropped) != 1 || s.Dropped[0].Opcode != "0010 nnnn mmmm 0011" {
		t.Fatalf("CAS.L not recorded in Dropped: %+v", s.Dropped)
	}
}

func TestApplyDropsUnknownNameErrors(t *testing.T) {
	s := &Spec{Instrs: []Instr{{Name: "ADD Rm, Rn"}}}
	if err := ApplyDrops(s, []string{"NOPE"}); err == nil {
		t.Fatal("expected error for unknown drop name, got nil")
	}
}
