package freespace

import "testing"

func TestRankVirginFirst(t *testing.T) {
	cands := []Candidate{
		{Code: "0100nnnnmmmm0001", Match: 0x4001, Virgin: false, Shadows: []string{"SH4A: x"}},
		{Code: "0100nnnnmmmm0010", Match: 0x4002, Virgin: true},
	}
	Rank(cands, "", nil)
	if cands[0].Code != "0100nnnnmmmm0010" {
		t.Errorf("first = %s, want the virgin candidate 0100nnnnmmmm0010", cands[0].Code)
	}
}

func TestRankFamilyProximity(t *testing.T) {
	claims := []Claim{
		claim(t, "0100nnnnmmmm1100", "shad\tRm,Rn", "Shift Instructions", "SH4"),
	}
	cands := []Candidate{
		// Hamming distance 4 from the family member.
		{Code: "0100nnnnmmmm0011", Match: 0x4003, Mask: 0xF00F, Virgin: true},
		// Hamming distance 1.
		{Code: "0100nnnnmmmm1110", Match: 0x400E, Mask: 0xF00F, Virgin: true},
	}
	Rank(cands, "Shift Instructions", claims)
	if cands[0].Code != "0100nnnnmmmm1110" {
		t.Errorf("first = %s, want 0100nnnnmmmm1110 (nearest to the family)", cands[0].Code)
	}
}

func TestRankNumericTieBreak(t *testing.T) {
	cands := []Candidate{
		{Code: "0100nnnnmmmm0010", Match: 0x4002, Virgin: true},
		{Code: "0100nnnnmmmm0001", Match: 0x4001, Virgin: true},
	}
	Rank(cands, "", nil)
	if cands[0].Match != 0x4001 {
		t.Errorf("first match = %#04x, want 0x4001", cands[0].Match)
	}
}

func TestNearestIgnoresOtherFamilies(t *testing.T) {
	claims := []Claim{
		claim(t, "0100nnnnmmmm1110", "near\tRm,Rn", "Shift Instructions", "SH4"),
		claim(t, "0100nnnnmmmm1111", "far\tRm,Rn", "Logic Operation Instructions", "SH4"),
	}
	c := Candidate{Code: "0100nnnnmmmm1111", Match: 0x400F, Mask: 0xF00F}
	got, ok := Nearest(c, "Shift Instructions", claims)
	if !ok {
		t.Fatal("Nearest found nothing, want the Shift Instructions claim")
	}
	if got.Format != "near\tRm,Rn" {
		t.Errorf("Nearest = %q, want the same-family claim despite the exact match in another family", got.Format)
	}
}

func TestNearestNoFamily(t *testing.T) {
	if _, ok := Nearest(Candidate{}, "", nil); ok {
		t.Error("Nearest with no family reported a result, want none")
	}
}
