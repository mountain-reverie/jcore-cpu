package llvm

import (
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/loader"
)

func build(t *testing.T, raw loader.RawInsn) []ir.Insn {
	t.Helper()
	insns, err := ir.Build([]loader.RawInsn{raw})
	if err != nil {
		t.Fatal(err)
	}
	return insns
}

func TestEmitContainsDefAndEncoding(t *testing.T) {
	insns := build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov\tRm,Rn",
		Code: "0110nnnnmmmm0011", J2: true,
	})
	out := EmitInstrInfo(insns)
	if !strings.Contains(out, "def MOV_") {
		t.Errorf("missing def:\n%s", out)
	}
	// fixed top nibble 0110 => Inst{15} = 0; Inst{13} = 1
	if !strings.Contains(out, "let Inst{15} = 0;") {
		t.Errorf("missing fixed bit assignment:\n%s", out)
	}
	if !strings.Contains(out, "Predicates = [HasJ2]") {
		t.Errorf("missing predicate:\n%s", out)
	}
	if !strings.Contains(out, `AsmString`) {
		t.Errorf("missing AsmString:\n%s", out)
	}
}
