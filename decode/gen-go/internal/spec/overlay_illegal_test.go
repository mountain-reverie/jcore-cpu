package spec

import "testing"

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
