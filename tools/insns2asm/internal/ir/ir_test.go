package ir

import (
	"testing"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/loader"
)

func TestBuildMov(t *testing.T) {
	raw := []loader.RawInsn{{
		Group: "Data Transfer Instructions", Format: "mov\tRm,Rn",
		Code: "0110nnnnmmmm0011", J2: true, SH1: true,
	}}
	got, err := Build(raw)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 {
		t.Fatalf("want 1 insn, got %d", len(got))
	}
	in := got[0]
	if in.Mnemonic != "mov" || len(in.Operands) != 2 {
		t.Errorf("mnemonic/operands wrong: %+v", in)
	}
	if f, ok := in.FieldFor('n'); !ok || f.Hi != 11 || f.Lo != 8 {
		t.Errorf("n field: %+v ok=%v", f, ok)
	}
	if !in.Arch.SH1 || !in.Arch.J2 {
		t.Errorf("arch wrong: %+v", in.Arch)
	}
}

func TestBuildUnmappedOperandErrors(t *testing.T) {
	// FRm/FRn/DRm/DRn/FVm/FVn are now valid FP operand tokens; use a truly unknown token.
	raw := []loader.RawInsn{{
		Group: "Data Transfer Instructions", Format: "fmov\tZZZunk,FRn",
		Code: "1111nnnnmmmm1100", SH4: true,
	}}
	if _, err := Build(raw); err == nil {
		t.Error("want error for unmapped ZZZunk operand")
	}
}

func TestBuildPopulatesOperandWidth(t *testing.T) {
	raw := []loader.RawInsn{{
		Group: "Data Transfer Instructions", Format: "mov\t#imm,Rn",
		Code: "1110nnnniiiiiiii", SH1: true,
	}}
	got, err := Build(raw)
	if err != nil {
		t.Fatal(err)
	}
	in := got[0]
	// operands: #imm (i, 8 bits), Rn (n, 4 bits)
	if in.Operands[0].Width != 8 {
		t.Errorf("#imm width = %d, want 8", in.Operands[0].Width)
	}
	if in.Operands[1].Width != 4 {
		t.Errorf("Rn width = %d, want 4", in.Operands[1].Width)
	}
}

func TestBuildSumsSplitFieldWidth(t *testing.T) {
	got, err := Build([]loader.RawInsn{{
		Group: "Data Transfer Instructions", Format: "movi20\t#imm20,Rn",
		Code: "0000nnnniiii0000 iiiiiiiiiiiiiiii", SH2A: true,
	}})
	if err != nil {
		t.Fatal(err)
	}
	// operand 0 is #imm20: i-field split 4 (word0) + 16 (word1) = 20
	if got[0].Operands[0].Width != 20 {
		t.Errorf("imm20 width = %d, want 20", got[0].Operands[0].Width)
	}
}
