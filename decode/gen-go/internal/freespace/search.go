package freespace

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/opcode"
)

// Candidate is one encoding the form admits, with its collision status.
type Candidate struct {
	Code        string // 16-character pattern, e.g. "0100nnnnmmmm1110"
	Match, Mask uint16
	Virgin      bool     // no claim at all overlaps it
	Shadows     []string // "VARIANT: format" per overlapping non-avoided claim, sorted
	Shareable   []string // two-word claims it overlaps on word1 (TwoWord searches only)
}

// Options configures a search.
type Options struct {
	Form    string   // 16-character pattern; '-' marks a bit the search assigns
	Regions []string // hex nibble prefixes; empty means unconstrained
	Avoid   []string // variant names the encoding must not collide with
	TwoWord bool     // candidate is word1 of a two-word instruction
}

// maxFreeBits caps enumeration. 16 free bits is 65536 candidates, already far
// past useful; beyond that the caller almost certainly passed the wrong form.
const maxFreeBits = 16

// Search enumerates the encodings a form admits and classifies each one.
//
// The candidate's mask covers the form's fixed bits plus the bits Search
// assigns. Operand field positions ('n', 'm', 'd', 'i') stay don't-care,
// because the instruction must accept every operand value — which is exactly
// why collision has to be an overlap test.
func Search(opts Options, claims []Claim) ([]Candidate, error) {
	form := strings.ReplaceAll(strings.TrimSpace(opts.Form), " ", "")
	if len(form) != 16 {
		return nil, fmt.Errorf("form %q: want 16 bits, got %d", opts.Form, len(form))
	}
	base, fixedMask, err := opcode.Parse(strings.ReplaceAll(form, "-", "n"))
	if err != nil {
		return nil, fmt.Errorf("form %q: %w", opts.Form, err)
	}

	var free []uint
	for i, c := range form {
		switch c {
		case '-':
			free = append(free, uint(15-i))
		case '0', '1', 'n', 'm', 'd', 'i':
			// fixed or operand field
		default:
			return nil, fmt.Errorf("form %q: invalid character %q at %d", opts.Form, c, i)
		}
	}
	if len(free) > maxFreeBits {
		return nil, fmt.Errorf("form %q: %d free bits exceeds limit %d", opts.Form, len(free), maxFreeBits)
	}

	regions, err := parseRegions(opts.Regions)
	if err != nil {
		return nil, err
	}
	avoid, err := avoidSet(opts.Avoid)
	if err != nil {
		return nil, err
	}

	var out []Candidate
	for n := 0; n < 1<<len(free); n++ {
		match := base
		mask := fixedMask
		for i, bit := range free {
			mask |= 1 << bit
			if n&(1<<(len(free)-1-i)) != 0 {
				match |= 1 << bit
			}
		}
		if !inRegions(match, mask, regions) {
			continue
		}
		cand := Candidate{
			Code:   render(form, free, match),
			Match:  match,
			Mask:   mask,
			Virgin: true,
		}
		blocked := false
		for _, c := range claims {
			if !opcode.Overlaps(match, mask, c.Match, c.Mask) {
				continue
			}
			cand.Virgin = false
			if c.ClaimedBy(avoid) {
				if opts.TwoWord && c.TwoWord {
					cand.Shareable = append(cand.Shareable, describeShareable(c))
					continue
				}
				blocked = true
				break
			}
			cand.Shadows = append(cand.Shadows, describe(c))
		}
		if blocked {
			continue
		}
		sort.Strings(cand.Shadows)
		sort.Strings(cand.Shareable)
		out = append(out, cand)
	}
	return out, nil
}

// describe renders a claim as "VARIANT[,VARIANT]: format" for reporting.
func describe(c Claim) string {
	return strings.Join(c.Variants, ",") + ": " + strings.ReplaceAll(c.Format, "\t", " ")
}

// describeShareable renders a two-word claim like describe, but appends the
// claim's word2 pattern so the caller can see which extension words are
// already taken — Search cannot verify a free ext_word[15:12] discriminant
// remains, since it doesn't know which extension word the caller intends.
func describeShareable(c Claim) string {
	return describe(c) + " [ext " + c.Word2 + "]"
}

// render substitutes the assigned bits back into the form so the result reads
// as a pattern ("0100nnnnmmmm1110") rather than a bare number.
func render(form string, free []uint, match uint16) string {
	b := []byte(form)
	for _, bit := range free {
		i := 15 - int(bit)
		if match&(1<<bit) != 0 {
			b[i] = '1'
		} else {
			b[i] = '0'
		}
	}
	return string(b)
}

type region struct{ match, mask uint16 }

// parseRegions turns hex nibble prefixes ("4", "0,4,8", "4f") into
// (match, mask) constraints on the high bits.
func parseRegions(specs []string) ([]region, error) {
	var out []region
	for _, s := range specs {
		s = strings.TrimSpace(s)
		if s == "" {
			continue
		}
		if len(s) > 4 {
			return nil, fmt.Errorf("region %q: at most 4 hex digits", s)
		}
		v, err := strconv.ParseUint(s, 16, 32)
		if err != nil {
			return nil, fmt.Errorf("region %q: not hex: %w", s, err)
		}
		shift := uint(4 * (4 - len(s)))
		out = append(out, region{
			match: uint16(v) << shift,
			mask:  uint16(0xFFFF) << shift,
		})
	}
	return out, nil
}

// inRegions reports whether a candidate lies in any requested region. A
// candidate qualifies only if it actually fixes the bits the region
// constrains; a form leaving the top nibble to an operand field cannot be
// pinned to a region.
func inRegions(match, mask uint16, regions []region) bool {
	if len(regions) == 0 {
		return true
	}
	for _, r := range regions {
		if mask&r.mask == r.mask && match&r.mask == r.match {
			return true
		}
	}
	return false
}

// avoidSet validates variant names against the insns.json columns.
func avoidSet(names []string) (map[string]bool, error) {
	known := map[string]bool{}
	for _, v := range variantColumns {
		known[v] = true
	}
	out := map[string]bool{}
	for _, n := range names {
		n = strings.ToUpper(strings.TrimSpace(n))
		if n == "" {
			continue
		}
		if !known[n] {
			return nil, fmt.Errorf("unknown variant %q: want one of %s", n, strings.Join(variantColumns, ", "))
		}
		out[n] = true
	}
	return out, nil
}
