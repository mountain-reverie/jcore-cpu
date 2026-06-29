package loader

import (
	"strings"
	"testing"
)

const sample = `{"instructions":[
  {"group":"Data Transfer Instructions","format":"mov\tRm,Rn","code":"0110nnnnmmmm0011","T":"-","J2":true,"SH1":true},
  {"group":"DSP ALU Arithmetic Operation Instructions","format":"padd\tSx,Sy,Dz","code":"111110xxyyyygzzz","DSP":true},
  {"group":"Branch Instructions","format":"bra\tlabel","code":"1010dddddddddddd","SH1":true},
  {"group":"System Control Instructions","format":"ldc\tRm,SR","code":"0100mmmm00001110","SH1":true},
  {"group":"System Control Instructions","format":"lds\tRm,DSR","code":"0100mmmm01101010","DSP":true},
  {"group":"Bit Manipulation Instructions","format":"tas.b\t@Rn","code":"0100nnnn00011011","collides":["x"],"J2":true}
]}`

func TestLoadKeepsBranchAndSystemDropsDSPOperands(t *testing.T) {
	got, dropped, err := Load(strings.NewReader(sample))
	if err != nil {
		t.Fatal(err)
	}
	// kept: mov, bra, ldc Rm,SR, tas.b  (4). Excluded: padd (DSP group),
	// lds Rm,DSR (System group but DSR operand). dropped counts only the
	// operand-excluded System/Branch insn => 1.
	if len(got) != 4 {
		t.Fatalf("want 4 kept insns, got %d: %+v", len(got), got)
	}
	if dropped != 1 {
		t.Fatalf("want dropped=1 (lds Rm,DSR), got %d", dropped)
	}
	for _, in := range got {
		if strings.Contains(in.Format, "DSR") || in.Group == "DSP ALU Arithmetic Operation Instructions" {
			t.Errorf("excluded insn leaked: %+v", in)
		}
	}
}

func TestIsEmittedGroup(t *testing.T) {
	for _, g := range []string{"Shift Instructions", "Branch Instructions", "System Control Instructions"} {
		if !IsEmittedGroup(g) {
			t.Errorf("%q should be emitted", g)
		}
	}
	if IsEmittedGroup("DSP ALU Logical Operation Instructions") {
		t.Error("DSP groups never emitted")
	}
	if !IsEmittedGroup("Floating-Point Single-Precision Instructions (FPSCR.PR = 0)") {
		t.Error("single-precision FP group should now be emitted")
	}
	if !IsEmittedGroup("Floating-Point Double-Precision Instructions (FPSCR.PR = 1)") {
		t.Error("double-precision FP group must now be emitted")
	}
	if !IsEmittedGroup("64 Bit Floating-Point Data Transfer Instructions (FPSCR.SZ = 1)") {
		t.Error("64-bit FP transfer group must now be emitted")
	}
}

func TestIsDSPCoprocOperand(t *testing.T) {
	for _, tok := range []string{"A0", "X0", "DSR", "CP0_Rm", "Sx"} {
		if !isDSPCoprocOperand(tok) {
			t.Errorf("%q should be a DSP/coproc operand", tok)
		}
	}
	for _, tok := range []string{"Rn", "SR", "label", "@Rm"} {
		if isDSPCoprocOperand(tok) {
			t.Errorf("%q should NOT be a DSP/coproc operand", tok)
		}
	}
}
