// Package freespace searches for unused 16-bit instruction encodings.
//
// It answers: given the shape of an instruction I want to add, and the list
// of SH/J variants the encoding must not collide with, which encodings are
// available? Collision is a mask-overlap test (opcode.Overlaps), not a
// string or key comparison — an encoding whose operand fields differ can
// still be unusable.
package freespace

import (
	"fmt"
	"sort"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/insns"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/opcode"
)

// Claim is one encoding already taken by an instruction in docs/insns.json.
type Claim struct {
	Match, Mask uint16   // word1 key
	Format      string   // e.g. "mov\tRm,Rn"
	Group       string   // e.g. "Data Transfer Instructions"
	Variants    []string // sorted; variant columns true on this row
	TwoWord     bool     // row's code is 32 bits (word1 + extension word)
	Word2       string   // raw second-word pattern, e.g. "iiiiiiiiiiiiiiii"; empty for single-word rows
}

// variantColumns mirrors the canonical list owned by internal/insns, which
// owns the docs/insns.json format. Read once so the two cannot drift.
var variantColumns = insns.VariantColumns()

// Variants returns the variant names accepted by --avoid, sorted.
func Variants() []string {
	out := make([]string, len(variantColumns))
	copy(out, variantColumns)
	return out
}

// ClaimedBy reports whether any variant in avoid claims this encoding.
func (c Claim) ClaimedBy(avoid map[string]bool) bool {
	for _, v := range c.Variants {
		if avoid[v] {
			return true
		}
	}
	return false
}

// Claims builds the claimed-encoding set from a loaded insns.json document.
//
// Rows are recorded regardless of which variants enable them: the per-claim
// variant list is what lets callers both filter against --avoid and detect
// encodings claimed by nothing at all.
//
// Two-word rows carry a 32-bit code written as two space-separated 16-bit
// words. They are keyed on word1, because word1 is what the decoder must
// discriminate on first; a candidate overlapping such a word1 is reported
// separately rather than silently accepted.
func Claims(doc *insns.Doc) ([]Claim, error) {
	var out []Claim
	for i, r := range doc.Rows {
		code, _ := stringField(r, "code")
		if code == "" {
			return nil, fmt.Errorf("row %d: missing code", i)
		}
		words := strings.Fields(code)
		match, mask, err := opcode.Parse(normalizeCode(words[0]))
		if err != nil {
			return nil, fmt.Errorf("row %d: %w", i, err)
		}
		format, _ := stringField(r, "format")
		group, _ := stringField(r, "group")
		c := Claim{
			Match:   match,
			Mask:    mask,
			Format:  format,
			Group:   group,
			TwoWord: len(words) > 1,
		}
		if len(words) > 1 {
			c.Word2 = words[1]
		}
		for _, v := range variantColumns {
			if b, ok := r.Get(v); ok {
				if on, isBool := b.(bool); isBool && on {
					c.Variants = append(c.Variants, v)
				}
			}
		}
		sort.Strings(c.Variants)
		out = append(out, c)
	}
	return out, nil
}

// normalizeCode maps every character that is not '0' or '1' to a don't-care,
// so opcode.Parse accepts the whole document.
//
// docs/insns.json is not limited to the 'n'/'m'/'d'/'i' operand characters:
// 108 DSP rows use '*', 'z', 'x', 'y', 'D', 'A', 'e', 'f', 'g' and 'u' for
// their operand and reserved fields. Every one of those positions is a bit
// the instruction does not fix, which is exactly what a don't-care means
// here. internal/insns/match.go normalizes the same way for the same reason.
//
// Widening a field to don't-care can only make Overlaps report MORE
// collisions, never fewer, so an unfamiliar character can never cause an
// occupied encoding to be offered as free.
func normalizeCode(s string) string {
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

func stringField(r *insns.Row, key string) (string, bool) {
	v, ok := r.Get(key)
	if !ok {
		return "", false
	}
	s, ok := v.(string)
	return s, ok
}
