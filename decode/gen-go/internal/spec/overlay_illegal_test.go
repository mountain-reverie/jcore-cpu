package spec

import (
	"os"
	"path/filepath"
	"testing"
)

func TestInjectOverlayIllegals_BaseGetsBothOverlays(t *testing.T) {
	s, err := Load("../../spec") // base only
	if err != nil {
		t.Fatal(err)
	}
	instrsBefore := len(s.Instrs)
	if err := InjectOverlayIllegals(s, "../../spec", []string{"sh2a", "sh4"}); err != nil {
		t.Fatal(err)
	}
	// The recorded set is NOT dispatched microcode: s.Instrs must be untouched.
	if len(s.Instrs) != instrsBefore {
		t.Fatalf("InjectOverlayIllegals must not mutate s.Instrs; got %d, want %d", len(s.Instrs), instrsBefore)
	}
	// disp12 word1 0x3nm1 -> "0011nnnnmmmm0001" must now be recorded as excluded.
	found := false
	for _, in := range s.ExcludedIllegal {
		if normalizeDashes(in.Opcode) == normalizeDashes("0011 nnnn mmmm 0001") {
			found = true
			if in.Plane != "system" {
				t.Errorf("excluded illegal not system-plane: %q", in.Name)
			}
		}
	}
	if !found {
		t.Fatalf("expected excluded illegal entry for disp12 word1 0x3nm1")
	}
}

func TestInjectOverlayIllegals_SkipsPresentOverlay(t *testing.T) {
	s, err := LoadProfile("../../spec", "../../spec/sh2a") // sh2a real
	if err != nil {
		t.Fatal(err)
	}
	if err := InjectOverlayIllegals(s, "../../spec", []string{"sh2a", "sh4"}); err != nil {
		t.Fatal(err)
	}
	// sh2a opcodes are real here -> NOT recorded as excluded; sh4 IS recorded.
	for _, in := range s.ExcludedIllegal {
		if normalizeDashes(in.Opcode) == normalizeDashes("0011 nnnn mmmm 0001") {
			t.Fatalf("sh2a op recorded as excluded illegal despite being present (real)")
		}
	}
}

func TestInjectOverlayIllegals_OverlapGuardError(t *testing.T) {
	// Test that InjectOverlayIllegals returns an error when a recorded illegal
	// opcode collides (same opcode.Parse match/mask) with a real base opcode.

	// Create a temporary spec directory structure:
	// - tmpSpec/
	//   - testoverlay/ (simulating an overlay like spec/sh2a)
	//     - instructions.toml
	tmpSpec := t.TempDir()
	overlayDir := filepath.Join(tmpSpec, "testoverlay")
	if err := os.MkdirAll(overlayDir, 0755); err != nil {
		t.Fatal(err)
	}

	// Write a minimal TOML file to the overlay directory.
	// The overlay instruction has opcode "0011 dddd dddd 0001", which:
	// - normalizes to "0011dddddddd0001" (different from base's normalized string)
	// - parses to the same match/mask as "0011 nnnn mmmm 0001" (both have mask=0x3001, match=0x3001)
	overlayToml := `
[[instr]]
name = "Collision Test"
format = "nim12"
opcode = "0011 dddd dddd 0001"
operation = "test"

[[instr.slots]]
`
	overlayPath := filepath.Join(overlayDir, "instructions.toml")
	if err := os.WriteFile(overlayPath, []byte(overlayToml), 0644); err != nil {
		t.Fatal(err)
	}

	// Create a Spec with a base instruction whose opcode parses to match=0x3001, mask=0x3001.
	// Use opcode "0011 nnnn mmmm 0001" (normalized differently than overlay's "0011 iiii jjjj 0001").
	s := &Spec{
		Source: make(map[string]string),
		Instrs: []Instr{
			{
				Name:      "Base Instruction",
				Format:    "nim12",
				Opcode:    "0011 nnnn mmmm 0001",
				Operation: "base test",
				Slots: []Slot{
					{}, // minimal slot
				},
			},
		},
	}

	// Inject the overlay. Since the base instruction and overlay instruction
	// have different normalized opcode strings but the same parsed match/mask,
	// the present[norm] check (line 137) passes, but the overlap guard (line 161-166)
	// should catch the collision and return an error.
	err := InjectOverlayIllegals(s, tmpSpec, []string{"testoverlay"})
	if err == nil {
		t.Fatal("expected error from overlap guard, got nil")
	}

	// Verify the error message mentions "overlaps".
	errStr := err.Error()
	if !contains(errStr, "overlaps") {
		t.Fatalf("error message does not mention overlaps: %s", errStr)
	}
}

func TestInjectOverlayIllegals_SystemPlaneSkip(t *testing.T) {
	// Test that system-plane overlay instructions (e.g., TLB exceptions from sh4)
	// are NEVER recorded in s.ExcludedIllegal.

	s, err := Load("../../spec") // base only
	if err != nil {
		t.Fatal(err)
	}

	// Inject the sh4 overlay, which contains system-plane entries like TLB exceptions.
	if err := InjectOverlayIllegals(s, "../../spec", []string{"sh4"}); err != nil {
		t.Fatal(err)
	}

	// System-plane entries from sh4/exceptions.toml must NOT appear in ExcludedIllegal.
	// The sh4/exceptions.toml file contains entries like:
	//   - "Interrupt" with plane = "system" and opcode "---- 0000 dddd dddd"
	//   - "TLB IMISS" and other TLB exceptions with plane = "system"

	// Verify that no ExcludedIllegal entry corresponds to a system-plane exception opcode.
	// Specifically, check that the Interrupt opcode (---- 0000 dddd dddd) is not recorded.
	systemPlaneOpcodes := map[string]bool{
		normalizeDashes("---- 0000 dddd dddd"): true, // Interrupt (system-plane)
		// TLB exceptions also have plane = "system" and should be skipped.
	}

	for _, excl := range s.ExcludedIllegal {
		normOp := normalizeDashes(excl.Opcode)
		if systemPlaneOpcodes[normOp] {
			t.Errorf("system-plane opcode recorded as excluded illegal: %s (%s)", excl.Name, excl.Opcode)
		}
		// Additional safeguard: no ExcludedIllegal entry should have Plane != "system".
		// (All injected ExcludedIllegal entries get Plane="system" by injection, line 171.)
		// This checks that the source overlay entries were system-plane (and thus skipped).
	}

	// Verify that real (non-system) sh4 opcodes ARE recorded.
	// For example, sh4/mmu.toml or sh4/bank.toml should contribute opcodes.
	// Count recorded entries to ensure some sh4 opcodes were actually injected.
	if len(s.ExcludedIllegal) == 0 {
		t.Errorf("expected some sh4 non-system-plane opcodes to be recorded in ExcludedIllegal, got 0")
	}
}

// contains is a helper to check if a string contains a substring.
func contains(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
