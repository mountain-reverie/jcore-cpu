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

	byKey := map[Key]*Row{}
	for _, r := range d.Rows {
		cv, ok := r.Get("code")
		if !ok {
			continue
		}
		code, _ := cv.(string)
		k, ok := KeyOf(code)
		if !ok {
			continue
		}
		if _, dup := byKey[k]; dup {
			return nil, fmt.Errorf("duplicate row code %q", code)
		}
		byKey[k] = r
	}

	// patch existing rows
	for _, r := range d.Rows {
		cv, ok := r.Get("code")
		if !ok {
			continue
		}
		code, _ := cv.(string)
		k, ok := KeyOf(code)
		if !ok {
			continue
		}
		for _, vd := range vds {
			setCols(r, vd, k)
		}
	}

	// collect unmatched instrs, dedup by key
	type pending struct {
		in  spec.Instr
		vd  VariantData
		key Key
	}
	seen := map[Key]bool{}
	var pend []pending
	for _, vd := range vds {
		for _, in := range vd.Set.Order {
			k, _ := KeyOf(in.Opcode)
			if _, ok := byKey[k]; ok {
				rep.Matched++
				continue
			}
			if seen[k] {
				continue
			}
			seen[k] = true
			pend = append(pend, pending{in, vd, k})
		}
	}

	// sort by (group, code) and append
	sort.Slice(pend, func(i, j int) bool {
		gi, gj := pend[i].vd.Variant.Group, pend[j].vd.Variant.Group
		if gi != gj {
			return gi < gj
		}
		return normOpcode(pend[i].in.Opcode) < normOpcode(pend[j].in.Opcode)
	})
	for _, p := range pend {
		r := newRow(p.in, p.vd.Variant.Group)
		byKey[p.key] = r
		for _, vd := range vds {
			setCols(r, vd, p.key)
		}
		d.Rows = append(d.Rows, r)
		rep.Appended = append(rep.Appended, p.in.Name)
	}

	return rep, nil
}

func setCols(r *Row, vd VariantData, k Key) {
	name := vd.Variant.Name
	if in, ok := vd.Set.ByKey[k]; ok {
		tm := vd.Tab.For(in)
		r.Set(name, true)
		r.Set(name+".issue", intToNum(tm.Issue))
		r.Set(name+".latency", intToNum(tm.Latency))
	} else {
		r.Set(name, false)
		r.Set(name+".issue", intToNum(0))
		r.Set(name+".latency", intToNum(0))
	}
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
