package opcode

import (
	"fmt"
	"strings"
)

// Parse turns a 16-character pattern (after stripping spaces) into a
// (match, mask) pair. A bit is set in mask iff the pattern fixes it to
// 0 or 1 (i.e. the character is '0' or '1'). Don't-care characters
// ('n', 'm', 'd', 'i', '-') produce 0 in mask. Match holds 1 where
// the pattern has '1' and 0 everywhere else.
func Parse(pattern string) (match, mask uint16, err error) {
	s := strings.ReplaceAll(strings.TrimSpace(pattern), " ", "")
	if len(s) != 16 {
		return 0, 0, fmt.Errorf("opcode %q: want 16 bits, got %d", pattern, len(s))
	}
	for i, c := range s {
		bit := uint16(1) << (15 - i)
		switch c {
		case '1':
			match |= bit
			mask |= bit
		case '0':
			mask |= bit
		case 'n', 'm', 'd', 'i', '-':
			// don't care
		default:
			return 0, 0, fmt.Errorf("opcode %q: invalid character %q at %d", pattern, c, i)
		}
	}
	return match, mask, nil
}

// Parse32 parses a 32-bit (two-word) opcode pattern. Same character set as
// Parse; the string must be exactly 32 bits after stripping spaces.
func Parse32(pattern string) (match, mask uint32, err error) {
	s := strings.ReplaceAll(strings.TrimSpace(pattern), " ", "")
	if len(s) != 32 {
		return 0, 0, fmt.Errorf("opcode %q: want 32 bits, got %d", pattern, len(s))
	}
	for i, c := range s {
		bit := uint32(1) << (31 - i)
		switch c {
		case '1':
			match |= bit
			mask |= bit
		case '0':
			mask |= bit
		case 'n', 'm', 'd', 'i', '-':
			// don't care
		default:
			return 0, 0, fmt.Errorf("opcode %q: invalid character %q at %d", pattern, c, i)
		}
	}
	return match, mask, nil
}
