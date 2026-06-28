package sel

import (
	"testing"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/loader"
)

func build(t *testing.T, raw loader.RawInsn) ir.Insn {
	t.Helper()
	is, err := ir.Build([]loader.RawInsn{raw})
	if err != nil {
		t.Fatal(err)
	}
	return is[0]
}

func TestIs1aSimpleAcceptsRegImmIndirect(t *testing.T) {
	for _, r := range []loader.RawInsn{
		{Group: "Data Transfer Instructions", Format: "mov\tRm,Rn", Code: "0110nnnnmmmm0011", SH1: true},
		{Group: "Data Transfer Instructions", Format: "mov\t#imm,Rn", Code: "1110nnnniiiiiiii", SH1: true},
		{Group: "Data Transfer Instructions", Format: "mov.l\t@Rm+,Rn", Code: "0110nnnnmmmm0110", SH1: true},
	} {
		if !Is1aSimple(build(t, r)) {
			t.Errorf("should be 1a-simple: %s", r.Format)
		}
	}
}

func TestIs1aSimpleRejectsTwoWord(t *testing.T) {
	for _, r := range []loader.RawInsn{
		{Group: "Data Transfer Instructions", Format: "movi20\t#imm20,Rn", Code: "0000nnnniiii0000 iiiiiiiiiiiiiiii", SH2A: true}, // two-word
	} {
		if Is1aSimple(build(t, r)) {
			t.Errorf("should NOT be 1a-simple: %s", r.Format)
		}
	}
}

func TestIs1aSimpleRejectsNonGPIntegerGroup(t *testing.T) {
	// jmp @Rm: simple operand (MemReg), single-word, but Branch group -> excluded.
	in := build(t, loader.RawInsn{
		Group: "Branch Instructions", Format: "jmp\t@Rm", Code: "0100mmmm00101011", SH1: true,
	})
	if Is1aSimple(in) {
		t.Error("jmp @Rm is Branch group, must not be 1a-simple")
	}
}

func TestIs1aSimpleAcceptsRegisterOnlyMemory(t *testing.T) {
	for _, r := range []loader.RawInsn{
		{Group: "Data Transfer Instructions", Format: "mov.l\tRm,@-Rn", Code: "0010nnnnmmmm0110", SH1: true},
		{Group: "Data Transfer Instructions", Format: "mov.l\t@(R0,Rm),Rn", Code: "0000nnnnmmmm1110", SH1: true},
		{Group: "Bit Manipulation Instructions", Format: "and.b\t#imm,@(R0,GBR)", Code: "11001101iiiiiiii", SH1: true},
	} {
		if !Is1aSimple(build(t, r)) {
			t.Errorf("should now be supported: %s", r.Format)
		}
	}
}

func TestIs1aSimpleRejectsFixedMemAndTwoWord(t *testing.T) {
	for _, r := range []loader.RawInsn{
		{Group: "Data Transfer Instructions", Format: "movi20\t#imm20,Rn", Code: "0000nnnniiii0000 iiiiiiiiiiiiiiii", SH2A: true},
	} {
		if Is1aSimple(build(t, r)) {
			t.Errorf("should be deferred to 1b, not 1a: %s", r.Format)
		}
	}
}

func TestIs1aSimpleAcceptsFixedRegMem(t *testing.T) {
	for _, r := range []loader.RawInsn{
		{Group: "Data Transfer Instructions", Format: "movml.l\tRm,@-R15", Code: "0100mmmm11110001", SH2A: true},
		{Group: "Data Transfer Instructions", Format: "movml.l\t@R15+,Rn", Code: "0100nnnn11110101", SH2A: true},
		{Group: "Data Transfer Instructions", Format: "cas.l\tRm,Rn,@R0", Code: "0010nnnnmmmm0011", SH4A: true},
	} {
		if !Is1aSimple(build(t, r)) {
			t.Errorf("fixed-reg mem should now be supported: %s", r.Format)
		}
	}
}

func TestIs1aSimpleAcceptsDispOperands(t *testing.T) {
	for _, r := range []loader.RawInsn{
		{Group: "Data Transfer Instructions", Format: "mov.l\t@(disp,Rm),Rn", Code: "0101nnnnmmmmdddd", SH1: true},
		{Group: "Data Transfer Instructions", Format: "mov.l\t@(disp,GBR),R0", Code: "11000110dddddddd", SH1: true},
		{Group: "Data Transfer Instructions", Format: "mov.l\t@(disp,PC),Rn", Code: "1101nnnndddddddd", SH1: true},
	} {
		if !Is1aSimple(build(t, r)) {
			t.Errorf("should be 1a-simple: %s", r.Format)
		}
	}
}

func TestIs1aSimpleRejectsDisp12TwoWord(t *testing.T) {
	// disp12 two-word form should stay rejected
	if Is1aSimple(build(t, loader.RawInsn{Group: "Data Transfer Instructions",
		Format: "mov.l\t@(disp12,Rm),Rn", Code: "0011nnnnmmmm0001 0110dddddddddddd", SH2A: true})) {
		t.Error("disp12 two-word should be rejected (1a single-word only)")
	}
}
