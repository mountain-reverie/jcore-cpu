package insns

import (
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/opcode"
)

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
