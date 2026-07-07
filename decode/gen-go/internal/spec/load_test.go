package spec

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/BurntSushi/toml"
)

func TestLoadAppliesDefaults(t *testing.T) {
	s, err := Load(filepath.Join("..", "..", "testdata", "fixtures"))
	if err != nil {
		t.Fatal(err)
	}
	if len(s.Instrs) != 2 {
		t.Fatalf("want 2 instrs, got %d", len(s.Instrs))
	}
	// CLRT slot leaves pc + if_issue unset; defaults must fill them in
	slot := s.Instrs[0].Slots[0]
	if slot["pc"] != "INC" {
		t.Errorf("pc not inherited from defaults: %v", slot["pc"])
	}
	if slot["if_issue"] != "NO" {
		t.Errorf("if_issue not inherited: %v", slot["if_issue"])
	}
	// CLRT explicitly overrides sr to "T=0"
	if slot["sr"] != "T=0" {
		t.Errorf("sr override lost: %v", slot["sr"])
	}
	// ADD slot leaves sr unset; defaults must apply HOLD
	addSlot := s.Instrs[1].Slots[0]
	if addSlot["sr"] != "HOLD" {
		t.Errorf("sr default not applied to ADD: %v", addSlot["sr"])
	}
}

func TestLoadDirectoryAlphabetical(t *testing.T) {
	dir := t.TempDir()
	mustWrite(t, filepath.Join(dir, "b.toml"), `
[[instr]]
name = "B"
format = "0"
opcode = "0000 0000 0000 0001"
slots = [{}]
`)
	mustWrite(t, filepath.Join(dir, "a.toml"), `
[[instr]]
name = "A"
format = "0"
opcode = "0000 0000 0000 0010"
slots = [{}]
`)
	s, err := Load(dir)
	if err != nil {
		t.Fatal(err)
	}
	if s.Instrs[0].Name != "A" || s.Instrs[1].Name != "B" {
		t.Errorf("order wrong: %v", []string{s.Instrs[0].Name, s.Instrs[1].Name})
	}
}

func TestLoadProductionSpec(t *testing.T) {
	s, err := Load(filepath.Join("..", "..", "spec"))
	if err != nil {
		t.Fatal(err)
	}
	if len(s.Instrs) < 100 {
		t.Errorf("loaded only %d instructions, want >=100", len(s.Instrs))
	}
}

func mustWrite(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestOpcode2RoundTrip(t *testing.T) {
	const doc = `
[[instr]]
  name = "MOV.L @(disp12,Rm),Rn"
  format = "nmd"
  opcode = "0011 nnnn mmmm 0001"
  opcode2 = "0110 dddd dddd dddd"
  operation = "(disp12+Rm)->Rn"
  [[instr.slots]]
    pc = "INC"
`
	var f struct {
		Instr []Instr `toml:"instr"`
	}
	if _, err := toml.Decode(doc, &f); err != nil {
		t.Fatal(err)
	}
	if len(f.Instr) != 1 {
		t.Fatalf("want 1 instr, got %d", len(f.Instr))
	}
	if got := f.Instr[0].Opcode2; got != "0110 dddd dddd dddd" {
		t.Errorf("Opcode2 = %q, want %q", got, "0110 dddd dddd dddd")
	}
}
