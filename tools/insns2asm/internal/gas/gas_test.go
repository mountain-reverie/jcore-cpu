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
	out := EmitDelta(insns)
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
	out := EmitDelta(insns)
	if !strings.Contains(out, "A_IMM") || !strings.Contains(out, "A_REG_N") {
		t.Errorf("missing arg codes:\n%s", out)
	}
	if !strings.Contains(out, "arch_j_core") {
		t.Errorf("missing arch mask:\n%s", out)
	}
}
