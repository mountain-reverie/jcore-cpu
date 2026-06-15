package spec

import (
	"os"
	"path/filepath"
	"testing"
)

func TestOverlayOverridesByName(t *testing.T) {
	base := t.TempDir()
	over := t.TempDir()
	os.WriteFile(filepath.Join(base, "a.toml"), []byte(`
[defaults]
  pc = "INC"
[[instr]]
  name = "RTE"
  opcode = "0000 0000 0010 1011"
  operation = "base-rte"
[[instr]]
  name = "NOP"
  opcode = "0000 0000 0000 1001"
  operation = "base-nop"
`), 0o644)
	os.WriteFile(filepath.Join(over, "o.toml"), []byte(`
[[instr]]
  name = "RTE"
  opcode = "0000 0000 0010 1011"
  operation = "overlay-rte"
[[instr]]
  name = "LDC Rm, SPC"
  opcode = "0100 mmmm 0100 1110"
  operation = "new"
`), 0o644)

	s, err := LoadProfile(base, over)
	if err != nil {
		t.Fatal(err)
	}
	var rteCount int
	var rteOp string
	for _, in := range s.Instrs {
		if in.Name == "RTE" {
			rteCount++
			rteOp = in.Operation
		}
	}
	if rteCount != 1 {
		t.Fatalf("want exactly 1 RTE after override, got %d", rteCount)
	}
	if rteOp != "overlay-rte" {
		t.Errorf("RTE not overridden: operation = %q, want overlay-rte", rteOp)
	}
	var hasNew bool
	for _, in := range s.Instrs {
		if in.Name == "LDC Rm, SPC" {
			hasNew = true
		}
	}
	if !hasNew {
		t.Error("overlay-only instruction LDC Rm, SPC missing")
	}
}
