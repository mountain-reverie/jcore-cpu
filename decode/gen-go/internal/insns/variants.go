package insns

import (
	"fmt"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

type Variant struct {
	Name     string
	Overlays []string // subdirectory names under specDir (e.g. "sh4")
	Group    string   // group label for appended rows
}

func Variants() []Variant {
	return []Variant{
		{Name: "J2"},
		{Name: "J1"},
		{Name: "J4", Overlays: []string{"sh4"}, Group: "System Control Instructions"},
		{Name: "J2A", Overlays: []string{"sh2a"}},
	}
}

type InstrSet struct {
	ByKey map[Key]spec.Instr
	Order []spec.Instr
}

func LoadVariant(specDir string, v Variant) (*InstrSet, error) {
	var overlayDirs []string
	for _, o := range v.Overlays {
		overlayDirs = append(overlayDirs, specDir+"/"+o)
	}
	s, err := spec.LoadProfile(specDir, overlayDirs...)
	if err != nil {
		return nil, fmt.Errorf("%s: load: %w", v.Name, err)
	}
	if err := spec.Validate(s); err != nil {
		return nil, fmt.Errorf("%s: validate: %w", v.Name, err)
	}
	set := &InstrSet{ByKey: map[Key]spec.Instr{}}
	for _, in := range s.Instrs {
		if in.Plane == "system" {
			continue
		}
		k, ok := KeyOf(in.Opcode)
		if !ok {
			return nil, fmt.Errorf("%s: unparseable opcode %q on %q", v.Name, in.Opcode, in.Name)
		}
		if prev, dup := set.ByKey[k]; dup {
			return nil, fmt.Errorf("%s: opcode collision %q: %s vs %s", v.Name, in.Opcode, prev.Name, in.Name)
		}
		set.ByKey[k] = in
		set.Order = append(set.Order, in)
	}
	return set, nil
}
