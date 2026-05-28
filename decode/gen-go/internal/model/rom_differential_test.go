package model

// TestDecoderDifferentialROM checks that the ROM microcode word at each
// instruction's slot address decodes to the same control-signal values that
// AssignSlot would produce for that (instruction, slot) pair.
//
// Strategy: use CreateEncoding to obtain the bit-field layout, then for every
// (instruction, slot) in the production spec walk the ROM words in the order
// assigned by Build (sequential, normal-instructions first in csvInstrOrder,
// system-instructions last) and decode each word back to an AssignMap.  Assert
// that the decoded AssignMap matches the expected AssignMap from AssignSlot.
//
// This is the ROM-side analogue of TestDecoderDifferential (which tests the
// direct decoder).  It catches bugs in CreateEncoding, Encode, or the ROM
// address assignment algorithm that would produce wrong hardware behaviour for
// specific instructions even though the ROM byte pattern looks structurally
// valid.
//
// Exclusions (same rationale as TestDecoderDifferential):
//   - SigImmVal: the ROM stores the raw ImmVal code, not the textual tag; the
//     byte-identity test already covers this path.
//   - Nillable signals absent in expected: the ROM may store a non-zero code
//     for a nillable signal when another instruction that shares the same slot
//     address region happened to set it — but for the instruction under test
//     the value is irrelevant.  We skip the check when expected[sig] == "".
//
// Coverage gap — nillable signals:
//
// When expected[sig] == "" for a nillable signal, the comparison is skipped.
// This means: if the ROM encodes a nillable signal to a wrong value where it
// should be don't-care (all-zeros) for this slot, this test will NOT catch it.
//
// What covers that gap instead:
//   (a) Byte-identity of the simple decoder against the Clojure golden output
//       in testdata/golden/clj/ — the simple decoder's if-branches are the
//       per-instruction source of truth; any wrong constant value produces a
//       textual difference.
//   (b) The simulator LED check in regression.sh Step 3 — any wrong
//       nillable-signal value that affects CPU behavior will manifest as a wrong
//       LED write value or sequence across the full testrom run.
//   (c) The synthesis check in Step 7 (yosys + ghdl-yosys-plugin) — a nillable
//       signal spuriously driven to a non-zero constant would appear as a
//       multi-driver net and fail `check -assert` if it conflicts with another
//       assignment. A wrong but non-conflicting don't-care-value assignment is
//       NOT caught by synthesis.

