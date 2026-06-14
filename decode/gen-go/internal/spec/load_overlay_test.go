package spec

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadProfile_EmptyOverlayIsNoop(t *testing.T) {
	base := "../../spec"
	emptyOverlay := t.TempDir()

	baseSpec, err := Load(base)
	if err != nil {
		t.Fatalf("Load(%q): %v", base, err)
	}

	profileSpec, err := LoadProfile(base, emptyOverlay)
	if err != nil {
		t.Fatalf("LoadProfile(%q, emptyDir): %v", base, err)
	}

	if len(profileSpec.Instrs) != len(baseSpec.Instrs) {
		t.Errorf("empty overlay changed instruction count: got %d, want %d",
			len(profileSpec.Instrs), len(baseSpec.Instrs))
	}
}

func TestLoadProfile_OverlayAddsInstr(t *testing.T) {
	base := "../../spec"

	baseSpec, err := Load(base)
	if err != nil {
		t.Fatalf("Load(%q): %v", base, err)
	}
	baseCount := len(baseSpec.Instrs)

	overlayDir := t.TempDir()
	extraTOML := `[defaults]
  pc = "INC"
  if_issue = "NO"
  sr = "HOLD"

[[instr]]
  name = "TEST.OVERLAY"
  format = "n"
  opcode = "1111 nnnn 0000 0000"
  operation = "test overlay instruction"

  [[instr.slots]]
    pc = "INC"
`
	if err := os.WriteFile(filepath.Join(overlayDir, "extra.toml"), []byte(extraTOML), 0644); err != nil {
		t.Fatalf("write extra.toml: %v", err)
	}

	profileSpec, err := LoadProfile(base, overlayDir)
	if err != nil {
		t.Fatalf("LoadProfile(%q, overlayDir): %v", base, err)
	}

	if len(profileSpec.Instrs) != baseCount+1 {
		t.Errorf("overlay instruction count: got %d, want %d",
			len(profileSpec.Instrs), baseCount+1)
	}

	// Verify the overlay instruction is present and at the end.
	last := profileSpec.Instrs[len(profileSpec.Instrs)-1]
	if last.Name != "TEST.OVERLAY" {
		t.Errorf("last instruction name: got %q, want %q", last.Name, "TEST.OVERLAY")
	}
}
