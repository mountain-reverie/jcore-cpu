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
	return LoadProfile(dir)
}

// LoadProfile loads a base spec directory and then appends instructions from
// zero or more overlay directories (each in alphabetical file order). Overlays
// only contribute instructions; the Defaults from the base dir are used
// throughout. An empty overlay (or no overlays) produces the same result as
// calling Load(base).
func LoadProfile(base string, overlays ...string) (*Spec, error) {
	out := &Spec{Source: make(map[string]string)}

	// Load the base directory, capturing defaults from the first file.
	baseInstrs, baseDefs, err := readDir(base)
	if err != nil {
		return nil, err
	}
	out.Defaults = baseDefs
	for _, instr := range baseInstrs {
		applyDefaults(&instr, out.Defaults)
		out.Instrs = append(out.Instrs, instr)
		out.Source[instr.Name] = instr.Name // source key = instr name for overlay instrs
	}

	// Re-read base to record proper filenames in Source (readDir doesn't expose them).
	// We do this by re-reading just to get the filename map, then overwrite Source.
	out.Source = make(map[string]string)
	if err := populateSource(out, base); err != nil {
		return nil, err
	}

	// Index loaded instructions by name so an overlay can override by name.
	nameIndex := make(map[string]int, len(out.Instrs))
	for i, in := range out.Instrs {
		nameIndex[in.Name] = i
	}

	// Load each overlay dir. An overlay instruction whose name matches an
	// already-loaded instruction REPLACES it in place (ISA-variant override,
	// e.g. J4 swapping in register-model exceptions); otherwise it is appended.
	for _, overlayDir := range overlays {
		overlayInstrs, _, err := readDir(overlayDir)
		if err != nil {
			return nil, err
		}
		for _, instr := range overlayInstrs {
			applyDefaults(&instr, out.Defaults)
			if idx, ok := nameIndex[instr.Name]; ok {
				out.Instrs[idx] = instr
			} else {
				nameIndex[instr.Name] = len(out.Instrs)
				out.Instrs = append(out.Instrs, instr)
			}
			out.Source[instr.Name] = instr.Name
		}
		// Record proper filenames for overlay instructions.
		if err := populateSource(out, overlayDir); err != nil {
			return nil, err
		}
	}

	return out, nil
}

// readDir reads all *.toml files in dir (alphabetically) and returns the
// collected instructions plus the Defaults from the first file that declares
// them. It does not apply defaults to slots.
func readDir(dir string) ([]Instr, Defaults, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, Defaults{}, fmt.Errorf("read %s: %w", dir, err)
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && filepath.Ext(e.Name()) == ".toml" {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)

	var instrs []Instr
	var defs Defaults
	for _, name := range names {
		path := filepath.Join(dir, name)
		var f File
		if _, err := toml.DecodeFile(path, &f); err != nil {
			return nil, Defaults{}, fmt.Errorf("decode %s: %w", path, err)
		}
		// First file's defaults win.
		if defs == (Defaults{}) {
			defs = f.Defaults
		}
		instrs = append(instrs, f.Instrs...)
	}
	return instrs, defs, nil
}

// populateSource maps each instruction name to the filename it came from,
// for instructions that are present in both out.Source and the given dir.
// It walks the dir's TOML files alphabetically and records the filename for
// any instruction it finds that belongs to out (keyed by name).
func populateSource(out *Spec, dir string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return fmt.Errorf("read %s: %w", dir, err)
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && filepath.Ext(e.Name()) == ".toml" {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)

	for _, name := range names {
		path := filepath.Join(dir, name)
		var f File
		if _, err := toml.DecodeFile(path, &f); err != nil {
			return fmt.Errorf("decode %s: %w", path, err)
		}
		for _, instr := range f.Instrs {
			out.Source[instr.Name] = name
		}
	}
	return nil
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
