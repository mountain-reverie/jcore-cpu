package spec

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/BurntSushi/toml"
)

func TestSlotIllegalFieldParses(t *testing.T) {
	const src = `
[[instr]]
  name = "BT label"
  opcode = "1000 1001 dddd dddd"
  slot_illegal = true

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
	if !f.Instr[0].SlotIllegal {
		t.Errorf("%s: want SlotIllegal=true", f.Instr[0].Name)
	}
	if f.Instr[1].SlotIllegal {
		t.Errorf("%s: want SlotIllegal=false (default)", f.Instr[1].Name)
	}
}

// TestAttributePatchUnknownNameErrors locks the typo guard: an attribute patch
// naming an instruction that does not exist must fail loudly rather than be
// silently dropped -- silent-drop is the exact failure class the slot_illegal
// work was fixing.
func TestAttributePatchUnknownNameErrors(t *testing.T) {
	dir := t.TempDir()
	overlay := filepath.Join(dir, "overlay")
	if err := os.MkdirAll(overlay, 0o755); err != nil {
		t.Fatal(err)
	}
	src := "[[instr]]\n  name = \"NO SUCH INSTRUCTION\"\n  patch = true\n  slot_illegal = true\n"
	if err := os.WriteFile(filepath.Join(overlay, "patch.toml"), []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadProfile("../../spec", overlay)
	if err == nil {
		t.Fatal("want an error for an attribute patch naming an unknown instruction")
	}
	if !strings.Contains(err.Error(), "NO SUCH INSTRUCTION") {
		t.Errorf("error should name the offending instruction, got: %v", err)
	}
}

// TestAttributePatchWithSlotsErrors: a patch that also declares microcode is
// ambiguous. Silently dropping the slots would hide a real edit, so LoadProfile
// must refuse it rather than pick one meaning.
func TestAttributePatchWithSlotsErrors(t *testing.T) {
	overlay := filepath.Join(t.TempDir(), "overlay")
	if err := os.MkdirAll(overlay, 0o755); err != nil {
		t.Fatal(err)
	}
	src := `
[[instr]]
  name = "MOVA @(disp, PC), R0"
  patch = true
  slot_illegal = true
  [[instr.slots]]
    pc = "INC"
`
	if err := os.WriteFile(filepath.Join(overlay, "patch.toml"), []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadProfile("../../spec", overlay)
	if err == nil {
		t.Fatal("want an error for a patch that declares slots")
	}
	if !strings.Contains(err.Error(), "drop `patch`") {
		t.Errorf("error should say how to fix it, got: %v", err)
	}
}
