package spec

import (
	"fmt"
	"path/filepath"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/opcode"
)

// normalizeDashes strips whitespace and lowercases an opcode pattern so two
// equivalent spellings ("0011 nnnn mmmm 0001" vs "0011nnnnmmmm0001") compare
// equal. Word1-only comparisons ignore Opcode2 entirely.
func normalizeDashes(s string) string {
	out := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
			continue
		}
		if c >= 'A' && c <= 'Z' {
			c += 'a' - 'A'
		}
		out = append(out, c)
	}
	return string(out)
}

// OverlayOpcodes reads all *.toml files in dir (an overlay spec directory,
// e.g. spec/sh2a) and returns the instructions declared there, without
// applying any defaults. It is an exported wrapper around the package's
// internal directory reader so callers outside this package (e.g. cpugen's
// overlay-illegal injection) don't need to duplicate TOML parsing.
func OverlayOpcodes(dir string) ([]Instr, error) {
	instrs, _, err := readDir(dir)
	if err != nil {
		return nil, err
	}
	return instrs, nil
}

// InjectOverlayIllegals scans each overlay directory in overlays (paths
// relative to specDir's parent, e.g. filepath.Join(specDir, "sh2a")) and, for
// every word1 opcode declared there that is NOT already present in s (by
// normalized word1 opcode), appends a synthetic "Illegal <overlay>" system
// instruction that dispatches to the General Illegal microcode.
//
// This makes overlay opcodes that a given build excludes (e.g. sh4 opcodes
// in a base or sh2a-only build, or sh2a opcodes in a base or sh4-only build)
// TRAP instead of silently NOPing, because check_illegal_instruction only
// flags a hardcoded stub range and otherwise relies on the decode table
// having an explicit entry for every excluded encoding.
//
// The "not already in s" skip rule is what makes the behavior automatically
// vary by build: a base build (no overlays loaded) gets illegals injected
// for both sh2a and sh4; a build that loaded spec/sh2a for real gets sh2a
// skipped (already present, real dispatch) and only sh4 injected; and
// symmetrically for a sh4-loaded build.
//
// It is an error if an injected opcode's word1 pattern overlaps (in the
// opcode.Parse match/mask sense) a real, already-present base opcode --
// that would silently misroute a legitimate instruction and must be
// surfaced rather than skipped.
func InjectOverlayIllegals(s *Spec, specDir string, overlays []string) error {
	illegal, err := findGeneralIllegal(s)
	if err != nil {
		return err
	}

	// Index normalized word1 opcodes already present in s, and the set of
	// instruction names already present. Overlay files sometimes REDECLARE
	// an existing base instruction under the SAME NAME with a narrower
	// opcode (e.g. sh4/exceptions.toml pins bit 11 of "General Illegal",
	// "Slot Illegal", "Interrupt", "Error", "Break", "Reset CPU" to 0 purely
	// to disambiguate them from new TLB-exception nibbles it introduces).
	// LoadProfile treats that as an in-place override of the SAME
	// instruction, not a new one -- so a name match here means "s already
	// handles this", and it must not be (re)injected as a synthetic
	// illegal even though its raw overlay opcode string differs from
	// base's.
	present := make(map[string]bool, len(s.Instrs))
	presentNames := make(map[string]bool, len(s.Instrs))
	type opInfo struct {
		match, mask uint16
		name        string
	}
	presentOps := make([]opInfo, 0, len(s.Instrs))
	for _, in := range s.Instrs {
		norm := normalizeDashes(in.Opcode)
		present[norm] = true
		presentNames[in.Name] = true
		m, msk, perr := opcode.Parse(in.Opcode)
		if perr == nil {
			presentOps = append(presentOps, opInfo{m, msk, in.Name})
		}
	}

	injected := make(map[string]bool)

	for _, overlayName := range overlays {
		overlayDir := filepath.Join(specDir, overlayName)
		overlayInstrs, err := OverlayOpcodes(overlayDir)
		if err != nil {
			return err
		}
		for _, in := range overlayInstrs {
			norm := normalizeDashes(in.Opcode)
			if present[norm] {
				continue // already real in this build -- skip injection
			}
			if presentNames[in.Name] {
				continue // same-named instruction already exists (override, not a new opcode)
			}
			if injected[norm] {
				continue // already injected from a prior overlay -- dedup
			}

			m, msk, perr := opcode.Parse(in.Opcode)
			if perr != nil {
				return fmt.Errorf("InjectOverlayIllegals: overlay %s instr %q: %w", overlayDir, in.Name, perr)
			}

			// Overlap guard: an injected illegal must not collide with any
			// real, already-present base opcode AT THE SAME SPECIFICITY --
			// i.e. same fixed-bit mask (so dropping Opcode2 hasn't widened
			// this pattern into ambiguity with an existing, differently-
			// distinguished base instruction) and the same match value on
			// that mask (a literal encoding duplicate). Partial-mask
			// overlap against wildcard-heavy fallback patterns (e.g.
			// General Illegal's own "---- -111 dddd dddd") is normal and
			// resolved by decode-table priority, not an error.
			for _, p := range presentOps {
				if msk == p.mask && m == p.match {
					return fmt.Errorf("InjectOverlayIllegals: overlay %s opcode %q (word1 of %q) overlaps existing base instruction %q",
						overlayDir, in.Opcode, in.Name, p.name)
				}
			}

			clone := Instr{
				Name:      fmt.Sprintf("Illegal %s", in.Name),
				Format:    illegal.Format,
				Opcode:    in.Opcode, // word1 only; Opcode2 intentionally dropped
				Operation: illegal.Operation,
				Plane:     "system",
				Slots:     cloneSlots(illegal.Slots),
			}
			s.Instrs = append(s.Instrs, clone)
			injected[norm] = true
			present[norm] = true
			presentOps = append(presentOps, opInfo{m, msk, clone.Name})
		}
	}

	return nil
}

// findGeneralIllegal locates the "General Illegal" instruction in s, whose
// slots are cloned for every injected overlay-illegal entry.
func findGeneralIllegal(s *Spec) (*Instr, error) {
	for i := range s.Instrs {
		if s.Instrs[i].Name == "General Illegal" {
			return &s.Instrs[i], nil
		}
	}
	return nil, fmt.Errorf("InjectOverlayIllegals: %q instruction not found in spec", "General Illegal")
}

// cloneSlots deep-copies a slot slice so mutating the injected instruction's
// slots (e.g. via applyDefaults) never affects the original General Illegal
// instruction's slots.
func cloneSlots(slots []Slot) []Slot {
	out := make([]Slot, len(slots))
	for i, sl := range slots {
		if sl == nil {
			continue
		}
		cp := make(Slot, len(sl))
		for k, v := range sl {
			cp[k] = v
		}
		out[i] = cp
	}
	return out
}
