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

func TestEmitBindsRegisterOperands(t *testing.T) {
	insns := build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov\tRm,Rn",
		Code: "0110nnnnmmmm0011", J2: true,
	})
	out := EmitInstrInfo(insns)
	if !strings.Contains(out, "def MOV_") {
		t.Errorf("missing def:\n%s", out)
	}
	// operand variables declared and bound to their fields
	if !strings.Contains(out, "bits<4> rn;") || !strings.Contains(out, "bits<4> rm;") {
		t.Errorf("missing operand bit vars:\n%s", out)
	}
	if !strings.Contains(out, "let Inst{11-8} = rn;") {
		t.Errorf("missing rn field binding:\n%s", out)
	}
	if !strings.Contains(out, "let Inst{7-4} = rm;") {
		t.Errorf("missing rm field binding:\n%s", out)
	}
	if !strings.Contains(out, "dag InOperandList = (ins GPR:$rm, GPR:$rn);") {
		t.Errorf("missing/incorrect InOperandList:\n%s", out)
	}
	if !strings.Contains(out, "dag OutOperandList = (outs);") {
		t.Errorf("missing OutOperandList:\n%s", out)
	}
	if !strings.Contains(out, `let AsmString = "mov\t${rm}, ${rn}";`) {
		t.Errorf("AsmString should use ${vars}:\n%s", out)
	}
	if !strings.Contains(out, "let Predicates = [HasJ2];") {
		t.Errorf("missing predicate:\n%s", out)
	}
}

func TestEmitBindsBranchDisp(t *testing.T) {
	insns := build(t, loader.RawInsn{
		Group: "Branch Instructions", Format: "bra\tlabel",
		Code: "1010dddddddddddd", SH1: true,
	})
	out := EmitInstrInfo(insns)
	if !strings.Contains(out, "bits<12> disp;") {
		t.Errorf("missing 12-bit disp var:\n%s", out)
	}
	if !strings.Contains(out, "let Inst{11-0} = disp;") {
		t.Errorf("missing disp binding:\n%s", out)
	}
	if !strings.Contains(out, "dag InOperandList = (ins bdisp12:$disp);") {
		t.Errorf("missing bdisp12 operand:\n%s", out)
	}
}

func TestEmitBindsMemDispBaseAndDisp(t *testing.T) {
	insns := build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov.l\t@(disp12,Rm),Rn",
		Code: "0011nnnnmmmm0001 0110dddddddddddd", SH2A: true,
	})
	out := EmitInstrInfo(insns)
	// both base reg (m) and disp (d) fields are bound
	if !strings.Contains(out, "bits<4> rm;") || !strings.Contains(out, "bits<12> disp;") {
		t.Errorf("memdisp should bind both base and disp:\n%s", out)
	}
}

func TestEmitOperandClassDefs(t *testing.T) {
	insns := build(t, loader.RawInsn{
		Group: "Branch Instructions", Format: "bra\tlabel",
		Code: "1010dddddddddddd", SH1: true,
	})
	out := EmitInstrInfo(insns)
	if !strings.Contains(out, "def bdisp12 : Operand<i32>") {
		t.Errorf("missing generated operand class def:\n%s", out)
	}
}

func TestEmitBindsSplitFieldImmediate(t *testing.T) {
	insns := build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "movi20\t#imm20,Rn",
		Code: "0000nnnniiii0000 iiiiiiiiiiiiiiii", SH2A: true,
	})
	out := EmitInstrInfo(insns)
	if !strings.Contains(out, "bits<20> imm;") {
		t.Errorf("imm should be 20 bits:\n%s", out)
	}
	if !strings.Contains(out, "let Inst{23-20} = imm{19-16};") {
		t.Errorf("missing high-nibble sub-range binding:\n%s", out)
	}
	if !strings.Contains(out, "let Inst{15-0} = imm{15-0};") {
		t.Errorf("missing low-word sub-range binding:\n%s", out)
	}
}

func TestEmitFixedRegAsLiteral(t *testing.T) {
	insns := build(t, loader.RawInsn{
		Group: "System Control Instructions", Format: "ldc\tRm,SR",
		Code: "0100mmmm00001110", SH1: true,
	})
	out := EmitInstrInfo(insns)
	// SR is fixed: literal in AsmString, not an operand, no extra bits
	if !strings.Contains(out, `let AsmString = "ldc\t${rm}, sr";`) {
		t.Errorf("fixed reg should be a lowercase literal:\n%s", out)
	}
	if !strings.Contains(out, "dag InOperandList = (ins GPR:$rm);") {
		t.Errorf("fixed reg must not appear as operand:\n%s", out)
	}
}

func TestEmitSizeAndDecoderNamespace(t *testing.T) {
	insns := build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov\tRm,Rn",
		Code: "0110nnnnmmmm0011", J2: true,
	})
	out := EmitInstrInfo(insns)
	if !strings.Contains(out, "let Size = 2;") {
		t.Errorf("missing Size for single-word insn:\n%s", out)
	}
	if !strings.Contains(out, `let DecoderNamespace = "SH";`) {
		t.Errorf("missing DecoderNamespace:\n%s", out)
	}
}

