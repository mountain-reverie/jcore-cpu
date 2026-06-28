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

func TestEmitTwoWordBitPos(t *testing.T) {
	insns := build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov.l\t@(disp12,Rm),Rn",
		Code: "0011nnnnmmmm0001 0110dddddddddddd", SH2A: true,
	})
	out := EmitInstrInfo(insns)
	// Two-word encoding: 32-bit Inst total
	if !strings.Contains(out, "bits<32> Inst;") {
		t.Errorf("missing bits<32>:\n%s", out)
	}
	// word0 nibble 0011 occupies bits 31..28
	wantBits := []string{
		"let Inst{31} = 0;",
		"let Inst{30} = 0;",
		"let Inst{29} = 1;",
		"let Inst{28} = 1;",
		// word1 leading nibble 0110 occupies bits 15..12
		"let Inst{15} = 0;",
		"let Inst{14} = 1;",
		"let Inst{13} = 1;",
		"let Inst{12} = 0;",
	}
	for _, want := range wantBits {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
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
