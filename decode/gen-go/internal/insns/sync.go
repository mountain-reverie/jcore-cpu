package insns

import (
	"fmt"
	"sort"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

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
		if k, ok := KeyOf(code); ok {
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

	for _, vd := range vds {
		for _, in := range vd.Set.Order {
			k, _ := KeyOf(in.Opcode)
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
			setCols(row, vd, vd.Set.ByKey[k])
			matched[row] = true
		}
	}

	// Any variant column not set on a row defaults to false/0:
	for _, r := range d.Rows {
		for _, vd := range vds {
			if _, ok := r.Get(vd.Variant.Name); !ok {
				setColsFalse(r, vd.Variant.Name)
			}
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

func annotateCollides(d *Doc) {
	byKey := map[Key][]*Row{}
	for _, r := range d.Rows {
		if cv, ok := r.Get("code"); ok {
			if code, ok := cv.(string); ok {
				if k, ok := KeyOf(code); ok {
					byKey[k] = append(byKey[k], r)
				}
			}
		}
	}
	for _, r := range d.Rows {
		cv, _ := r.Get("code")
		code, _ := cv.(string)
		k, ok := KeyOf(code)
		if !ok {
			continue
		}
		var others []string
		for _, o := range byKey[k] {
			if o == r {
				continue
			}
			if f, ok := o.Get("format"); ok {
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
		r.Set("collides", anys)
	}
}

func pickRow(cands []*Row, in spec.Instr) (*Row, error) {
	if len(cands) == 1 {
		return cands[0], nil
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
	r.Set(name+".issue", intToNum(tm.Issue))
	r.Set(name+".latency", intToNum(tm.Latency))
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
	r.Set("format", in.Format)
	r.Set("abstract", in.Operation)
	r.Set("code", normOpcode(in.Opcode))
	return r
}
