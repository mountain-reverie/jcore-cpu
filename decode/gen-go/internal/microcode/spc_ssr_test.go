package microcode

import "testing"

func TestSPCSSRRegnum(t *testing.T) {
	cases := map[string]string{
		"SPC": `"10101"`, // index 21
		"SSR": `"10110"`, // index 22
	}
	for tag, want := range cases {
		if !isNamedReg(tag) {
			t.Errorf("%s should be a named register", tag)
		}
		if got := RegnumVHDL(tag); got != want {
			t.Errorf("RegnumVHDL(%q) = %q, want %q", tag, got, want)
		}
	}
}
