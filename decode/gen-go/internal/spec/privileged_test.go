package spec

import (
	"strings"
	"testing"

	"github.com/BurntSushi/toml"
)

func TestPrivilegedFieldParses(t *testing.T) {
	const src = `
[[instr]]
  name = "LDC Rm, VBR"
  opcode = "0100 mmmm 0010 1110"
  privileged = true

[[instr]]
  name = "ADD Rm, Rn"
  opcode = "0011 nnnn mmmm 1100"
`
	var f struct {
		Instr []Instr `toml:"instr"`
	}
	if _, err := toml.Decode(src, &f); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(f.Instr) != 2 {
		t.Fatalf("want 2 instrs, got %d", len(f.Instr))
	}
	if !f.Instr[0].Privileged {
		t.Errorf("%s: want Privileged=true", f.Instr[0].Name)
	}
	if f.Instr[1].Privileged {
		t.Errorf("%s: want Privileged=false (default)", f.Instr[1].Name)
	}
	_ = strings.TrimSpace // keep import set stable across edits
}
