package oracle

import (
	"testing"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/loader"
)

func TestReconstructSingleWord(t *testing.T) {
	insns, err := ir.Build([]loader.RawInsn{{
		Group: "Data Transfer Instructions", Format: "mov\tRm,Rn",
		Code: "0110nnnnmmmm0011", SH1: true,
	}})
	if err != nil {
		t.Fatal(err)
	}
	if got := Reconstruct(insns[0]); got != "0110nnnnmmmm0011" {
		t.Errorf("reconstruct = %q", got)
	}
}

func TestReconstructTwoWord(t *testing.T) {
	insns, err := ir.Build([]loader.RawInsn{{
		Group: "Data Transfer Instructions", Format: "mov.l\t@(disp12,Rm),Rn",
		Code: "0011nnnnmmmm0001 0110dddddddddddd", SH2A: true,
	}})
	if err != nil {
		t.Fatal(err)
	}
	want := "0011nnnnmmmm0001 0110dddddddddddd"
	if got := Reconstruct(insns[0]); got != want {
		t.Errorf("reconstruct = %q want %q", got, want)
	}
}
