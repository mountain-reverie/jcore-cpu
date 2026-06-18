package model

import (
	"fmt"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/opcode"
)

// illegalMatchExpr turns an opcode pattern ("0010 nnnn mmmm 0011") into a VHDL
// boolean term that is true for every encoding of that instruction:
//
//	(code and x"f00f") = x"2003"
//
// where the mask is 1 on fixed bits and the match holds those fixed bit values.
func illegalMatchExpr(pattern string) (string, error) {
	match, mask, err := opcode.Parse(pattern)
	if err != nil {
		return "", fmt.Errorf("illegal match expr for %q: %w", pattern, err)
	}
	return fmt.Sprintf(`(code and x"%04x") = x"%04x"`, mask, match), nil
}
