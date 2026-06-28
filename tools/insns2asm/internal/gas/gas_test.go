package gas

import (
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/loader"
)

func TestEmitDeltaSkipsSHInstructions(t *testing.T) {
	insns, err := ir.Build([]loader.RawInsn{
		{Group: "Data Transfer Instructions", Format: "mov\tRm,Rn",
			Code: "0110nnnnmmmm0011", SH1: true, J2: true}, // SH present -> skip
		{Group: "Data Transfer Instructions", Format: "movi20\t#imm20,Rn",
			Code: "0000nnnniiii0000 iiiiiiiiiiiiiiii", J2: true}, // jcore-only -> emit
	})
	if err != nil {
		t.Fatal(err)
	}
	out, err := EmitDelta(insns)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(out, `"mov"`) {
		t.Errorf("mov is an SH insn, should be skipped:\n%s", out)
	}
	if !strings.Contains(out, `"movi20"`) {
		t.Errorf("movi20 (jcore-only) should be emitted:\n%s", out)
	}
}

func TestEmitDeltaArgsAndArch(t *testing.T) {
	insns, _ := ir.Build([]loader.RawInsn{
		{Group: "Data Transfer Instructions", Format: "movi20\t#imm20,Rn",
			Code: "0000nnnniiii0000 iiiiiiiiiiiiiiii", J2: true},
	})
	out, err := EmitDelta(insns)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, "A_IMM") || !strings.Contains(out, "A_REG_N") {
		t.Errorf("missing arg codes:\n%s", out)
	}
	if !strings.Contains(out, "arch_j_core") {
		t.Errorf("missing arch mask:\n%s", out)
	}
}

func TestNibblesKnownPattern(t *testing.T) {
	// code "0000nnnniiii0000": nibble0=0x0, nibble1=REG_N, nibble2=IMM0_4, nibble3=0x0
	insns, err := ir.Build([]loader.RawInsn{
		{Group: "Data Transfer Instructions", Format: "movi20\t#imm20,Rn",
			Code: "0000nnnniiii0000 iiiiiiiiiiiiiiii", J2: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	got, err := nibbles(insns[0])
	if err != nil {
		t.Fatal(err)
	}
	want := "0x0,REG_N,IMM0_4,0x0"
	if got != want {
		t.Errorf("nibbles = %q, want %q", got, want)
	}
}
