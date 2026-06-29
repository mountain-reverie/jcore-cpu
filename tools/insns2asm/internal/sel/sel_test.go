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

func TestIs1aSimpleAcceptsTwoWord(t *testing.T) {
	for _, r := range []loader.RawInsn{
		{Group: "Data Transfer Instructions", Format: "movi20\t#imm20,Rn", Code: "0000nnnniiii0000 iiiiiiiiiiiiiiii", SH2A: true},
		{Group: "Data Transfer Instructions", Format: "mov.l\t@(disp12,Rm),Rn", Code: "0011nnnnmmmm0001 0110dddddddddddd", SH2A: true},
		{Group: "Bit Manipulation Instructions", Format: "bclr.b\t#imm3,@(disp12,Rn)", Code: "0011nnnn0iii1001 0000dddddddddddd", SH2A: true},
	} {
		if !Is1aSimple(build(t, r)) {
			t.Errorf("two-word should now be supported: %s", r.Format)
		}
	}
}

func TestIs1aSimpleRejectsNonGPIntegerGroup(t *testing.T) {
	// setrc: System Control insn not in any allow-list, must be rejected.
	in := build(t, loader.RawInsn{
		Group: "System Control Instructions", Format: "setrc\tRn", Code: "0100mmmm00010100", SH2A: true,
	})
	if Is1aSimple(in) {
		t.Error("setrc is out-of-scope System Control, must not be 1a-simple")
	}
}

