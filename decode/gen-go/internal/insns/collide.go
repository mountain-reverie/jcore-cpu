package insns

import (
	"fmt"
	"sort"
	"strings"
)

// This file computes the VERDICT half of the collision story. annotateCollides
// (sync.go) computes the visible half: it links every row whose encoding can
// clash with another's, which is ~94 entries and almost all of them fine.
// `fmov FRm,FRn` against `fmov DRm,DRn` is one encoding discriminated at run
// time by FPSCR.SZ; `LDC Rm,PTEH` against DSP's `LDC Rm,MOD` is two variants
// that never ship on the same core.
//
// The defect worth failing a build on is narrower and mechanical:
//
//	two instructions with an IDENTICAL encoding that share an ENABLED variant.
//
// On such a core the decoder cannot tell them apart. There is no run-time
// discriminator and no configuration in which only one is present. That is
// exactly annotateCollides' unconditional arm (a.key == b.key) intersected
// with its variant condition, so both rules are kept here, side by side, over
// the same keyOfCode and the same sharedVariants.
//
// See jcore-workspace docs/decisions/0003-canonical-encoding-database.md.

// Collision is one pair of rows carrying an identical encoding that are both
// enabled on at least one variant. A and B are the rows' `format` strings with
// tabs normalised to a single space, ordered A < B so a pair has one spelling.
type Collision struct {
	A, B   string
	Code   string
	Shared []string // variant columns on which both rows are enabled, sorted
}

// Pair returns the collision's two formats in their canonical order, for use
// as a map key against a baseline list.
func (c Collision) Pair() [2]string { return [2]string{c.A, c.B} }

// CollisionReport is the result of one sweep: what was found, and enough about
// what was examined for the caller to prove the sweep was not vacuous.
type CollisionReport struct {
	Found    []Collision
	Variants []string // variant columns actually carried by the document, sorted
	Swept    int      // rows carrying both an encoding and a format
}

// Collisions reports every identical-encoding same-variant pair in d.
//
// It FAILS CLOSED. Zero rows, no variant column anywhere, an unparseable
// encoding, or zero rows carrying both a code and a format are all errors
// rather than an empty result: a sweep that finds nothing to sweep must never
// report success. (A missing file or unparseable JSON fails earlier, in Load.)
func Collisions(d *Doc) (*CollisionReport, error) {
	if len(d.Rows) == 0 {
		return nil, fmt.Errorf("no non-empty `instructions` array; nothing was swept, " +
			"which is a failure and not a pass")
	}

	// Which product columns the document actually carries. The canonical list
	// is variantColumns, owned by this package and shared with annotateCollides
	// and internal/freespace; the sweep does not guess at it.
	rep := &CollisionReport{}
	for _, v := range variantColumns {
		for _, r := range d.Rows {
			if val, ok := r.Get(v); ok {
				if _, isBool := val.(bool); isBool {
					rep.Variants = append(rep.Variants, v)
					break
				}
			}
		}
	}
	if len(rep.Variants) == 0 {
		return nil, fmt.Errorf("no row carries a boolean product column (want one of %s); "+
			"every pair would trivially share no variant and the sweep would pass vacuously",
			strings.Join(variantColumns, ","))
	}

	type keyed struct {
		row  *Row
		form string
	}
	byKey := map[Key][]keyed{}
	for _, r := range d.Rows {
		code := strings.TrimSpace(rowString(r, "code"))
		form := strings.TrimSpace(strings.ReplaceAll(rowString(r, "format"), "\t", " "))
		if code == "" || form == "" {
			continue
		}
		k, ok := keyOfCode(code)
		if !ok {
			return nil, fmt.Errorf("`%s` carries an unparseable encoding %q; "+
				"it cannot be compared against anything, so the sweep would skip it silently",
				form, code)
		}
		byKey[k] = append(byKey[k], keyed{r, form})
		rep.Swept++
	}
	if rep.Swept == 0 {
		return nil, fmt.Errorf("no instruction carries both a `code` and a `format`; " +
			"there is nothing to compare")
	}

	// Keyed by the format pair, so one pair is reported once however many
	// encodings it shares.
	found := map[[2]string]Collision{}
	for _, entries := range byKey {
		for i := range entries {
			for j := i + 1; j < len(entries); j++ {
				a, b := entries[i], entries[j]
				shared := sharedVariants(a.row, b.row)
				if len(shared) == 0 {
					continue
				}
				fa, fb := a.form, b.form
				if fb < fa {
					fa, fb = fb, fa
				}
				code := strings.TrimSpace(rowString(a.row, "code"))
				found[[2]string{fa, fb}] = Collision{A: fa, B: fb, Code: code, Shared: shared}
			}
		}
	}
	for _, c := range found {
		rep.Found = append(rep.Found, c)
	}
	sort.Slice(rep.Found, func(i, j int) bool {
		if rep.Found[i].A != rep.Found[j].A {
			return rep.Found[i].A < rep.Found[j].A
		}
		return rep.Found[i].B < rep.Found[j].B
	})
	return rep, nil
}

// rowString reads a string-valued row field, returning "" when the field is
// absent or is not a string.
func rowString(r *Row, key string) string {
	v, ok := r.Get(key)
	if !ok {
		return ""
	}
	s, _ := v.(string)
	return s
}

// sharedVariants returns the variant columns on which BOTH rows are enabled,
// i.e. the cores that face both instructions at once. Sorted, because
// variantColumns is.
func sharedVariants(a, b *Row) []string {
	var out []string
	for _, v := range variantColumns {
		av, aok := a.Get(v)
		bv, bok := b.Get(v)
		if !aok || !bok {
			continue
		}
		aOn, _ := av.(bool)
		bOn, _ := bv.(bool)
		if aOn && bOn {
			out = append(out, v)
		}
	}
	return out
}
