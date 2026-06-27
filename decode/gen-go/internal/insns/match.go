package insns

import (
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/opcode"
)

// NormAsm returns s lowercased with all whitespace removed.
func NormAsm(s string) string {
	var b strings.Builder
	for _, c := range s {
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			continue
		}
		if c >= 'A' && c <= 'Z' {
			c += 'a' - 'A'
		}
		b.WriteRune(c)
	}
	return b.String()
}

// aliasMnemonic corrects known SH-reference-dataset spelling quirks so the same
// instruction is not mistaken for an encoding collision. "ldtbl" is the dataset's
// misspelling of LDTLB (opcode 0x0038).
var aliasMnemonic = map[string]string{"ldtbl": "ldtlb"}

// mnemonicOf reduces an assembly string to its opcode mnemonic, used to decide
// whether a J-core instruction genuinely IS the lone SH-reference row sharing its
// encoding, or merely reuses it for a different instruction. The mnemonic is the
// first whitespace-delimited token plus any following tokens that begin with '/'
// or '.' — the spec writes condition/size suffixes space-separated ("CMP /EQ",
// "BT /S"), while operands begin with a register/immediate/label. The result is
// lowercased, surrounding punctuation trimmed, and alias-normalized. Examples:
// "CMP /STR Rm, Rn" -> "cmp/str", "LDC, Rm, GBR" -> "ldc", "movli.l\t@Rm,R0" ->
// "movli.l", "ldtbl" -> "ldtlb".
func mnemonicOf(s string) string {
	fields := strings.Fields(s)
	if len(fields) == 0 {
		return ""
	}
	mnem := fields[0]
	for _, f := range fields[1:] {
		if strings.HasPrefix(f, "/") || strings.HasPrefix(f, ".") {
			mnem += f
		} else {
			break
		}
	}
	mnem = strings.ToLower(mnem)
	mnem = strings.TrimFunc(mnem, func(r rune) bool {
		return !((r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '.' || r == '/')
	})
	if a, ok := aliasMnemonic[mnem]; ok {
		return a
	}
	return mnem
}

type Key struct{ Match, Mask uint16 }

func KeyOf(pattern string) (Key, bool) {
	s := strings.ReplaceAll(pattern, " ", "")
	if len(s) != 16 {
		return Key{}, false
	}
	var b strings.Builder
	for _, c := range s {
		if c == '0' || c == '1' {
			b.WriteRune(c)
		} else {
			b.WriteByte('-')
		}
	}
	m, mask, err := opcode.Parse(b.String())
	if err != nil {
		return Key{}, false
	}
	return Key{Match: m, Mask: mask}, true
}
