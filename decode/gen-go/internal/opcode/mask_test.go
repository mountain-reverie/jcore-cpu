package opcode

import "testing"

func TestParse(t *testing.T) {
	tests := []struct {
		in              string
		wantMatch, wantMask uint16
		wantErr         bool
	}{
		{"0000 0000 0000 1000", 0x0008, 0xFFFF, false},
		{"0011 nnnn mmmm 1100", 0x300C, 0xF00F, false},
		{"0000 0000 0010 1011", 0x002B, 0xFFFF, false},
		{"1111 1111 1111 1111", 0xFFFF, 0xFFFF, false},
		{"---- ---- ---- ----", 0x0000, 0x0000, false},
		{" 0011 nnnn mmmm 1100 ", 0x300C, 0xF00F, false},
		{"0011 nnnn mmmm", 0, 0, true},
		{"0011 nnnn mmmm 110Z", 0, 0, true},
	}
	for _, tc := range tests {
		t.Run(tc.in, func(t *testing.T) {
			m, mk, err := Parse(tc.in)
			if (err != nil) != tc.wantErr {
				t.Fatalf("err=%v, wantErr=%v", err, tc.wantErr)
			}
			if err != nil {
				return
			}
			if m != tc.wantMatch || mk != tc.wantMask {
				t.Errorf("match=%04X mask=%04X, want match=%04X mask=%04X",
					m, mk, tc.wantMatch, tc.wantMask)
			}
		})
	}
}

func TestParse32(t *testing.T) {
	// mov.l @(disp12,Rm),Rn : 0011 nnnn mmmm 0001  0110 dddd dddd dddd
	m, mask, err := Parse32("0011 nnnn mmmm 0001 0110 dddd dddd dddd")
	if err != nil {
		t.Fatalf("unexpected err: %v", err)
	}
	// fixed bits: 0011............0001 0110............  don't-cares elsewhere
	if want := uint32(0x30016000); m != want {
		t.Errorf("match = %#08x, want %#08x", m, want)
	}
	if want := uint32(0xF00FF000); mask != want {
		t.Errorf("mask = %#08x, want %#08x", mask, want)
	}
	if _, _, err := Parse32("0011"); err == nil {
		t.Error("want length error for short pattern")
	}
}

func TestOverlaps(t *testing.T) {
	mustParse := func(t *testing.T, p string) (uint16, uint16) {
		t.Helper()
		m, k, err := Parse(p)
		if err != nil {
			t.Fatalf("Parse(%q): %v", p, err)
		}
		return m, k
	}
	cases := []struct {
		name string
		a, b string
		want bool
	}{
		// Same fixed bits everywhere both constrain.
		{"identical", "0110nnnnmmmm0011", "0110nnnnmmmm0011", true},
		// b's don't-care m-field spans a's fixed 1100; every word matching
		// a also matches b. Exact-key comparison would miss this.
		{"nested field over constant", "0000nnnn11001011", "0000nnnnmmmm1011", true},
		// Differ in the low nibble, which both fix.
		{"disjoint low nibble", "0110nnnnmmmm0011", "0110nnnnmmmm0100", false},
		// Differ in the top nibble.
		{"disjoint top nibble", "0110nnnnmmmm0011", "0100nnnnmmmm0011", false},
		// Neither constrains any common bit.
		{"all don't care", "----------------", "0110nnnnmmmm0011", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			am, ak := mustParse(t, tc.a)
			bm, bk := mustParse(t, tc.b)
			if got := Overlaps(am, ak, bm, bk); got != tc.want {
				t.Errorf("Overlaps(%q, %q) = %v, want %v", tc.a, tc.b, got, tc.want)
			}
			if got := Overlaps(bm, bk, am, ak); got != tc.want {
				t.Errorf("Overlaps is not symmetric for %q, %q", tc.a, tc.b)
			}
		})
	}
}
