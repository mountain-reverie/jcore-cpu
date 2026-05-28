package spec

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"github.com/BurntSushi/toml"
)

// Load reads every *.toml file under dir in alphabetical filename order
// and returns a merged Spec with defaults resolved into every slot.
func Load(dir string) (*Spec, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", dir, err)
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && filepath.Ext(e.Name()) == ".toml" {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)

	out := &Spec{Source: make(map[string]string)}
	for _, name := range names {
		path := filepath.Join(dir, name)
		var f File
		if _, err := toml.DecodeFile(path, &f); err != nil {
			return nil, fmt.Errorf("decode %s: %w", path, err)
		}
		// First file's defaults win for the whole spec. Later files may
		// redeclare them but values must match; we don't bother to check
		// that here since the converter writes the same block into every file.
		if out.Defaults == (Defaults{}) {
			out.Defaults = f.Defaults
		}
		for _, instr := range f.Instrs {
			applyDefaults(&instr, out.Defaults)
			out.Instrs = append(out.Instrs, instr)
			out.Source[instr.Name] = name
		}
	}
	return out, nil
}

// applyDefaults fills in unset slot fields from defaults. Empty strings
// in slots mean "inherit"; explicit values win.
//
// Empty slots are NOT modified: a fully-empty slot is the implicit
// cycle-terminator (see Slot's documentation) and must remain
// distinguishable from a slot that explicitly set its fields to the
// default values. Post-load: len(slot) == 0 iff terminator.
func applyDefaults(instr *Instr, d Defaults) {
	defs := map[string]string{}
	if d.PC != "" {
		defs["pc"] = d.PC
	}
	if d.IfIssue != "" {
		defs["if_issue"] = d.IfIssue
	}
	if d.SR != "" {
		defs["sr"] = d.SR
	}
	for i := range instr.Slots {
		if len(instr.Slots[i]) == 0 {
			continue // preserve empty cycle-terminator
		}
		for k, v := range defs {
			cur, present := instr.Slots[i][k]
			if !present || cur == "" {
				instr.Slots[i][k] = v
			}
		}
	}
}
