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

func TestAugmentationsSharedJ4RegRegForms(t *testing.T) {
	insns, err := ir.Build([]loader.RawInsn{
		{Group: "System Control Instructions", Format: "ldc\tRm,SSR", Code: "0100mmmm00111110", SH3: true, SH4: true, SH4A: true, J4: true},
		{Group: "System Control Instructions", Format: "stc\tSSR,Rn", Code: "0000nnnn00110010", SH3: true, SH4: true, SH4A: true, J4: true},
		{Group: "System Control Instructions", Format: "ldc\tRm,Rn_BANK", Code: "0100mmmm1nnn1110", SH3: true, SH4: true, SH4A: true, J4: true},
		{Group: "System Control Instructions", Format: "stc\tRm_BANK,Rn", Code: "0000nnnn1mmm0010", SH3: true, SH4: true, SH4A: true, J4: true},
		// .l memory form: NOT J4, must not produce an augmentation.
		{Group: "System Control Instructions", Format: "ldc.l\t@Rm+,SSR", Code: "0100mmmm00110111", SH3: true, SH4: true, SH4A: true},
		// SGR: NOT J4, must not produce an augmentation.
		{Group: "System Control Instructions", Format: "stc\tSGR,Rn", Code: "0000nnnn00111010", SH4: true, SH4A: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	augs, err := Augmentations(insns)
	if err != nil {
		t.Fatal(err)
	}
	if len(augs) != 4 {
		t.Fatalf("expected 4 augmentations (SSR/BANK reg-reg ldc+stc), got %d: %+v", len(augs), augs)
	}
	for _, a := range augs {
		if a.Flag != "arch_j4_up" {
			t.Errorf("unexpected flag %q", a.Flag)
		}
		if a.Mnemonic == "ldc.l" || a.Mnemonic == "stc.l" {
			t.Errorf(".l form must not be augmented: %+v", a)
		}
	}
}

func TestApplyAugmentationsIsIdempotentAndOrsFlag(t *testing.T) {
	src := `const sh_opcode_info sh_table[] =
{
/* 0100nnnn00111110 ldc <REG_N>,SSR */{"ldc",{A_REG_N,A_SSR},{HEX_4,REG_N,HEX_3,HEX_E}, arch_sh3_nommu_up},
/* 0000nnnn00110010 stc SSR,<REG_N> */{"stc",{A_SSR,A_REG_N},{HEX_0,REG_N,HEX_3,HEX_2}, arch_sh3_nommu_up},
};
`
	augs := []Augmentation{
		{Mnemonic: "ldc", Nibbles: "HEX_4,REG_N,HEX_3,HEX_E", Flag: "arch_j4_up"},
		{Mnemonic: "stc", Nibbles: "HEX_0,REG_N,HEX_3,HEX_2", Flag: "arch_j4_up"},
	}
	out, changed, err := ApplyAugmentations(src, augs)
	if err != nil {
		t.Fatal(err)
	}
	if changed != 2 {
		t.Fatalf("expected 2 lines changed, got %d", changed)
	}
	if !strings.Contains(out, "arch_sh3_nommu_up|arch_j4_up},") {
		t.Errorf("arch mask not OR'd correctly:\n%s", out)
	}
	// Re-applying must be a no-op (idempotent).
	out2, changed2, err := ApplyAugmentations(out, augs)
	if err != nil {
		t.Fatal(err)
	}
	if changed2 != 0 {
		t.Errorf("re-applying augmentations should change 0 lines, changed %d", changed2)
	}
	if out2 != out {
		t.Errorf("re-applying augmentations should be a no-op")
	}
}

func TestApplyAugmentationsIgnoresRegisterNibbleLetter(t *testing.T) {
	// Upstream sh-opc.h conventionally names the sole register-field nibble
	// of ldc-to-control-register forms REG_N even when insns.json's mnemonic
	// calls the operand Rm (e.g. "ldc Rm,SSR"); the augmentation must still
	// match this line.
	src := `/* 0100mmmm00111110 ldc <REG_N>,SSR */{"ldc",{A_REG_N,A_SSR},{HEX_4,REG_N,HEX_3,HEX_E}, arch_sh3_nommu_up},
`
	augs := []Augmentation{{Mnemonic: "ldc", Nibbles: "HEX_4,REG_M,HEX_3,HEX_E", Flag: "arch_j4_up"}}
	out, changed, err := ApplyAugmentations(src, augs)
	if err != nil {
		t.Fatal(err)
	}
	if changed != 1 {
		t.Fatalf("expected 1 line changed, got %d:\n%s", changed, out)
	}
	if !strings.Contains(out, "arch_sh3_nommu_up|arch_j4_up") {
		t.Errorf("flag not applied:\n%s", out)
	}
}

func TestApplyAugmentationsUnmatchedIsError(t *testing.T) {
	src := "const sh_opcode_info sh_table[] =\n{\n};\n"
	_, _, err := ApplyAugmentations(src, []Augmentation{{Mnemonic: "ldc", Nibbles: "HEX_4,REG_N,HEX_3,HEX_E", Flag: "arch_j4_up"}})
	if err == nil {
		t.Error("expected error for unmatched augmentation")
	}
}

func TestEmitDeltaOrderingKeepsMnemonicGroupsContiguous(t *testing.T) {
	// Regression for the bug where a distinct mnemonic (ldtlb.rn) ended up
	// interleaved between stc entries once spliced into upstream sh-opc.h.
	insns, err := ir.Build([]loader.RawInsn{
		{Group: "System Control Instructions", Format: "STC PTEH, Rn", Code: "0000nnnn01010011", J4: true},
		{Group: "System Control Instructions", Format: "LDTLB.RN", Code: "0000000001111000", J4: true},
		{Group: "System Control Instructions", Format: "STC PTEL, Rn", Code: "0000nnnn01100011", J4: true},
		{Group: "System Control Instructions", Format: "STC ASIDR, Rn", Code: "0000nnnn01110011", J4: true},
	})
	if err != nil {
		t.Fatal(err)
	}
	out, err := EmitDelta(insns)
	if err != nil {
		t.Fatal(err)
	}
	stcFirst := strings.Index(out, `"stc"`)
	stcLast := strings.LastIndex(out, `"stc"`)
	ldtlbIdx := strings.Index(out, `"ldtlb.rn"`)
	if ldtlbIdx > stcFirst && ldtlbIdx < stcLast {
		t.Errorf("ldtlb.rn interleaved inside the stc group:\n%s", out)
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
