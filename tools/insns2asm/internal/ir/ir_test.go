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
	raw := []loader.RawInsn{{
		Group: "Data Transfer Instructions", Format: "fmov\tFRm,FRn",
		Code: "1111nnnnmmmm1100", SH4: true,
	}}
	if _, err := Build(raw); err == nil {
		t.Error("want error for unmapped FRm operand")
	}
}
