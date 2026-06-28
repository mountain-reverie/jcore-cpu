// Package encoding parses insns.json "code" bit-pattern strings into
// structured 16-bit words and contiguous operand bit-fields.
package encoding

import (
	"fmt"
	"strings"
)

// Bit is one position in an instruction word.
type Bit struct {
	Fixed  bool // true: literal Val; false: operand field Letter
	Val    int  // 0 or 1 when Fixed
	Letter byte // operand letter (e.g. 'n','m','i','d') when !Fixed
}

// Word is 16 bits, index 0 = MSB (bit 15).
type Word [16]Bit

// Field is a contiguous run of one operand letter within a single word.
type Field struct {
	Letter byte
	Word   int // word index (0 or 1)
	Hi, Lo int // bit positions, 15..0, inclusive
	Width  int
}

// ParseCode parses a (possibly two-word) code string into words.
func ParseCode(code string) ([]Word, error) {
	parts := strings.Fields(code)
	if len(parts) == 0 {
		return nil, fmt.Errorf("empty code")
	}
	words := make([]Word, 0, len(parts))
	for _, p := range parts {
		if len(p) != 16 {
			return nil, fmt.Errorf("word %q is %d bits, want 16", p, len(p))
		}
		var w Word
		for i := 0; i < 16; i++ {
			c := p[i]
			switch c {
			case '0':
				w[i] = Bit{Fixed: true, Val: 0}
			case '1':
				w[i] = Bit{Fixed: true, Val: 1}
			default:
				w[i] = Bit{Letter: c}
			}
		}
		words = append(words, w)
	}
	return words, nil
}

// Fields returns contiguous letter runs in this word, MSB-first.
func (w Word) Fields() []Field {
	var fs []Field
	i := 0
	for i < 16 {
		b := w[i]
		if b.Fixed {
			i++
			continue
		}
		start := i
		for i < 16 && !w[i].Fixed && w[i].Letter == b.Letter {
			i++
		}
		hi := 15 - start
		lo := 15 - (i - 1)
		fs = append(fs, Field{Letter: b.Letter, Hi: hi, Lo: lo, Width: hi - lo + 1})
	}
	return fs
}

// ParseFields returns all fields across all words, with Word index set.
func ParseFields(words []Word) []Field {
	var all []Field
	for wi, w := range words {
		for _, f := range w.Fields() {
			f.Word = wi
			all = append(all, f)
		}
	}
	return all
}
