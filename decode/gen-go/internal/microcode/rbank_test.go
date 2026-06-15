package microcode

import "testing"

func TestRBANKRegnumVHDL(t *testing.T) {
	got := RegnumVHDL("RBANK")
	want := `"11" & op.code(6 downto 4)`
	if got != want {
		t.Errorf("RegnumVHDL(\"RBANK\") = %q, want %q", got, want)
	}
}

func TestRBANKIsNamedReg(t *testing.T) {
	if !isNamedReg("RBANK") {
		t.Error("RBANK should be recognized as a named register")
	}
}