func TestEmitSizeTwoWord(t *testing.T) {
	insns := build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "movi20\t#imm20,Rn",
		Code: "0000nnnniiii0000 iiiiiiiiiiiiiiii", SH2A: true,
	})
	out := EmitInstrInfo(insns)
	if !strings.Contains(out, "let Size = 4;") {
		t.Errorf("missing Size=4 for two-word insn:\n%s", out)
	}
}

func TestEmitImmUsesSHImm(t *testing.T) {
	insns := build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov\t#imm,Rn",
		Code: "1110nnnniiiiiiii", SH1: true,
	})
	out := EmitInstrInfo(insns)
	if !strings.Contains(out, "SHImm:$imm") {
		t.Errorf("imm operand should use SHImm class:\n%s", out)
	}
	if strings.Contains(out, "i32imm") {
		t.Errorf("should not emit builtin i32imm:\n%s", out)
	}
}

func TestEmitFixedRegMemoryOperands(t *testing.T) {
	// movml.l Rm,@-R15 : MemPreDec with Fixed=R15 -> "@-r15", not "@-$<nul>"
	insns := build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "movml.l\tRm,@-R15",
		Code: "0100mmmm11110001", SH2A: true,
	})
	out := EmitInstrInfo(insns)
	if !strings.Contains(out, `@-r15`) {
		t.Errorf("expected @-r15 literal:\n%s", out)
	}
	if strings.Contains(out, "$\x00") || strings.Contains(out, "@-$;") {
		t.Errorf("malformed fixed-reg AsmString:\n%s", out)
	}
}

func TestEmitVariableBaseMemoryOperands(t *testing.T) {
	// pre-dec @-Rn -> MemDec operand, AsmString ${rn} (no @- literal)
	pd := build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov.l\tRm,@-Rn",
		Code: "0010nnnnmmmm0110", SH1: true,
	})
	out := EmitInstrInfo(pd)
	if !strings.Contains(out, "MemDec:$rn") {
		t.Errorf("pre-dec should use MemDec operand:\n%s", out)
	}
	if strings.Contains(out, "@-") {
		t.Errorf("@- decoration must move into the operand class, not AsmString:\n%s", out)
	}
	// indexed @(R0,Rm) -> MemR0Idx
	idx := build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov.l\t@(R0,Rm),Rn",
		Code: "0000nnnnmmmm1110", SH1: true,
	})
	if !strings.Contains(EmitInstrInfo(idx), "MemR0Idx:$rm") {
		t.Errorf("indexed should use MemR0Idx operand:\n%s", EmitInstrInfo(idx))
	}
	// fixed @-R15 stays literal text
	fx := build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "movml.l\tRm,@-R15",
		Code: "0100mmmm11110001", SH2A: true,
	})
	if !strings.Contains(EmitInstrInfo(fx), "@-r15") {
		t.Errorf("fixed @-R15 stays literal:\n%s", EmitInstrInfo(fx))
	}
}

func TestScaleOf(t *testing.T) {
	for m, want := range map[string]int{"mov.b": 1, "mov.w": 2, "mov.l": 4, "mova": 4} {
		if got := ScaleOf(m); got != want {
			t.Errorf("ScaleOf(%q)=%d want %d", m, got, want)
		}
	}
}

func TestEmitDispOperandClasses(t *testing.T) {
	// mov.l @(disp,Rm),Rn -> memdisp_l4 compound (base Rm + disp), dest Rn
	d := build(t, loader.RawInsn{Group: "Data Transfer Instructions",
		Format: "mov.l\t@(disp,Rm),Rn", Code: "0101nnnnmmmmdddd", SH1: true})
	out := EmitInstrInfo(d)
	if !strings.Contains(out, "memdisp_l4:$") {
		t.Errorf("expected memdisp_l4 operand:\n%s", out)
	}
	// mov.l @(disp,GBR),R0 -> gbrdisp_l8
	g := build(t, loader.RawInsn{Group: "Data Transfer Instructions",
		Format: "mov.l\t@(disp,GBR),R0", Code: "11000110dddddddd", SH1: true})
	if !strings.Contains(EmitInstrInfo(g), "gbrdisp_l8:$") {
		t.Errorf("expected gbrdisp_l8:\n%s", EmitInstrInfo(g))
	}
	// mov.l @(disp,PC),Rn -> pcdisp_l8
	p := build(t, loader.RawInsn{Group: "Data Transfer Instructions",
		Format: "mov.l\t@(disp,PC),Rn", Code: "1101nnnndddddddd", SH1: true})
	if !strings.Contains(EmitInstrInfo(p), "pcdisp_l8:$") {
		t.Errorf("expected pcdisp_l8:\n%s", EmitInstrInfo(p))
	}
}
