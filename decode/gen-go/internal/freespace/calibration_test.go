package freespace

import (
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/insns"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/opcode"
)

// realClaims loads the actual docs/insns.json. This is the one test allowed
// to depend on it; everything else uses fixtures so ISA growth cannot break
// the suite.
func realClaims(t *testing.T) []Claim {
	t.Helper()
	doc, err := insns.Load("../../../../docs/insns.json")
	if err != nil {
		t.Fatalf("load insns.json: %v", err)
	}
	claims, err := Claims(doc)
	if err != nil {
		t.Fatalf("Claims: %v", err)
	}
	if len(claims) < 300 {
		t.Fatalf("got %d claims, want the full document (>=300 rows)", len(claims))
	}
	return claims
}

func TestNeverProposesAnOccupiedEncoding(t *testing.T) {
	claims := realClaims(t)
	avoid := []string{"SH1", "SH2", "SH2A", "SH4", "SH4A", "J1", "J2", "J4", "J2A"}
	avoidSet := map[string]bool{}
	for _, v := range avoid {
		avoidSet[v] = true
	}
	// A wide-open form: every Rm,Rn-shaped encoding in the whole 16-bit space.
	cands, err := Search(Options{Form: "----nnnnmmmm----", Avoid: avoid}, claims)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(cands) == 0 {
		t.Fatal("no candidates at all; the search is over-rejecting")
	}
	for _, c := range cands {
		for _, cl := range claims {
			if !cl.ClaimedBy(avoidSet) {
				continue
			}
			if opcode.Overlaps(c.Match, c.Mask, cl.Match, cl.Mask) {
				t.Fatalf("proposed %s, which overlaps %s claimed by %v",
					c.Code, cl.Format, cl.Variants)
			}
		}
	}
}

func TestKnownOccupiedEncodingIsNeverOffered(t *testing.T) {
	claims := realClaims(t)
	// 0110nnnnmmmm0011 is "mov Rm,Rn", present since SH1.
	cands, err := Search(Options{Form: "0110nnnnmmmm00--", Avoid: []string{"SH1"}}, claims)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	for _, c := range cands {
		if c.Code == "0110nnnnmmmm0011" {
			t.Fatal("offered mov Rm,Rn's encoding while avoiding SH1")
		}
	}
}
