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
// normalized word1 opcode or by instruction name), records it in
// s.ExcludedIllegal.
//
// IMPORTANT: unlike an earlier version of this mechanism, these entries are
// NOT appended to s.Instrs and therefore never become dispatched microcode
// slots in the ROM/simple/direct decode tables. Doing so previously injected
// new minterms into decode_table_direct.vhd's per-field QMC reduction, which
// corrupted control-bit outputs for unrelated, legal instructions --
// confirmed via a direct-vs-ROM-decoder bisection: rebuilding the cosim
// against the ROM decoder (decode_table(rom), identical spec) ran the
// default test ROM cleanly (LED writes present, no X), while the QMC-reduced
// direct decoder X-faulted instruction fetch within the first ~70ns of
// simulation, well before any injected/excluded opcode was ever executed by
// the ROM. That ruled out "General Illegal microcode dispatched without
// exception context" and pointed squarely at the direct table's boolean
// reduction as the corrupted artifact.
//
// Instead, s.ExcludedIllegal feeds model.BuildBody's check_illegal_instruction
// predicate (decode_body.vhd) -- a small, decode-table-independent boolean
// function already used by the existing, proven exception path: datapath
// sets illegal_instr from check_illegal_instruction, and decode_core
// dispatches illegal_instr into the REAL "General Illegal" microcode entry
// that is already present in the ROM/simple/direct tables. This reuses
// working hardware instead of cloning exception-entry microcode slots into a
// second, directly-dispatched copy that the tables' minterm reduction must
// also absorb.
//
// The "not already in s" skip rule is what makes the behavior automatically
// vary by build: a base build (no overlays loaded) gets ExcludedIllegal
// populated for both sh2a and sh4; a build that loaded spec/sh2a for real
// gets sh2a skipped (already present, real dispatch) and only sh4 recorded;
// and symmetrically for a sh4-loaded build.
//
// It is an error if a recorded opcode's word1 pattern overlaps (in the
// opcode.Parse match/mask sense) a real, already-present base opcode at the
// same specificity -- that would silently misroute a legitimate instruction
// and must be surfaced rather than skipped.
func InjectOverlayIllegals(s *Spec, specDir string, overlays []string) error {
	// Index normalized word1 opcodes already present in s, and the set of
	// instruction names already present. Overlay files sometimes REDECLARE
	// an existing base instruction under the SAME NAME with a narrower
	// opcode (e.g. sh4/exceptions.toml pins bit 11 of "General Illegal",
	// "Slot Illegal", "Interrupt", "Error", "Break", "Reset CPU" to 0 purely
	// to disambiguate them from new TLB-exception nibbles it introduces).
	// LoadProfile treats that as an in-place override of the SAME
	// instruction, not a new one -- so a name match here means "s already
	// handles this", and it must not be (re)recorded as an excluded illegal
	// even though its raw overlay opcode string differs from base's.
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

	recorded := make(map[string]bool)

	for _, overlayName := range overlays {
		overlayDir := filepath.Join(specDir, overlayName)
		overlayInstrs, err := OverlayOpcodes(overlayDir)
		if err != nil {
			return err
		}
		for _, in := range overlayInstrs {
			if in.Plane == "system" {
				// System-plane entries (e.g. sh4/exceptions.toml's TLB
				// IMISS/DMISS/IPROT/DPROT vectors) are hardware-dispatched
				// microcode entry points, not opcodes a real fetch ever
				// decodes -- their "opcode" field is a nibble-selects-vector
				// pattern with most bits left as true don't-cares (e.g.
				// "---- 1000 dddd dddd", 12 of 16 bits wildcard) purely
				// because hardware jumps directly to that microcode slot on
				// a fault. Recording these as "excluded opcodes to trap"
				// and OR/QMC-reducing them together collapses to broad
				// clauses (e.g. "bit11=1 and bit10=0") that cover roughly
				// half the entire 16-bit opcode space, incorrectly trapping
				// real, legal instructions (confirmed: base build regressed
				// via testbra.s branch opcodes matching one such clause and
				// mistraping mid-test). Only real, fetch-decoded overlay
				// opcodes belong in the illegal-instruction trap set.
				continue
			}
			norm := normalizeDashes(in.Opcode)
			if present[norm] {
				continue // already real in this build -- skip
			}
			if presentNames[in.Name] {
				continue // same-named instruction already exists (override, not a new opcode)
			}
			if recorded[norm] {
				continue // already recorded from a prior overlay -- dedup
			}

			m, msk, perr := opcode.Parse(in.Opcode)
			if perr != nil {
				return fmt.Errorf("InjectOverlayIllegals: overlay %s instr %q: %w", overlayDir, in.Name, perr)
			}

			// Overlap guard: a recorded illegal opcode must not collide with
			// any real, already-present base opcode AT THE SAME SPECIFICITY
			// -- i.e. same fixed-bit mask (so dropping Opcode2 hasn't
			// widened this pattern into ambiguity with an existing,
			// differently-distinguished base instruction) and the same
			// match value on that mask (a literal encoding duplicate).
			// Partial-mask overlap against wildcard-heavy fallback patterns
			// (e.g. General Illegal's own "---- -111 dddd dddd") is normal
			// and resolved by decode-table priority, not an error.
			for _, p := range presentOps {
				if msk == p.mask && m == p.match {
					return fmt.Errorf("InjectOverlayIllegals: overlay %s opcode %q (word1 of %q) overlaps existing base instruction %q",
						overlayDir, in.Opcode, in.Name, p.name)
				}
			}

			s.ExcludedIllegal = append(s.ExcludedIllegal, Instr{
				Name:   fmt.Sprintf("Illegal %s", in.Name),
				Opcode: in.Opcode, // word1 only; Opcode2 intentionally dropped
				Plane:  "system",
			})
			recorded[norm] = true
			present[norm] = true
			presentOps = append(presentOps, opInfo{m, msk, in.Name})
		}
	}

	return nil
}
