package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestEmitTOMLRoundtrips(t *testing.T) {
	dir := t.TempDir()
	instrs := []spec.Instr{
		{Name: "CLRT", Format: "0", Opcode: "0000 0000 0000 1000",
			Operation: "0 -> T",
			Slots:     []spec.Slot{{"sr": "T=0", "pc": "INC"}}},
		{Name: "ADD Rm, Rn", Format: "nm", Opcode: "0011 nnnn mmmm 1100",
			Operation: "Rn + Rm -> Rn",
			Slots:     []spec.Slot{{"xbus": "Rn", "ybus": "Rm", "zbus": "Rn"}}},
	}
	cats := map[string][]spec.Instr{"system": {instrs[0]}, "arithmetic": {instrs[1]}}
	if err := emitTOML(dir, cats); err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"system.toml", "arithmetic.toml"} {
		b, err := os.ReadFile(filepath.Join(dir, want))
		if err != nil {
			t.Errorf("missing file %s: %v", want, err)
			continue
		}
		s := string(b)
		if !strings.Contains(s, "[defaults]") {
			t.Errorf("%s: missing [defaults] block", want)
		}
		if !strings.Contains(s, "[[instr]]") {
			t.Errorf("%s: missing [[instr]] block", want)
		}
	}
}
