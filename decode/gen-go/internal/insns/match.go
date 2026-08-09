package insns

import (
	"regexp"
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

// genericOperand matches the tokens that vary freely between two spellings of
// the SAME instruction: GPR operands and immediate/displacement placeholders.
// Anything else in the operand list — notably a named control register — is
// part of the instruction's identity.
var genericOperand = regexp.MustCompile(`^(r[nm0]|r[0-9]+|rn_bank|rm_bank|#?imm|#?i+|disp|d+|label)$`)

// operandSig reduces an assembly string to a comparable operand signature:
// the operand list with GPRs and immediates collapsed to "_", punctuation and
// case normalized. It exists because mnemonicOf() alone cannot tell two
// different instructions apart when they share a mnemonic and differ only in a
// named control register — exactly the case of SH-DSP's `ldc Rm,MOD` versus
// J4's `LDC Rm,PTEH`, which share the encoding 0100mmmm01011110. Treating those
// as the same instruction silently folded all three J4 MMU LDC forms into the
// DSP rows, so insns.json claimed J4 implemented MOD/RS/RE, the J4 MMU LDC
// forms had no rows at all, and the collision detector could not see the
// overlap. Examples:
//
//	"ldc\tRm,MOD"    -> "_,mod"
//	"LDC Rm, PTEH"   -> "_,pteh"
//	"CMP /EQ Rm, Rn" -> "_,_"      (matches "cmp/eq Rm,Rn")
//	"mov.l\t@(disp,Rm),Rn" -> "@(_,_),_"
func operandSig(s string) string {
	fields := strings.Fields(s)
	if len(fields) == 0 {
		return ""
	}
	// Drop the mnemonic and any space-separated "/EQ"-style suffix tokens.
	rest := fields[1:]
	for len(rest) > 0 && (strings.HasPrefix(rest[0], "/") || strings.HasPrefix(rest[0], ".")) {
		rest = rest[1:]
	}
	joined := strings.ToLower(strings.Join(rest, ""))
	var b strings.Builder
	var tok strings.Builder
	flush := func() {
		t := tok.String()
		tok.Reset()
		if t == "" {
			return
		}
		if genericOperand.MatchString(t) {
			b.WriteByte('_')
			return
		}
		b.WriteString(t)
	}
	for _, c := range joined {
		if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '#' || c == '_' {
			tok.WriteRune(c)
			continue
		}
		flush()
		b.WriteRune(c)
	}
	flush()
	return b.String()
}

// sameInstruction reports whether an insns.json row's format string and a spec
// instruction's name denote the same instruction.
//
// The mnemonics must always agree. Operand signatures are compared only when
// BOTH sides actually carry operands: some spec names are bare mnemonics
// ("LDTLB", and the system-plane pseudo-instructions "Break"/"Interrupt"),
// and an empty signature there means "not stated", not "no operands". So an
// empty signature on either side falls back to mnemonic-only agreement, which
// is the behaviour that predates operandSig.
//
// The case this exists to catch has operands on both sides and differs only in
// a named control register — `stc MOD,Rn` vs `STC EXPEVT,Rn`.
func sameInstruction(rowFormat, specName string) bool {
	if mnemonicOf(rowFormat) != mnemonicOf(specName) {
		return false
	}
	rs, ss := operandSig(rowFormat), operandSig(specName)
	if rs == "" || ss == "" {
		return true
	}
	return rs == ss
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
