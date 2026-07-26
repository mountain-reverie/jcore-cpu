package model

import (
	"testing"
)

// TestIllegalInstrPerVariant verifies per-variant illegal-instruction gating
// (model.BuildBody -> Body.IllegalInstr) entirely at the Go unit level,
// independent of the C-VHDL cosim environment.
// It builds the decoder model for base J2, J2A (sh2a overlay), and J4 (sh4
// overlay) and evaluates the generated check_illegal_instruction boolean
// expression against representative opcodes drawn from each ISA:
//
//   - 0x3211: SH-2A "MOV.L @(disp12,Rm),Rn" word1 (0011 nnnn mmmm 0001,
//     n=2,m=1) -- real instruction on J2A, must trap as illegal elsewhere.
//   - 0x0038: SH-4 LDTLB (0000 0000 0011 1000) -- real instruction on J4,
//     must trap as illegal elsewhere.
//   - 0x000B: RTS, 0x300C: ADD R0,R0 -- base J2 instructions, legal on
//     every variant.
func TestIllegalInstrPerVariant(t *testing.T) {
	const (
		sh2aWord1 = 0x3211 // SH-2A MOV.L @(disp12,Rm),Rn word1
		sh4LDTLB  = 0x0038 // SH-4 LDTLB
		rts       = 0x000B // base J2 RTS
		addR0R0   = 0x300C // base J2 ADD Rm,Rn
		ldcTBR    = 0x404A // SH-2A ldc Rm,TBR (0100 mmmm 0100 1010, m=0)
		stcTBR    = 0x004A // SH-2A stc TBR,Rn (0000 nnnn 0100 1010, n=0)
		jsrnAtTBR = 0x8300 // SH-2A jsr/n @@(disp8,TBR) (1000 0011 dddddddd)
	)

	build := func(t *testing.T, overlay string) *Decoder {
		t.Helper()
		_, d := buildIllegalVariant(t, overlay, 72, IllegalFull)
		if d.Body == nil {
			t.Fatal("Build did not produce a Body")
		}
		return d
	}

	evalIllegal := func(t *testing.T, d *Decoder, opcode uint16) bool {
		t.Helper()
		return d.Body.IllegalInstr.Eval(opcode)
	}

	base := build(t, "")
	j2a := build(t, "sh2a")
	j4 := build(t, "sh4")

	cases := []struct {
		variant string
		d       *Decoder
		opcode  uint16
		name    string
		want    bool
	}{
		{"base", base, sh2aWord1, "sh2a disp12 word1", true},
		{"base", base, sh4LDTLB, "sh4 LDTLB", true},
		{"base", base, rts, "RTS", false},
		{"base", base, addR0R0, "ADD R0,R0", false},

		{"base", base, ldcTBR, "ldc Rm,TBR", true},
		{"base", base, stcTBR, "stc TBR,Rn", true},
		{"base", base, jsrnAtTBR, "jsr/n @@(disp8,TBR)", true},

		{"j2a", j2a, sh2aWord1, "sh2a disp12 word1", false},
		{"j2a", j2a, sh4LDTLB, "sh4 LDTLB", true},
		{"j2a", j2a, ldcTBR, "ldc Rm,TBR", false},
		{"j2a", j2a, stcTBR, "stc TBR,Rn", false},
		{"j2a", j2a, jsrnAtTBR, "jsr/n @@(disp8,TBR)", false},

		{"j4", j4, sh2aWord1, "sh2a disp12 word1", true},
		{"j4", j4, sh4LDTLB, "sh4 LDTLB", false},
		{"j4", j4, ldcTBR, "ldc Rm,TBR", true},
		{"j4", j4, stcTBR, "stc TBR,Rn", true},
		{"j4", j4, jsrnAtTBR, "jsr/n @@(disp8,TBR)", true},
	}

	for _, c := range cases {
		got := evalIllegal(t, c.d, c.opcode)
		if got != c.want {
			t.Errorf("%s variant: check_illegal_instruction(%#04x %s) = %v, want %v",
				c.variant, c.opcode, c.name, got, c.want)
		}
	}
}
