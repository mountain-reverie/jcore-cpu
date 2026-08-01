package insns

import (
	"fmt"
	"sort"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/opcode"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// keyOfCode keys an insns.json "code" field, handling both single-word (16-bit)
// and two-word SH-2A (32-bit) codes. Two-word codes are keyed by BOTH words so
// the several @(disp12) movs -- which all share the first word 0011nnnnmmmm0001
// and differ only in the second -- stay distinct rows.
func keyOfCode(code string) (Key, bool) {
	s := strings.ReplaceAll(strings.TrimSpace(code), " ", "")
	switch len(s) {
	case 16:
		return KeyOf(s)
	case 32:
		return KeyOf2(s[:16], s[16:])
	}
	return Key{}, false
}

// overlapKeys reports whether two encoding keys can match the same
// instruction. This is strictly weaker than Key equality: two patterns whose
// operand fields differ can still claim the same words, and equality misses
// exactly that case.
//
// When both keys are two-word, word 1 AND the extension word must overlap —
// several two-word instructions legitimately share word 1 and are told apart
// only by the extension word (the disp12 family). When only one side is
// two-word, word 1 decides: a single-word instruction claims the whole word
// whatever follows it.
func overlapKeys(a, b Key) bool {
	if !opcode.Overlaps(a.Match, a.Mask, b.Match, b.Mask) {
		return false
	}
	if a.Two && b.Two {
		return opcode.Overlaps(a.Match2, a.Mask2, b.Match2, b.Mask2)
	}
	return true
}

// keyOfInstr keys a spec instruction, two-word when it carries an extension
// word (Opcode2), so it matches the corresponding two-word insns.json row
// instead of being appended as a duplicate.
func keyOfInstr(in spec.Instr) (Key, bool) {
	if in.Opcode2 != "" {
		return KeyOf2(in.Opcode, in.Opcode2)
	}
	return KeyOf(in.Opcode)
}

type VariantData struct {
	Variant Variant
	Set     *InstrSet
	Tab     *Table
}

type Report struct {
	Appended []string
	Matched  int
}

func Sync(d *Doc, vds []VariantData) (*Report, error) {
	rep := &Report{}

	byKey := map[Key][]*Row{}
	for _, r := range d.Rows {
		cv, ok := r.Get("code")
		if !ok {
			continue
		}
		code, _ := cv.(string)
		if k, ok := keyOfCode(code); ok {
			byKey[k] = append(byKey[k], r)
		}
	}

	matched := map[*Row]bool{}
	seenKey := map[Key]bool{}
	type pend struct {
		in  spec.Instr
		vd  VariantData
		key Key
	}
	var pending []pend

	// Reset every variant column on existing rows to false; the match loop below
	// re-marks only the rows an actual instruction maps to. This clears stale
	// flags when an instruction stops matching a row — e.g. NOTT, after J4's
	// LDTLB.RN is surfaced as its own row instead of folding into NOTT.
	for _, r := range d.Rows {
		for _, vd := range vds {
			setColsFalse(r, vd.Variant.Name)
		}
	}

	for _, vd := range vds {
		for _, in := range vd.Set.Order {
			k, _ := keyOfInstr(in)
			cands := byKey[k]
			if len(cands) == 0 {
				if !seenKey[k] {
					seenKey[k] = true
					pending = append(pending, pend{in, vd, k})
				}
				continue
			}
			row, err := pickRow(cands, in)
			if err != nil {
				return nil, err
			}
			if row == nil {
				// The lone candidate row is a DIFFERENT instruction that merely
				// shares this encoding (e.g. J4 LDTLB.RN over SH-2A NOTT at 0x0068).
				// Append it as a distinct row so it is surfaced, and let
				// annotateCollides link the two by shared encoding.
				if !seenKey[k] {
					seenKey[k] = true
					pending = append(pending, pend{in, vd, k})
				}
				continue
			}
			setCols(row, vd, vd.Set.ByKey[k])
			matched[row] = true
		}
	}

	// append unmatched (dedup already via seenKey), sorted by (group, code)
	sort.Slice(pending, func(i, j int) bool {
		gi, gj := pending[i].vd.Variant.Group, pending[j].vd.Variant.Group
		if gi != gj {
			return gi < gj
		}
		return normOpcode(pending[i].in.Opcode) < normOpcode(pending[j].in.Opcode)
	})
	for _, p := range pending {
		r := newRow(p.in, p.vd.Variant.Group)
		for _, vd := range vds {
			if in, ok := vd.Set.ByKey[p.key]; ok {
				setCols(r, vd, in)
			} else {
				setColsFalse(r, vd.Variant.Name)
			}
		}
		d.Rows = append(d.Rows, r)
		byKey[p.key] = append(byKey[p.key], r)
		rep.Appended = append(rep.Appended, p.in.Name)
	}

	rep.Matched = len(matched)
	annotateCollides(d)
	return rep, nil
}

// variantColumns are the per-variant boolean columns carried by every row of
// docs/insns.json, sorted. This package owns the document format, so this is
// the canonical list; other packages read it through VariantColumns.
var variantColumns = []string{
	"DSP", "J1", "J2", "J2A", "J4",
	"SH1", "SH2", "SH2A", "SH2E", "SH3", "SH3E", "SH4", "SH4A",
}

// VariantColumns returns the per-variant column names of docs/insns.json,
// sorted. The result is a copy: callers may not mutate the canonical list.
func VariantColumns() []string {
	out := make([]string, len(variantColumns))
	copy(out, variantColumns)
	return out
}

// sharesVariant reports whether two rows are both present in at least one
// variant, i.e. whether any single CPU faces both instructions at once.
func sharesVariant(a, b *Row) bool {
	for _, v := range variantColumns {
		av, aok := a.Get(v)
		bv, bok := b.Get(v)
		if !aok || !bok {
			continue
		}
		aOn, _ := av.(bool)
		bOn, _ := bv.(bool)
		if aOn && bOn {
			return true
		}
	}
	return false
}

// annotateCollides records, on each row, the formats of other rows whose
// encoding it can collide with.
//
// Two link rules apply. Rows with an IDENTICAL key link unconditionally, as
// they always have: the same encoding used twice is worth documenting even
// across variants that never ship together (J4's LDTLB.RN over SH-2A's NOTT).
// Rows that merely OVERLAP link only when they share a variant. Without that
// condition the DSP rows, whose operand and reserved fields normalize to
// don't-care, overlap nearly everything in the 1111 space and bury the real
// collisions under thousands of entries for ISA combinations no CPU has.
func annotateCollides(d *Doc) {
	type keyed struct {
		row *Row
		key Key
	}
	var rows []keyed
	for _, r := range d.Rows {
		cv, ok := r.Get("code")
		if !ok {
			continue
		}
		code, ok := cv.(string)
		if !ok {
			continue
		}
		k, ok := keyOfCode(code)
		if !ok {
			continue
		}
		rows = append(rows, keyed{r, k})
	}

	for i, a := range rows {
		var others []string
		for j, b := range rows {
			if i == j {
				continue
			}
			if a.key != b.key {
				if !overlapKeys(a.key, b.key) || !sharesVariant(a.row, b.row) {
					continue
				}
			}
			if f, ok := b.row.Get("format"); ok {
				if fs, ok := f.(string); ok {
					others = append(others, fs)
				}
			}
		}
		if len(others) == 0 {
			continue
		}
		sort.Strings(others)
		anys := make([]any, len(others))
		for i, s := range others {
			anys[i] = s
		}
		a.row.Set("collides", anys)
	}
}

// pickRow chooses the doc row that a J-core spec instruction belongs to, or
// returns (nil, nil) to signal "no match — append as a distinct row".
//
// Single candidate: a match only if its opcode mnemonic agrees with the spec
// instruction's. A lone SH-reference row whose mnemonic differs means the J-core
// op merely REUSES the encoding for a different instruction (collision) and must
// be surfaced separately, not folded in. (Bucket A/B notation differences — e.g.
// the "ldtbl" typo, or MMU regs over DSP control regs — share the mnemonic and
// stay folded.)
//
// Multiple candidates: the encoding is shared within the SH dataset itself; pick
// by full mnemonic identity to choose WHICH same-key row is ours. That is a
// distinct question from the single-candidate match-vs-append decision, so it
// uses full NormAsm equality rather than mnemonic-only.
func pickRow(cands []*Row, in spec.Instr) (*Row, error) {
	if len(cands) == 1 {
		f, _ := cands[0].Get("format")
		fs, _ := f.(string)
		if mnemonicOf(fs) == mnemonicOf(in.Name) {
			return cands[0], nil
		}
		return nil, nil
	}
	want := NormAsm(in.Name)
	var hit *Row
	n := 0
	for _, r := range cands {
		f, _ := r.Get("format")
		if fs, ok := f.(string); ok && NormAsm(fs) == want {
			hit = r
			n++
		}
	}
	if n == 1 {
		return hit, nil
	}
	return nil, fmt.Errorf("opcode %q (%s): %d of %d candidate rows match by mnemonic; cannot disambiguate", in.Opcode, in.Name, n, len(cands))
}

func setCols(r *Row, vd VariantData, in spec.Instr) {
	name := vd.Variant.Name
	tm := vd.Tab.For(in)
	r.Set(name, true)
	r.Set(name+".issue", tm.Issue.jsonValue())
	r.Set(name+".latency", tm.Latency.jsonValue())
}

func setColsFalse(r *Row, name string) {
	r.Set(name, false)
	r.Set(name+".issue", intToNum(0))
	r.Set(name+".latency", intToNum(0))
}

func newRow(in spec.Instr, group string) *Row {
	r := &Row{}
	r.Set("group", group)
	for _, arch := range []string{"SH1", "SH2", "SH2E", "SH3", "SH3E", "SH4", "SH4A", "SH2A", "DSP"} {
		r.Set(arch, false)
		r.Set(arch+".issue", intToNum(0))
		r.Set(arch+".latency", intToNum(0))
	}
	r.Set("format", in.Name)
	r.Set("abstract", in.Operation)
	r.Set("code", normOpcode(in.Opcode))
	return r
}
