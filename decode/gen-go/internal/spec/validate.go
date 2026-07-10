package spec

import (
	"fmt"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/opcode"
)

// Validate runs schema-level checks across the whole spec. Returns the
// first error encountered, with the instruction name embedded for context.
func Validate(s *Spec) error {
	seenOpcodes := make(map[string]string, len(s.Instrs))
	for _, instr := range s.Instrs {
		if _, _, err := opcode.Parse(instr.Opcode); err != nil {
			return fmt.Errorf("%s: %w", instr.Name, err)
		}
		// Two-word instructions (Opcode2 set) are keyed on (word1, word2):
		// several two-word instructions legitimately share word1 and are
		// disambiguated only by the extension word's high nibble
		// (ext_word[15:12], see internal/model discrimination). Single-word
		// instructions (Opcode2 == "") stay keyed on word1 alone, same as
		// before.
		dupKey := instr.Opcode + "\x00" + instr.Opcode2
		if prev, dup := seenOpcodes[dupKey]; dup {
			return fmt.Errorf("duplicate opcode %q: %q and %q",
				instr.Opcode, prev, instr.Name)
		}
		seenOpcodes[dupKey] = instr.Name
		for i, slot := range instr.Slots {
			for field := range slot {
				if !KnownFields[field] {
					return fmt.Errorf("%s slot %d: unknown field %q",
						instr.Name, i, field)
				}
			}
			if err := checkMemoryAccess(slot); err != nil {
				return fmt.Errorf("%s slot %d: %w", instr.Name, i, err)
			}
			// Empty slots are only allowed as the final slot of an
			// instruction. The Clojure generator treats a final empty
			// slot as the implicit "if_issue=true, dispatch=true"
			// terminator; an empty slot in the middle indicates a data
			// error (e.g. a missed merge during CSV ingest). Per
			// applyDefaults's contract, len(slot) == 0 iff terminator.
			if len(slot) == 0 && i != len(instr.Slots)-1 {
				return fmt.Errorf("%s slot %d: empty slot not at end of instruction",
					instr.Name, i)
			}
		}
	}
	return nil
}

// checkMemoryAccess enforces the rule that ma_op requires ma_size.
func checkMemoryAccess(s Slot) error {
	op := s["ma_op"]
	if op == "" || strings.EqualFold(op, "NOP") {
		return nil
	}
	if s["ma_size"] == "" {
		return fmt.Errorf("ma_op=%q requires ma_size", op)
	}
	return nil
}