import (
	"fmt"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/microcode"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// decodeROMWord decodes one ROM word binary string back to an AssignMap using
// the Encoding produced by CreateEncoding.  The inverse of Encoding.Encode:
// for each field, extract the integer code from the bit-string, then reverse
// the Codes map to find the key (signal value or tuple key).
//
// For standalone fields the key is the signal value directly.
// For group fields the key is a comma-joined tuple; we split it and assign
// each member signal.
//
// Returns an error if an integer code found in the word has no reverse mapping
// in the Codes table (indicates an encoding bug or a mismatch between the
// Encoding used for packing and the one used here for unpacking).
func decodeROMWord(word string, enc *microcode.Encoding) (microcode.AssignMap, error) {
	am := make(microcode.AssignMap)
	n := enc.TotalBits

	for _, f := range enc.Fields {
		w := f.Width()
		if w == 0 {
			continue
		}

		// Extract the integer code from bits Hi..Lo of the word.
		// word[0] = MSB = bit (n-1).  Bit position bitPos corresponds
		// to word index n-1-bitPos.
		code := 0
		for bit := range w {
			// bit 0 = MSB of the field = position Hi in the vector.
			bitPos := f.Hi - bit
			idx := n - 1 - bitPos
			if idx < 0 || idx >= len(word) {
				return nil, fmt.Errorf("field Hi=%d Lo=%d: bit index %d out of range [0,%d)", f.Hi, f.Lo, idx, len(word))
			}
			code <<= 1
			if word[idx] == '1' {
				code |= 1
			}
		}

		// Reverse the Codes map: find the key whose code equals code.
		// Code 0 with the "" key means absent/all-zeros in the ROM.
		key := ""
		for k, v := range f.Codes {
			if v == code {
				key = k
				break
			}
		}
		if key == "" && code != 0 {
			// code != 0 but no matching key — the Codes map does not have an
			// entry for code 0 keyed by "" only when the field is nillable
			// (absent case is all-zeros and not stored).  Any other non-zero
			// unmatched code is an encoding bug.
			return nil, fmt.Errorf("field signal=%q group=%v: no reverse mapping for code %d", f.Signal, f.Group, code)
		}

		if key == "" {
			// Absent / all-zeros: no signal assignment for this field.
			continue
		}

		if f.Signal != "" {
			// Standalone field: key is the signal value.
			am[f.Signal] = key
		} else {
			// Group field: key is comma-joined tuple; split and assign each member.
			parts := strings.Split(key, ",")
			for i, s := range f.Group {
				if i < len(parts) && parts[i] != "" {
					am[s] = parts[i]
				}
			}
		}
	}

	return am, nil
}

func TestDecoderDifferentialROM(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if d.ROM == nil {
		t.Fatal("Build returned nil ROM")
	}

	// Reconstruct the Encoding from all slots, exactly as Build does, so
	// decodeROMWord uses the same bit-field layout as Encode used.
	instrByName := make(map[string]*spec.Instr, len(s.Instrs))
	for i := range s.Instrs {
		instrByName[s.Instrs[i].Name] = &s.Instrs[i]
	}

	// Replicate the csvInstrOrder partitioning from Build.
	var normalInstrs []*spec.Instr
	var systemInstrs []*spec.Instr
	for _, name := range csvInstrOrder {
		si := instrByName[name]
		if si == nil {
			continue
		}
		if si.Plane == "system" {
			systemInstrs = append(systemInstrs, si)
		} else {
			normalInstrs = append(normalInstrs, si)
		}
	}
	allInstrs := append(normalInstrs, systemInstrs...)

	// Replicate format-inheritance from Build.
	resolvedFormat := make(map[string]string, len(allInstrs))
	prevFormat := ""
	for _, name := range csvInstrOrder {
		si := instrByName[name]
		if si == nil {
			continue
		}
		if si.Format != "" {
			resolvedFormat[name] = si.Format
			prevFormat = si.Format
		} else {
			resolvedFormat[name] = prevFormat
		}
	}

	// Gather all AssignMaps in ROM order to reconstruct the Encoding.
	var allSlots []microcode.AssignMap
	type romSlot struct {
		instrName string
		slotIdx   int
		lastSlot  bool
		am        microcode.AssignMap
		instrForAssign spec.Instr
	}
	var romSlots []romSlot

	for _, si := range allInstrs {
		var keptSlots []spec.Slot
		for _, slot := range si.Slots {
			if len(slot) > 0 {
				keptSlots = append(keptSlots, slot)
			}
		}
		n := len(keptSlots)
		instrForAssign := *si
		if rf, ok := resolvedFormat[si.Name]; ok {
			instrForAssign.Format = rf
		}
		for j, slot := range keptSlots {
			am, err := microcode.AssignSlot(instrForAssign, slot)
			if err != nil {
				t.Fatalf("%s slot %d: AssignSlot: %v", si.Name, j, err)
			}
			if j == n-1 {
				_, hasIfIssue := am[microcode.SigIfIssue]
				_, hasDispatch := am[microcode.SigDispatch]
				if !hasIfIssue && !hasDispatch {
					am[microcode.SigIfIssue] = "1"
					am[microcode.SigDispatch] = "1"
				}
			}
			allSlots = append(allSlots, am)
			romSlots = append(romSlots, romSlot{
				instrName:      si.Name,
				slotIdx:        j,
				lastSlot:       j == n-1,
				am:             am,
				instrForAssign: instrForAssign,
			})
		}
	}

	enc := microcode.CreateEncoding(allSlots, 72)

	// Walk each ROM address and compare decoded vs expected.
	totalCases := 0
	for addr, rs := range romSlots {
		word := d.ROM.Words[addr].Bits
		testName := fmt.Sprintf("%s/slot%d", rs.instrName, rs.slotIdx)
		t.Run(testName, func(t *testing.T) {
			totalCases++
			decoded, err := decodeROMWord(word, enc)
			if err != nil {
				t.Fatalf("decodeROMWord addr=%d: %v", addr, err)
			}

			expected := rs.am

			// Compare signal by signal.
			for _, sig := range microcode.AllSignals {
				if sig == microcode.SigImmVal {
					// Excluded: ImmVal is stored as a numeric code in the ROM,
					// not as the textual tag in AssignMap. Covered by byte-identity.
					continue
				}
				wantVal := expected[sig]
				if wantVal == "" {
					// Nillable or absent: skip check (see file doc).
					continue
				}
				gotVal := decoded[sig]
				if gotVal != wantVal {
					t.Errorf("addr=%d signal=%s: ROM decoded %q, expected %q (ROM word: %s)",
						addr, sig, gotVal, wantVal, word)
				}
			}
		})
	}
	t.Logf("total ROM (instruction, slot) cases checked: %d", totalCases)
}
