// Package format parses an insns.json "format" string into a mnemonic and
// a list of operand tokens, respecting parentheses so commas inside @(...)
// do not split operands.
package format

import "strings"

// Parsed is a decomposed assembler format string.
type Parsed struct {
	Mnemonic string
	Operands []string
}

// Parse splits format on the first whitespace (tab or space), then the operand list on top-level commas.
func Parse(formatStr string) Parsed {
	i := strings.IndexAny(formatStr, " \t")
	if i < 0 {
		return Parsed{Mnemonic: strings.TrimSpace(formatStr)}
	}
	mnem := strings.TrimSpace(formatStr[:i])
	rest := strings.TrimLeft(formatStr[i:], " \t")
	return Parsed{Mnemonic: mnem, Operands: splitTopLevel(rest)}
}

func splitTopLevel(s string) []string {
	var ops []string
	depth, start := 0, 0
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '(':
			depth++
		case ')':
			depth--
		case ',':
			if depth == 0 {
				ops = append(ops, strings.TrimSpace(s[start:i]))
				start = i + 1
			}
		}
	}
	last := strings.TrimSpace(s[start:])
	if last != "" {
		ops = append(ops, last)
	}
	return ops
}
