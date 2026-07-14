package emit

import (
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
)

func TestHex16(t *testing.T) {
	cases := map[uint16]string{
		0x0008: "0x8",
		0x300c: "0x300c",
		0xffff: "0xffff",
		0x0000: "0x0",
	}
	for in, want := range cases {
		if got := hex16(in); got != want {
			t.Errorf("hex16(%#x)=%q, want %q", in, got, want)
		}
	}
}

func TestFormatString(t *testing.T) {
	cases := []struct {
		name, format, want string
	}{
		{"CLRT", "0", "CLRT"},
		{"ADD Rm, Rn", "nm", "ADD R%hu, R%hu"},
		{"MOVT Rn", "n", "MOVT R%hu"},
		{"BF label", "d8", "BF label"},
		{"MOV.B Rm, @(R0, Rn)", "nm", "MOV.B R%hu, @(R0, R%hu)"},
	}
	for _, c := range cases {
		if got := formatString(c.name, c.format); got != c.want {
			t.Errorf("formatString(%q,%q)=%q, want %q", c.name, c.format, got, c.want)
		}
	}
}

func TestRegisterArgs(t *testing.T) {
	cases := []struct {
		name, format, want string
	}{
		{"CLRT", "0", ""},
		{"MOVT Rn", "n", ", (uint16_t)((instr >> 8) & 0xF)"},
		{"BSRF Rm", "m", ", (uint16_t)((instr >> 8) & 0xF)"},
		{"ADD Rm, Rn", "nm", ", (uint16_t)((instr >> 4) & 0xF), (uint16_t)((instr >> 8) & 0xF)"},
		{"MOV.B Rm, @(R0, Rn)", "nm", ", (uint16_t)((instr >> 4) & 0xF), (uint16_t)((instr >> 8) & 0xF)"},
		{"MOV.B R0, @(disp, Rn)", "nd4", ", (uint16_t)((instr >> 4) & 0xF)"},
		{"MOV.L Rn, @(disp, GBR)", "nd8", ", (uint16_t)((instr >> 8) & 0xF)"},
		{"MOV.B @(disp, Rm), R0", "md", ", (uint16_t)((instr >> 4) & 0xF)"},
		{"MOV #imm, Rn", "i8", ""},
	}
	for _, c := range cases {
		instr := model.Instruction{Name: c.name, Format: c.format}
		if got := registerArgs(instr); got != c.want {
			t.Errorf("registerArgs(%q,%q)=%q, want %q", c.name, c.format, got, c.want)
		}
	}
}

func TestRegisterExprNi3(t *testing.T) {
	if got := registerExpr("ni3", "Rn"); got != "(instr >> 8) & 0xF" {
		t.Errorf("registerExpr(\"ni3\",\"Rn\") = %q, want %q", got, "(instr >> 8) & 0xF")
	}
}
