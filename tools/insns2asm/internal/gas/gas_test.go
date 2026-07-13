package gas

import (
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/loader"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/operand"
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
	if !strings.Contains(out, "arch_j2_up") {
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
	want := "HEX_0,REG_N,IMM0_4,HEX_0"
	if got != want {
		t.Errorf("nibbles = %q, want %q", got, want)
	}
}

func TestEmitDeltaLowercaseAndHexMacros(t *testing.T) {
	insns, err := ir.Build([]loader.RawInsn{
		{Group: "Data Transfer Instructions", Format: "cas.l\tRm, Rn, @R0", Code: "0010nnnnmmmm0011", J2: true},
		{Group: "System Control Instructions", Format: "bgnd", Code: "0000000000111011", J1: true, J2: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	out, err := EmitDelta(insns)
	if err != nil {
		t.Fatal(err)
	}
	wantCas := `{"cas.l",{A_REG_M,A_REG_N,A_IND_0,0},{HEX_2,REG_N,REG_M,HEX_3},arch_j2_up},`
	wantBgnd := `{"bgnd",{0},{HEX_0,HEX_0,HEX_3,HEX_B},arch_j2_up},`
	if !strings.Contains(out, wantCas) {
		t.Errorf("cas.l line wrong.\n got: %s\nwant substr: %s", out, wantCas)
	}
	if !strings.Contains(out, wantBgnd) {
		t.Errorf("bgnd line wrong.\n got: %s\nwant substr: %s", out, wantBgnd)
	}
	// No raw 0x nibble literals should remain in emitted lines.
	if strings.Contains(out, "0x") {
		t.Errorf("expected HEX_n macros, found raw 0x nibble:\n%s", out)
	}
}

func TestEmitDeltaLowercasesMnemonic(t *testing.T) {
	// insns.json carries some uppercase formats (e.g. STC PTEH); the gas table
	// mnemonic must be lowercase to match the assembler's parsing.
	insns, err := ir.Build([]loader.RawInsn{
		{Group: "System Control Instructions", Format: "STC PTEH, Rn", Code: "0000nnnn01010011", J2: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	out, err := EmitDelta(insns)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(out, `{"STC"`) {
		t.Errorf("mnemonic must be lowercased:\n%s", out)
	}
	if !strings.Contains(out, `{"stc"`) {
		t.Errorf("expected lowercase stc:\n%s", out)
	}
}

func TestEmitDeltaMMUForms(t *testing.T) {
	insns, err := ir.Build([]loader.RawInsn{
		{Group: "System Control Instructions", Format: "STC PTEH, Rn", Code: "0000nnnn01010011", J4: true},
		{Group: "System Control Instructions", Format: "STC PTEL, Rn", Code: "0000nnnn01100011", J4: true},
		{Group: "System Control Instructions", Format: "STC ASIDR, Rn", Code: "0000nnnn01110011", J4: true},
		{Group: "System Control Instructions", Format: "STC TSBPTR, Rn", Code: "0000nnnn01000011", J4: true},
		{Group: "System Control Instructions", Format: "LDTLB.RN", Code: "0000000001111000", J4: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	out, err := EmitDelta(insns)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{
		`{"stc",{A_PTEH,A_REG_N,0},{HEX_0,REG_N,HEX_5,HEX_3},arch_j4_up},`,
		`{"stc",{A_PTEL,A_REG_N,0},{HEX_0,REG_N,HEX_6,HEX_3},arch_j4_up},`,
		`{"stc",{A_ASIDR,A_REG_N,0},{HEX_0,REG_N,HEX_7,HEX_3},arch_j4_up},`,
		`{"stc",{A_TSBPTR,A_REG_N,0},{HEX_0,REG_N,HEX_4,HEX_3},arch_j4_up},`,
		`{"ldtlb.rn",{0},{HEX_0,HEX_0,HEX_7,HEX_8},arch_j4_up},`,
	}
	for _, w := range want {
		if !strings.Contains(out, w) {
			t.Errorf("missing emitted line:\n%s\nin:\n%s", w, out)
		}
	}
}

func TestArgCodeBranchAndSystemClasses(t *testing.T) {
	cases := []struct {
		o    operand.Operand
		want string
	}{
		{operand.Operand{Class: operand.BranchDisp, Letter: 'd', Width: 12}, "A_BDISP12"},
		{operand.Operand{Class: operand.BranchDisp, Letter: 'd', Width: 8}, "A_BDISP8"},
		{operand.Operand{Class: operand.BankReg, Letter: 'n'}, "A_REG_B"},
		{operand.Operand{Class: operand.MemTBRDisp, Letter: 'd', Width: 8}, "A_DISP_TBR"},
		{operand.Operand{Class: operand.FixedReg, Fixed: "SSR"}, "A_SSR"},
	}
	for _, c := range cases {
		got, err := argCode(c.o)
		if err != nil {
			t.Fatalf("%+v: %v", c.o, err)
		}
		if got != c.want {
			t.Errorf("argCode(%+v) = %q, want %q", c.o, got, c.want)
		}
	}
}
