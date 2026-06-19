package model

import (
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/logic"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestAddrBitsForSlots pins the microcode-address-width formula at its
// boundaries and checks the invariant that the all-ones address always stays
// a reserved (unused) slot — i.e. numSlots < 2^addrBits.
func TestAddrBitsForSlots(t *testing.T) {
	cases := []struct {
		slots, want int
	}{
		{1, 8},   // floor
		{200, 8}, // base-ish
		{251, 8}, // current base
		{255, 8}, // last value that fits 8-bit (slots 0..254, sentinel 255 free)
		{256, 9}, // slots 0..255 would collide with the 255 sentinel -> need 9
		{257, 9},
		{511, 9},  // slots 0..510, sentinel 511 free
		{512, 10}, // bumps to 10
	}
	for _, c := range cases {
		got := addrBitsForSlots(c.slots)
		if got != c.want {
			t.Errorf("addrBitsForSlots(%d) = %d, want %d", c.slots, got, c.want)
		}
		if c.slots >= (1 << got) {
			t.Errorf("addrBitsForSlots(%d)=%d leaves no room for the all-ones sentinel", c.slots, got)
		}
	}
}

// TestAddrLit checks the VHDL address-literal rendering: hex for widths
// divisible by 4 (so the 8-bit case reproduces the legacy x"%02x" form
// byte-for-byte), binary otherwise.
func TestAddrLit(t *testing.T) {
	cases := []struct {
		value, bits int
		want        string
	}{
		{0, 8, `x"00"`},
		{226, 8, `x"e2"`}, // a real reset addr
		{250, 8, `x"fa"`}, // a real system addr (BREAK)
		{255, 8, `x"ff"`}, // the 8-bit sentinel (legacy default)
		{0, 9, `"000000000"`},
		{257, 9, `"100000001"`},
		{511, 9, `"111111111"`}, // the 9-bit sentinel
	}
	for _, c := range cases {
		if got := addrLit(c.value, c.bits); got != c.want {
			t.Errorf("addrLit(%d, %d) = %q, want %q", c.value, c.bits, got, c.want)
		}
	}
}

// TestBuildBodyAddrSentinel checks the predecode "unknown opcode" default is
// the all-ones address rendered at the active width.
func TestBuildBodyAddrSentinel(t *testing.T) {
	empty := func() *Body {
		return BuildBody(map[string]int{}, map[string]logic.LogicMap{}, map[string]bool{}, map[string]bool{}, 8, nil, 0)
	}
	if got := empty().AddrSentinel; got != `x"ff"` {
		t.Errorf("8-bit AddrSentinel = %q, want %q", got, `x"ff"`)
	}
	b9 := BuildBody(map[string]int{}, map[string]logic.LogicMap{}, map[string]bool{}, map[string]bool{}, 9, nil, 0)
	if got := b9.AddrSentinel; got != `"111111111"` {
		t.Errorf("9-bit AddrSentinel = %q, want %q", got, `"111111111"`)
	}
}

// TestSetOperationAddrWidth covers the operation_t.addr patch directly,
// including the 9-bit width (which no real Build reaches yet) and the
// not-found error path that guards against a silent no-op if the record or
// field is ever renamed.
func TestSetOperationAddrWidth(t *testing.T) {
	addrType := func(p *Package) string {
		for _, r := range p.Records {
			if r.Name != "operation_t" {
				continue
			}
			for _, f := range r.Fields {
				if len(f.Names) == 1 && f.Names[0] == "addr" {
					return f.Type
				}
			}
		}
		return ""
	}

	p8 := newStaticPackage()
	if err := setOperationAddrWidth(p8, 8); err != nil {
		t.Fatal(err)
	}
	if got := addrType(p8); got != "std_logic_vector(7 downto 0)" {
		t.Errorf("8-bit operation_t.addr = %q, want std_logic_vector(7 downto 0)", got)
	}

	p9 := newStaticPackage()
	if err := setOperationAddrWidth(p9, 9); err != nil {
		t.Fatal(err)
	}
	if got := addrType(p9); got != "std_logic_vector(8 downto 0)" {
		t.Errorf("9-bit operation_t.addr = %q, want std_logic_vector(8 downto 0)", got)
	}

	// Not-found path: a package without operation_t must error, not no-op.
	if err := setOperationAddrWidth(&Package{}, 8); err == nil {
		t.Error("setOperationAddrWidth on a package without operation_t: want error, got nil")
	}
}

// TestProductionBuildIsEightBit is the end-to-end invariant: the real SH-2
// spec fits the 8-bit microcode space, so AddressBits is 8 and the ROM is the
// legacy 256 words. (This is what keeps base/J1/J2 byte-identical; the >256
// path widens automatically once a future spec crosses the ceiling.)
func TestProductionBuildIsEightBit(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if d.AddressBits != 8 {
		t.Errorf("production AddressBits = %d, want 8", d.AddressBits)
	}
	if len(d.ROM.Words) != 256 {
		t.Errorf("production ROM.Words = %d, want 256", len(d.ROM.Words))
	}
}