func TestSelectsBranchGroup(t *testing.T) {
	cases := []struct {
		name string
		raw  loader.RawInsn
	}{
		{"bra", loader.RawInsn{Group: "Branch Instructions", Format: "bra\tlabel", Code: "1010dddddddddddd", J2: true}},
		{"bt", loader.RawInsn{Group: "Branch Instructions", Format: "bt\tlabel", Code: "10001001dddddddd", J2: true}},
		{"jmp", loader.RawInsn{Group: "Branch Instructions", Format: "jmp\t@Rm", Code: "0100mmmm00101011", J2: true}},
		{"braf", loader.RawInsn{Group: "Branch Instructions", Format: "braf\tRm", Code: "0000mmmm00100011", J2: true}},
		{"rts", loader.RawInsn{Group: "Branch Instructions", Format: "rts", Code: "0000000000001011", J2: true}},
		{"rte", loader.RawInsn{Group: "System Control Instructions", Format: "rte", Code: "0000000000101011", J2: true}},
	}
	for _, c := range cases {
		insns, err := ir.Build([]loader.RawInsn{c.raw})
		if err != nil {
			t.Fatalf("%s: build: %v", c.name, err)
		}
		if !Is1aSimple(insns[0]) {
			t.Errorf("%s should be selected", c.name)
		}
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

func TestSelectsSystemControl(t *testing.T) {
	accept := []loader.RawInsn{
		{Group: "System Control Instructions", Format: "nop", Code: "0000000000001001", J2: true},
		{Group: "System Control Instructions", Format: "trapa\t#imm", Code: "11000011iiiiiiii", J2: true},
		{Group: "System Control Instructions", Format: "ldc\tRm,SR", Code: "0100mmmm00001110", J2: true},
		{Group: "System Control Instructions", Format: "stc\tSSR,Rn", Code: "0000nnnn00110010", J2: true},
		{Group: "System Control Instructions", Format: "ldc.l\t@Rm+,SPC", Code: "0100mmmm01000111", J2: true},
		{Group: "System Control Instructions", Format: "stc\tGBR,Rn", Code: "0000nnnn00010010", J2: true},
		{Group: "System Control Instructions", Format: "lds\tRm,PR", Code: "0100mmmm00101010", J2: true},
		{Group: "System Control Instructions", Format: "ldc\tRm,Rn_BANK", Code: "0100mmmm1nnn1110", J2: true},
		{Group: "System Control Instructions", Format: "stc\tRm_BANK,Rn", Code: "0000nnnn1mmm0010", J2: true},
		{Group: "System Control Instructions", Format: "ldc\tRm,TBR", Code: "0100mmmm01001010", SH2A: true},
		{Group: "System Control Instructions", Format: "pref\t@Rn", Code: "0000nnnn10000011", SH2A: true},
		{Group: "System Control Instructions", Format: "resbank", Code: "0000000001011011", SH2A: true},
	}
	for _, raw := range accept {
		insns, err := ir.Build([]loader.RawInsn{raw})
		if err != nil {
			t.Fatalf("%s: build: %v", raw.Format, err)
		}
		if !Is1aSimple(insns[0]) {
			t.Errorf("should be selected: %s", raw.Format)
		}
	}
}

func TestSystemCoverage(t *testing.T) {
	// SH3/SH4/SH4A no-operand and cache-op system instructions must be selected.
	accept := []loader.RawInsn{
		{Group: "System Control Instructions", Format: "clrs", Code: "0000000001001000", SH3: true},
		{Group: "System Control Instructions", Format: "sets", Code: "0000000001011000", SH3: true},
		{Group: "System Control Instructions", Format: "synco", Code: "0000000010101011", SH4A: true},
		{Group: "System Control Instructions", Format: "ldtbl", Code: "0000000000111000", SH4: true},
		{Group: "System Control Instructions", Format: "icbi\t@Rn", Code: "0000nnnn11100011", SH4A: true},
		{Group: "System Control Instructions", Format: "ocbi\t@Rn", Code: "0000nnnn10010011", SH4: true},
		{Group: "System Control Instructions", Format: "ocbp\t@Rn", Code: "0000nnnn10100011", SH4: true},
		{Group: "System Control Instructions", Format: "ocbwb\t@Rn", Code: "0000nnnn10110011", SH4: true},
		{Group: "System Control Instructions", Format: "prefi\t@Rn", Code: "0000nnnn11010011", SH4A: true},
		{Group: "System Control Instructions", Format: "movca.l\tR0,@Rn", Code: "0000nnnn11000011", SH4: true},
	}
	for _, raw := range accept {
		insns, err := ir.Build([]loader.RawInsn{raw})
		if err != nil {
			t.Fatalf("%s: build: %v", raw.Format, err)
		}
		if !Is1aSimple(insns[0]) {
			t.Errorf("should be selected: %s", raw.Format)
		}
	}
}

func TestRejectsOutOfScopeSystemControl(t *testing.T) {
	reject := []loader.RawInsn{
		{Group: "System Control Instructions", Format: "ldc\tRm,SGR", Code: "0100mmmm00111010", SH2A: true},
		{Group: "System Control Instructions", Format: "ldc\tRm,DBR", Code: "0100mmmm11111010", SH2A: true},
		{Group: "System Control Instructions", Format: "setrc\tRn", Code: "0100mmmm00010100", SH2A: true},
	}
	for _, raw := range reject {
		insns, err := ir.Build([]loader.RawInsn{raw})
		if err != nil {
			t.Fatalf("%s: build: %v", raw.Format, err)
		}
		if Is1aSimple(insns[0]) {
			t.Errorf("should be rejected: %s", raw.Format)
		}
	}
}

func TestFPSelected(t *testing.T) {
	accept := []loader.RawInsn{
		{Group: "Floating-Point Single-Precision Instructions (FPSCR.PR = 0)", Format: "fadd\tFRm,FRn", Code: "1111nnnnmmmm0000", SH4: true},
		{Group: "32 Bit Floating-Point Data Transfer Instructions (FPSCR.SZ = 0)", Format: "fmov.s\t@Rm,FRn", Code: "1111nnnnmmmm1000", SH4: true},
		{Group: "Floating-Point Single-Precision Instructions (FPSCR.PR = 0)", Format: "fmac\tFR0,FRm,FRn", Code: "1111nnnnmmmm1110", SH4: true},
		{Group: "Floating-Point Control Instructions", Format: "flds\tFRm,FPUL", Code: "1111mmmm00011101", SH4: true},
		{Group: "Floating-Point Control Instructions", Format: "lds\tRm,FPSCR", Code: "0100mmmm01101010", SH4: true},
		{Group: "Floating-Point Control Instructions", Format: "frchg", Code: "1111101111111101", SH4: true},
	}
	for _, raw := range accept {
		in := build(t, raw)
		if !Is1aSimple(in) {
			t.Errorf("should be FP-selected: %s", raw.Format)
		}
	}

	// fipr and ftrv are no longer deferred; they must now be accepted.
	nowAccept := []loader.RawInsn{
		{Group: "Floating-Point Single-Precision Instructions (FPSCR.PR = 0)", Format: "fipr\tFVm,FVn", Code: "1111nnnnmmmm0001", SH4: true},
		{Group: "Floating-Point Single-Precision Instructions (FPSCR.PR = 0)", Format: "ftrv\tXMTRX,FVn", Code: "1111nnnn00000001", SH4: true},
	}
	for _, raw := range nowAccept {
		in := build(t, raw)
		if !Is1aSimple(in) {
			t.Errorf("should now be FP-selected (3c): %s", raw.Format)
		}
	}
}

func TestDoublePrecisionFPSelected(t *testing.T) {
	accept := []loader.RawInsn{
		{Group: "Floating-Point Double-Precision Instructions (FPSCR.PR = 1)", Format: "fadd\tDRm,DRn", Code: "1111nnn0mmm00000", SH4: true},
		{Group: "64 Bit Floating-Point Data Transfer Instructions (FPSCR.SZ = 1)", Format: "fmov.d\t@Rm,DRn", Code: "1111nnn0mmmm1000", SH4: true},
		{Group: "64 Bit Floating-Point Data Transfer Instructions (FPSCR.SZ = 1)", Format: "fmov\tDRm,XDn", Code: "1111nnn1mmm01100", SH4: true},
		{Group: "Floating-Point Double-Precision Instructions (FPSCR.PR = 1)", Format: "fcnvsd\tFPUL,DRn", Code: "1111nnn010101101", SH4: true},
		{Group: "Floating-Point Single-Precision Instructions (FPSCR.PR = 0)", Format: "fsca\tFPUL,DRn", Code: "1111nnn011111101", SH4: true},
	}
	for _, raw := range accept {
		in := build(t, raw)
		if !Is1aSimple(in) {
			t.Errorf("should be double-FP-selected: %s", raw.Format)
		}
	}

	// fipr is no longer deferred; it is accepted regardless of operand shape.
	// (Previously rejected when fipr was in fpDeferMnemonics.)
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

