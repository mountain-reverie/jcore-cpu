package main

import (
	"fmt"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// headerFields are not slot fields; they go on the Instr, not each Slot.
var headerFields = map[string]bool{
	"TABLE": true, "Format": true, "State": true, "Instruction": true,
	"Op Code": true, "Operation": true, "Plane": true,
}

// snakeCase converts "ZBUS SEL" → "zbus_sel", "MA OP" → "ma_op".
func snakeCase(col string) string {
	return strings.ToLower(strings.ReplaceAll(strings.TrimSpace(col), " ", "_"))
}

// convertGroup turns one CSV InstructionGroup into a spec.Instr.
// droppedCols lists CSV columns (raw names) that the histogram step
// determined are always-empty and should be omitted from output.
func convertGroup(g InstructionGroup, droppedCols map[string]bool) (spec.Instr, error) {
	if len(g.Rows) == 0 {
		return spec.Instr{}, fmt.Errorf("instruction %q: no rows", g.Name)
	}
	head := g.Rows[0]
	instr := spec.Instr{
		Name:      g.Name,
		Format:    head["Format"],
		Opcode:    head["Op Code"],
		Operation: head["Operation"],
		Plane:     head["Plane"],
		TableRef:  head["TABLE"],
	}
	for _, r := range g.Rows {
		slot := spec.Slot{}
		for col, val := range r {
			if val == "" || headerFields[col] || droppedCols[col] {
				continue
			}
			slot[snakeCase(col)] = val
		}
		instr.Slots = append(instr.Slots, slot)
	}
	return instr, nil
}
