package logic

import (
	"fmt"
	"sort"
	"strings"
)

// StrToLogicMap converts a binary pattern string ("01-1") into a LogicMap
// keyed by SigBit{Sig: sig, Bit: lsb-index}. '-' produces no entry (don't
// care). The rightmost character of s is bit 0. Other character values
// ('0','1') become 0/1 values. Any other character is silently treated
// like '-'; callers must validate patterns before passing.
func StrToLogicMap(sig, s string) LogicMap {
	out := make(LogicMap)
	n := len(s)
	for i := 0; i < n; i++ {
		bit := n - 1 - i // s[0] is the MSB
		switch s[i] {
		case '0':
			out[SigBit{Sig: sig, Bit: bit}] = 0
		case '1':
			out[SigBit{Sig: sig, Bit: bit}] = 1
		}
	}
	return out
}

// OpToLogicMap combines a plane bit string (1 char) and an opcode pattern
// (16 chars, possibly with spaces) into one LogicMap. The plane string is
// indexed under sig "p"; the opcode bits under sig "i". Whitespace in the
// opcode string is stripped before processing. Non-binary characters
// ('-', 'n', 'm', 'd', 'i', etc.) become don't-cares.
func OpToLogicMap(plane, opcode string) LogicMap {
	clean := strings.ReplaceAll(opcode, " ", "")
	out := StrToLogicMap("i", clean)
	for k, v := range StrToLogicMap("p", plane) {
		out[k] = v
	}
	return out
}

// LogicMapToStdMatch renders m as a width-character VHDL std_match pattern
// string. Bits keyed by SigBit{sig, b} are emitted as '0' or '1'; missing
// bits (and bits keyed under other sigs) become '-'. The MSB is the
// leftmost character (consistent with VHDL std_logic_vector(width-1 downto 0)).
func LogicMapToStdMatch(m LogicMap, sig string, width int) string {
	out := make([]byte, width)
	for i := range out {
		out[i] = '-'
	}
	for k, v := range m {
		if k.Sig != sig {
			continue
		}
		if k.Bit < 0 || k.Bit >= width {
			continue
		}
		pos := width - 1 - k.Bit
		if v == 0 {
			out[pos] = '0'
		} else {
			out[pos] = '1'
		}
	}
	return string(out)
}

// LogicMapToBoolExpr renders m as a parenthesized AND conjunction like
// "(op.code(3) = '0' and p(0) = '1')". Terms are sorted by Sig then by
// Bit for deterministic output. Empty maps render as the empty string;
// the caller decides how to treat that case (e.g. "always true").
func LogicMapToBoolExpr(m LogicMap, sigs map[string]string) string {
	if len(m) == 0 {
		return ""
	}
	keys := make([]SigBit, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].Sig != keys[j].Sig {
			return keys[i].Sig < keys[j].Sig
		}
		return keys[i].Bit < keys[j].Bit
	})
	var parts []string
	for _, k := range keys {
		sigName, ok := sigs[k.Sig]
		if !ok {
			sigName = k.Sig
		}
		// Emit std_logic bit expressions so the conjunction stays
		// std_logic (assignable to std_logic signals like imp_bit_N
		// and addr(N)). bit=1 → "sig(N)"; bit=0 → "not sig(N)".
		// Callers that need a boolean (e.g. `if` conditions) wrap
		// the result with "(expr) = '1'".
		if m[k] == 1 {
			parts = append(parts, fmt.Sprintf("%s(%d)", sigName, k.Bit))
		} else {
			parts = append(parts, fmt.Sprintf("not %s(%d)", sigName, k.Bit))
		}
	}
	return "(" + strings.Join(parts, " and ") + ")"
}
