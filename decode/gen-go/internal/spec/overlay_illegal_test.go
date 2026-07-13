package spec

import "testing"

func TestInjectOverlayIllegals_BaseGetsBothOverlays(t *testing.T) {
	s, err := Load("../../spec") // base only
	if err != nil {
		t.Fatal(err)
	}
	before := len(s.Instrs)
	if err := InjectOverlayIllegals(s, "../../spec", []string{"sh2a", "sh4"}); err != nil {
		t.Fatal(err)
	}
	// disp12 word1 0x3nm1 -> "0011nnnnmmmm0001" must now be present as illegal.
	found := false
	for _, in := range s.Instrs[before:] {
		if normalizeDashes(in.Opcode) == normalizeDashes("0011 nnnn mmmm 0001") {
			found = true
			if in.Plane != "system" {
				t.Errorf("injected illegal not system-plane: %q", in.Name)
			}
		}
	}
	if !found {
		t.Fatalf("expected injected illegal entry for disp12 word1 0x3nm1")
	}
}

func TestInjectOverlayIllegals_SkipsPresentOverlay(t *testing.T) {
	s, err := LoadProfile("../../spec", "../../spec/sh2a") // sh2a real
	if err != nil {
		t.Fatal(err)
	}
	before := len(s.Instrs)
	if err := InjectOverlayIllegals(s, "../../spec", []string{"sh2a", "sh4"}); err != nil {
		t.Fatal(err)
	}
	// sh2a opcodes are real here -> NOT re-injected as illegal; sh4 IS injected.
	for _, in := range s.Instrs[before:] {
		if normalizeDashes(in.Opcode) == normalizeDashes("0011 nnnn mmmm 0001") {
			t.Fatalf("sh2a op re-injected as illegal despite being present (real)")
		}
	}
}
