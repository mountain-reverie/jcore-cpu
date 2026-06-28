package loader

import (
	"strings"
	"testing"
)

const sample = `{"instructions":[
  {"group":"Data Transfer Instructions","format":"mov\tRm,Rn","code":"0110nnnnmmmm0011","T":"-","J2":true,"SH1":true},
  {"group":"DSP ALU Arithmetic Operation Instructions","format":"padd\tSx,Sy,Dz","code":"111110xxyyyygzzz","DSP":true},
  {"group":"Branch Instructions","format":"bra\tlabel","code":"1010dddddddddddd","SH1":true},
  {"group":"Bit Manipulation Instructions","format":"tas.b\t@Rn","code":"0100nnnn00011011","collides":["x"],"J2":true}
]}`

func TestLoadExcludesDSPAndNonPhase1(t *testing.T) {
	got, err := Load(strings.NewReader(sample))
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("want 2 insns (mov, tas.b), got %d: %+v", len(got), got)
	}
	if got[0].Format != "mov\tRm,Rn" || !got[0].J2 || !got[0].SH1 {
		t.Errorf("mov fields wrong: %+v", got[0])
	}
	if got[1].Format != "tas.b\t@Rn" || len(got[1].Collides) != 1 {
		t.Errorf("tas.b fields wrong: %+v", got[1])
	}
}

func TestIsPhase1Group(t *testing.T) {
	if !IsPhase1Group("Shift Instructions") {
		t.Error("Shift Instructions should be phase 1")
	}
	if IsPhase1Group("Branch Instructions") {
		t.Error("Branch Instructions is not phase 1")
	}
	if IsPhase1Group("DSP ALU Logical Operation Instructions") {
		t.Error("DSP groups never phase 1")
	}
}
