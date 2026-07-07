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

type Key struct {
	Match, Mask   uint16
	Match2, Mask2 uint16
	Two           bool
}

// normalizeDashes converts non-0/1 characters in a binary pattern to dashes.
// Used to prepare patterns for opcode.Parse.
func normalizeDashes(s string) string {
	var b strings.Builder
	for _, c := range s {
		if c == '0' || c == '1' {
			b.WriteRune(c)
		} else {
			b.WriteByte('-')
		}
	}
	return b.String()
}

func KeyOf(pattern string) (Key, bool) {
	s := strings.ReplaceAll(pattern, " ", "")
	if len(s) != 16 {
		return Key{}, false
	}
	m, mask, err := opcode.Parse(normalizeDashes(s))
	if err != nil {
		return Key{}, false
	}
	return Key{Match: m, Mask: mask}, true
}

// KeyOf2 builds a two-word key from two 16-bit patterns.
func KeyOf2(word1, word2 string) (Key, bool) {
	k1, ok1 := KeyOf(word1)
	if !ok1 {
		return Key{}, false
	}
	word2Clean := strings.ReplaceAll(word2, " ", "")
	if len(word2Clean) != 16 {
		return Key{}, false
	}
	m2, mask2, err := opcode.Parse(normalizeDashes(word2Clean))
	if err != nil {
		return Key{}, false
	}
	return Key{Match: k1.Match, Mask: k1.Mask, Match2: m2, Mask2: mask2, Two: true}, true
}
