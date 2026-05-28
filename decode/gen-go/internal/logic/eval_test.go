package logic

import "testing"

// codeResolver returns bit `bit` of `opcode` when sig=="code", and
// always 0 for sig=="p" (plane). Mirrors the body-evaluator helper.
func codeResolver(opcode uint16) SigValue {
	return func(sig string, bit int) int {
		switch sig {
		case "code":
			return int((opcode >> bit) & 1)
		case "p":
			return 0
		}
		return 0
	}
}

func TestEvalBoolExprSimple(t *testing.T) {
	tests := []struct {
		expr   string
		opcode uint16
		want   bool
	}{
		{`code(0) = '1'`, 0x0001, true},
		{`code(0) = '1'`, 0x0000, false},
		{`code(0) = '0'`, 0x0000, true},
		{`(code(0) = '0' and code(1) = '0')`, 0x0000, true},
		{`(code(0) = '0' and code(1) = '0')`, 0x0001, false},
		{`(code(0) = '1' or code(1) = '1')`, 0x0001, true},
		{`(code(0) = '1' or code(1) = '1')`, 0x0000, false},
		{`not (code(0) = '1')`, 0x0001, false},
		{`not (code(0) = '1')`, 0x0000, true},
		{`'1'`, 0x0000, true},
		{`'0'`, 0x0000, false},
		// AND binds tighter than OR.
		{`code(0) = '1' or code(1) = '1' and code(2) = '1'`, 0x0001, true},
		{`code(0) = '1' or code(1) = '1' and code(2) = '1'`, 0x0006, true}, // 110 → AND wins
		{`code(0) = '1' or code(1) = '1' and code(2) = '1'`, 0x0002, false}, // bit1=1 bit2=0
	}
	for _, c := range tests {
		got, err := EvalBoolExpr(c.expr, codeResolver(c.opcode))
		if err != nil {
			t.Errorf("EvalBoolExpr(%q, %04x): %v", c.expr, c.opcode, err)
			continue
		}
		if got != c.want {
			t.Errorf("EvalBoolExpr(%q, %04x) = %v, want %v", c.expr, c.opcode, got, c.want)
		}
	}
}

func TestEvalBoolExprMalformed(t *testing.T) {
	cases := []string{
		`code(0 = '1'`,   // missing )
		`(code(0) = '1'`, // missing closing )
		`xyz`,            // junk
		``,               // empty
		// `code(0)` alone is now VALID — bare bit ref, true iff bit=1.
	}
	r := codeResolver(0)
	for _, c := range cases {
		if _, err := EvalBoolExpr(c, r); err == nil {
			t.Errorf("EvalBoolExpr(%q) accepted malformed input", c)
		}
	}
}
