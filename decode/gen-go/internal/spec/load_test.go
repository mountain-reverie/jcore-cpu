package spec

import (
	"os"
	"path/filepath"
	"testing"
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
