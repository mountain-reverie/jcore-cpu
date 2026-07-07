package microcode

import (
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestParseImm(t *testing.T) {
	cases := []struct {
		in   string
		want ImmVal
		ok   bool
	}{
		{"0", ImmVal{Kind: ImmNumeric, N: 0}, true},
		{"4", ImmVal{Kind: ImmNumeric, N: 4}, true},
		{"-16", ImmVal{Kind: ImmNumeric, N: -16}, true},
		{"u 8 2", ImmVal{Kind: ImmUnsigned, W: 8, S: 2}, true},
		{"[s 12 1]", ImmVal{Kind: ImmSigned, W: 12, S: 1}, true},
		{"", ImmVal{}, false},
		{"Rn", ImmVal{}, false},
	}
	for _, c := range cases {
		got, ok := ParseImm(c.in)
		if ok != c.ok || got != c.want {
			t.Errorf("ParseImm(%q)={%+v,%v}, want {%+v,%v}", c.in, got, ok, c.want, c.ok)
		}
	}
}

func TestParseImmToml(t *testing.T) {
	cases := []struct {
		format string
		in     string
		want   ImmVal
		ok     bool
	}{
		// Plain integers (format irrelevant)
		{"n", "0", ImmVal{Kind: ImmNumeric, N: 0}, true},
		{"n", "4", ImmVal{Kind: ImmNumeric, N: 4}, true},
		{"n", "-16", ImmVal{Kind: ImmNumeric, N: -16}, true},
		// Structured: no multiplier → shift=0
		{"nd4", "U", ImmVal{Kind: ImmUnsigned, W: 4, S: 0}, true},
		{"i8", "U", ImmVal{Kind: ImmUnsigned, W: 8, S: 0}, true},
		{"ni", "S", ImmVal{Kind: ImmSigned, W: 8, S: 0}, true},
		// Structured: U*2 → shift=1
		{"nd4", "U*2", ImmVal{Kind: ImmUnsigned, W: 4, S: 1}, true},
		{"d8", "U*2", ImmVal{Kind: ImmUnsigned, W: 8, S: 1}, true},
		{"d8", "S*2", ImmVal{Kind: ImmSigned, W: 8, S: 1}, true},
		// Structured: U*4 → shift=2
		{"nmd", "U*4", ImmVal{Kind: ImmUnsigned, W: 4, S: 2}, true},
		{"d8", "U*4", ImmVal{Kind: ImmUnsigned, W: 8, S: 2}, true},
		// d12 + S*2 → [s 12 1]
		{"d12", "S*2", ImmVal{Kind: ImmSigned, W: 12, S: 1}, true},
		// Register name → not an immediate
		{"n", "Rn", ImmVal{}, false},
		{"n", "GBR", ImmVal{}, false},
		// Empty → not an immediate
		{"n", "", ImmVal{}, false},
		// U without a valid format → ok=false
		{"n", "U", ImmVal{}, false},
	}
	for _, c := range cases {
		got, ok := ParseImmToml(c.format, c.in)
		if ok != c.ok || got != c.want {
			t.Errorf("ParseImmToml(%q, %q)={%+v,%v}, want {%+v,%v}",
				c.format, c.in, got, ok, c.want, c.ok)
		}
	}
}

func TestImmValLiteral(t *testing.T) {
	cases := map[string]ImmVal{
		"IMM_ZERO":   {Kind: ImmNumeric, N: 0},
		"IMM_P4":     {Kind: ImmNumeric, N: 4},
		"IMM_N16":    {Kind: ImmNumeric, N: -16},
		"IMM_U_8_2":  {Kind: ImmUnsigned, W: 8, S: 2},
		"IMM_S_12_1": {Kind: ImmSigned, W: 12, S: 1},
	}
	for want, in := range cases {
		if got := in.Literal(); got != want {
			t.Errorf("%+v.Literal() = %q, want %q", in, got, want)
		}
	}
}

// TestImmLiteralToVHDL covers every branch of ImmLiteralToVHDL, including
// the unrecognized-literal fallthrough that returns "".
func TestImmLiteralToVHDL(t *testing.T) {
	cases := []struct {
		lit  string
		want string
	}{
		// Numeric constants — fixed hex vectors.
		{"IMM_ZERO", `x"00000000"`},
		{"IMM_P1", `x"00000001"`},
		{"IMM_P2", `x"00000002"`},
		{"IMM_P4", `x"00000004"`},
		{"IMM_P8", `x"00000008"`},
		{"IMM_P16", `x"00000010"`},
		{"IMM_N1", `x"ffffffff"`},
		{"IMM_N2", `x"fffffffe"`},
		{"IMM_N8", `x"fffffff8"`},
		{"IMM_N16", `x"fffffff0"`},
		// Unsigned opcode-field extractions.
		{"IMM_U_4_0", `x"0000000" & op.code(3 downto 0)`},
		{"IMM_U_4_1", `"000000000000000000000000000" & op.code(3 downto 0) & "0"`},
		{"IMM_U_4_2", `"00000000000000000000000000" & op.code(3 downto 0) & "00"`},
		{"IMM_U_8_0", `x"000000" & op.code(7 downto 0)`},
		{"IMM_U_8_1", `"00000000000000000000000" & op.code(7 downto 0) & "0"`},
		{"IMM_U_8_2", `"0000000000000000000000" & op.code(7 downto 0) & "00"`},
		// Sign-extended named signals.
		{"IMM_S_8_0", "imms_8_0"},
		{"IMM_S_8_1", "imms_8_1"},
		{"IMM_S_12_1", "imms_12_1"},
		// General numeric constants — any IMM_P<N>/IMM_N<N> expands to a
		// 32-bit hex vector via the numeric fallback (not just the
		// predefined ±{1,2,4,8,16}). The predefined cases above remain
		// byte-identical to what the fallback would produce.
		{"IMM_P3", `x"00000003"`},    // not in the explicit switch
		{"IMM_P256", `x"00000100"`},  // 0x100 — PM3 fixed-vector offset
		{"IMM_P352", `x"00000160"`},  // 0x160 — PM3 EXPEVT code
		{"IMM_P1536", `x"00000600"`}, // 0x600 — PM3 fixed-vector offset
		{"IMM_N256", `x"ffffff00"`},  // -256 two's complement
		// Unrecognized / non-numeric literals must return the empty string.
		{"", ""},
		{"IMM_UNKNOWN", ""},
		{"imm_zero", ""},   // case-sensitive
		{"IMM_U_4_3", ""},  // structured, not numeric — stays empty
		{"IMM_S_16_0", ""}, // structured, not numeric — stays empty
		{"IMM_PXYZ", ""},   // IMM_P prefix but non-numeric tail — stays empty
		{"IMM_N", ""},      // empty numeric tail — stays empty
	}
	for _, c := range cases {
		got := ImmLiteralToVHDL(c.lit)
		if got != c.want {
			t.Errorf("ImmLiteralToVHDL(%q) = %q, want %q", c.lit, got, c.want)
		}
	}
}

// TestImmLiteralToVHDL_TotalOverCollected asserts that ImmLiteralToVHDL is
// total over every immval_t literal that CollectImmVals can produce for the
// production spec AND the J4 (sh4) overlay profile. Any literal that expands
// to "" would make the direct decoder emit a bare enum into a
// std_logic_vector context, which fails to elaborate. This invariant guards
// the whole class at go-test speed (no GHDL needed): adding a microcode
// immediate the expander can't represent fails here immediately.
func TestImmLiteralToVHDL_TotalOverCollected(t *testing.T) {
	profiles := []struct {
		name     string
		overlays []string
	}{
		{"production", nil},
		{"j4", []string{"../../spec/sh4"}},
	}
	for _, p := range profiles {
		s, err := spec.LoadProfile("../../spec", p.overlays...)
		if err != nil {
			t.Fatalf("LoadProfile(%s): %v", p.name, err)
		}
		for _, iv := range CollectImmVals(s) {
			lit := iv.Literal()
			if ImmLiteralToVHDL(lit) == "" {
				t.Errorf("[%s] ImmLiteralToVHDL(%q) is empty — direct decoder will not elaborate", p.name, lit)
			}
		}
	}
}

func TestCollectImmValsProduction(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	got := CollectImmVals(s)
	var lits []string
	for _, v := range got {
		lits = append(lits, v.Literal())
	}
	// Production spec must produce exactly the 19 literals committed
	// in decode/decode_pkg.vhd line 21, in the canonical order.
	want := "IMM_ZERO,IMM_P1,IMM_P2,IMM_P4,IMM_P8,IMM_P16,IMM_N16,IMM_N8,IMM_N2,IMM_N1,IMM_U_4_0,IMM_U_4_1,IMM_U_4_2,IMM_U_8_0,IMM_U_8_1,IMM_U_8_2,IMM_S_8_1,IMM_S_12_1,IMM_S_8_0"
	if strings.Join(lits, ",") != want {
		t.Errorf("got  %v\nwant %v", lits, strings.Split(want, ","))
	}
}

func TestExtWordImmVHDL(t *testing.T) {
	if got := ImmLiteralToVHDL("IMM_U_12_0"); got != `x"00000" & ext_word(11 downto 0)` {
		t.Errorf("disp12 VHDL = %q", got)
	}
	// movi20: imm20 = op.code(11..8) (high 4) & ext_word(15..0) (low 16), sign-extended from bit 19
	got := ImmLiteralToVHDL("IMM_S_20_0")
	if !strings.Contains(got, "op.code(11 downto 8)") || !strings.Contains(got, "ext_word(15 downto 0)") {
		t.Errorf("imm20 VHDL = %q", got)
	}
}
