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
