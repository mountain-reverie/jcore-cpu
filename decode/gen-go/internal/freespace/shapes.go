package freespace

import (
	"sort"
	"strings"
)

// shapes maps a canonical operand shape to the 16-bit pattern its operands
// occupy. Field characters follow opcode.Parse: 'n' destination register,
// 'm' source register, 'd' displacement, 'i' immediate. '-' marks a bit the
// search is free to assign.
//
// These are the layouts the SH-2 encoding already uses; the search does not
// invent new field placements, because the decoder's field extraction is
// hard-wired to these positions.
var shapes = map[string]string{
	"rm,rn":        "----nnnnmmmm----",
	"rn":           "----nnnn--------",
	"rm":           "----mmmm--------",
	"#imm8":        "--------iiiiiiii",
	"#imm8,r0":     "--------iiiiiiii",
	"#imm8,rn":     "----nnnniiiiiiii",
	"#imm4,rn":     "----nnnniiii----",
	"@(disp4,rn)":  "----nnnndddd----",
	"@(disp8,pc)":  "--------dddddddd",
	"@(disp12,rm)": "----nnnnmmmm----",
	"@rn":          "----nnnn--------",
	"@rm,rn":       "----nnnnmmmm----",
	"rm,@rn":       "----nnnnmmmm----",
	"none":         "----------------",
}

// normShape lowercases and strips whitespace so "Rm, Rn" and "rm,rn" agree.
func normShape(name string) string {
	var b strings.Builder
	for _, c := range strings.ToLower(name) {
		if c == ' ' || c == '\t' {
			continue
		}
		b.WriteRune(c)
	}
	return b.String()
}

// Shape returns the 16-character pattern for a named operand shape.
func Shape(name string) (string, bool) {
	p, ok := shapes[normShape(name)]
	return p, ok
}

// ShapeNames returns the known shape names, sorted.
func ShapeNames() []string {
	out := make([]string, 0, len(shapes))
	for k := range shapes {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
