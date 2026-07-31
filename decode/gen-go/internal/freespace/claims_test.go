package freespace

import (
	"reflect"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/insns"
)

// fixtureDoc builds an in-memory Doc so tests do not depend on the real
// docs/insns.json, which changes as the ISA grows.
func fixtureDoc(t *testing.T, rows ...map[string]any) *insns.Doc {
	t.Helper()
	doc := &insns.Doc{}
	for _, m := range rows {
		r := &insns.Row{}
		// Sorted key order keeps Row.keys deterministic; Claims does not
		// depend on order, but a stable fixture makes failures readable.
		for _, k := range []string{"group", "format", "code", "SH1", "SH2", "SH4", "SH2A", "J2", "J4"} {
			if v, ok := m[k]; ok {
				r.Set(k, v)
			}
		}
		doc.Rows = append(doc.Rows, r)
	}
	return doc
}

func TestClaimsSingleWord(t *testing.T) {
	doc := fixtureDoc(t, map[string]any{
		"group":  "Data Transfer Instructions",
		"format": "mov\tRm,Rn",
		"code":   "0110nnnnmmmm0011",
		"SH1":    true,
		"SH2":    true,
		"J4":     true,
		"SH2A":   false,
	})
	got, err := Claims(doc)
	if err != nil {
		t.Fatalf("Claims: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("got %d claims, want 1", len(got))
	}
	c := got[0]
	if c.Match != 0x6003 || c.Mask != 0xF00F {
		t.Errorf("key = (%#04x, %#04x), want (0x6003, 0xf00f)", c.Match, c.Mask)
	}
	if c.TwoWord {
		t.Error("TwoWord = true, want false")
	}
	if want := []string{"J4", "SH1", "SH2"}; !reflect.DeepEqual(c.Variants, want) {
		t.Errorf("Variants = %v, want %v (sorted, false columns dropped)", c.Variants, want)
	}
}

func TestClaimsTwoWordKeysOnWord1(t *testing.T) {
	doc := fixtureDoc(t, map[string]any{
		"group":  "Data Transfer Instructions",
		"format": "movi20\t#imm20,Rn",
		"code":   "0000nnnniiii0000 iiiiiiiiiiiiiiii",
		"SH2A":   true,
	})
	got, err := Claims(doc)
	if err != nil {
		t.Fatalf("Claims: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("got %d claims, want 1", len(got))
	}
	c := got[0]
	if c.Match != 0x0000 || c.Mask != 0xF00F {
		t.Errorf("key = (%#04x, %#04x), want (0x0000, 0xf00f) from word1 only", c.Match, c.Mask)
	}
	if !c.TwoWord {
		t.Error("TwoWord = false, want true")
	}
}

func TestClaimsRejectsBadCode(t *testing.T) {
	doc := fixtureDoc(t, map[string]any{
		"format": "bogus",
		"code":   "01100",
	})
	if _, err := Claims(doc); err == nil {
		t.Fatal("Claims accepted a 5-bit code, want error")
	}
}

func TestClaimedBy(t *testing.T) {
	c := Claim{Variants: []string{"SH1", "SH4"}}
	if !c.ClaimedBy(map[string]bool{"SH4": true}) {
		t.Error("ClaimedBy({SH4}) = false, want true")
	}
	if c.ClaimedBy(map[string]bool{"SH2A": true}) {
		t.Error("ClaimedBy({SH2A}) = true, want false")
	}
}

func TestVariantsCoversDocColumns(t *testing.T) {
	want := []string{"DSP", "J1", "J2", "J2A", "J4", "SH1", "SH2", "SH2A", "SH2E", "SH3", "SH3E", "SH4", "SH4A"}
	if got := Variants(); !reflect.DeepEqual(got, want) {
		t.Errorf("Variants() = %v, want %v", got, want)
	}
}
