package main

import "testing"

func TestCategorize(t *testing.T) {
	cases := map[string]string{
		"ADD":     "arithmetic",
		"SUB":     "arithmetic",
		"NEG":     "arithmetic",
		"AND":     "logic",
		"NOT":     "logic",
		"SHAL":    "shift",
		"ROTCR":   "shift",
		"MUL":     "multiply",
		"MAC.W":   "multiply",
		"DIV1":    "divide",
		"DIV0S":   "divide",
		"MOV":     "mov",
		"MOV.L":   "mov",
		"BF":      "branch",
		"BSR":     "branch",
		"RTE":     "branch",
		"CMP/EQ":  "compare",
		"TAS":     "compare",
		"NOP":     "system",
		"CLRT":    "system",
		"LDC":     "system",
		"TRAPA":   "system",
		"AINT":    "system",
		// real CSV names carry operand text after a space
		"ADD Rm, Rn":      "arithmetic",
		"BSRF Rm":         "branch",
		"MOVT Rn":         "mov",
		"AND Rm, Rn":      "logic",
		"CMP /STR Rm, Rn": "compare",
		"SHAL Rn":         "shift",
		"DIV0S Rm, Rn":    "divide",
	}
	for in, want := range cases {
		t.Run(in, func(t *testing.T) {
			if got := categoryFor(in); got != want {
				t.Errorf("category(%q)=%q, want %q", in, got, want)
			}
		})
	}
}
