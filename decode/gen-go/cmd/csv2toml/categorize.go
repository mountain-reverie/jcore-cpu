package main

import "strings"

// categoryFor maps an SH-2 mnemonic to one of the 10 TOML file
// categories under spec/. Unknown mnemonics fall through to "system".
func categoryFor(mnemonic string) string {
	m := strings.ToUpper(strings.TrimSpace(mnemonic))
	// Take the leading mnemonic up to the first space, '.', or '/' —
	// CSV instruction names have appended operand text like "ADD Rm, Rn"
	// or size suffixes like "MOV.L" or "CMP/EQ".
	base := m
	if i := strings.IndexAny(m, " \t./"); i > 0 {
		base = m[:i]
	}
	switch base {
	case "ADD", "ADDC", "ADDV", "SUB", "SUBC", "SUBV", "NEG", "NEGC", "EXTS", "EXTU":
		return "arithmetic"
	case "MUL", "MULS", "MULU", "DMULS", "DMULU", "MAC":
		return "multiply"
	case "DIV0S", "DIV0U", "DIV1":
		return "divide"
	case "AND", "OR", "XOR", "NOT", "TST":
		return "logic"
	case "SHAL", "SHAR", "SHLL", "SHLR", "SHLL2", "SHLR2",
		"SHLL8", "SHLR8", "SHLL16", "SHLR16",
		"ROTL", "ROTR", "ROTCL", "ROTCR":
		return "shift"
	case "MOV", "MOVA", "MOVT", "SWAP", "XTRCT":
		return "mov"
	case "BF", "BT", "BRA", "BSR", "JMP", "JSR", "RTS", "RTE", "BSRF", "BRAF":
		return "branch"
	case "CMP", "TAS":
		return "compare"
	default:
		return "system"
	}
}
