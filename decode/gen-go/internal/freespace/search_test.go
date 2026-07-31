package freespace

import (
	"strings"
	"testing"
)

func claim(t *testing.T, code, format, group string, variants ...string) Claim {
	t.Helper()
	doc := fixtureDoc(t, map[string]any{
		"code": code, "format": format, "group": group,
	})
	cs, err := Claims(doc)
	if err != nil {
		t.Fatalf("Claims(%q): %v", code, err)
	}
	c := cs[0]
	c.Variants = variants
	return c
}

func codes(cands []Candidate) []string {
	out := make([]string, len(cands))
	for i, c := range cands {
		out[i] = c.Code
	}
	return out
}

func TestSearchEnumeratesFreeBits(t *testing.T) {
	// Two free bits at the bottom -> four candidates, no claims to dodge.
	got, err := Search(Options{Form: "0110nnnnmmmm00--"}, nil)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	want := []string{
		"0110nnnnmmmm0000", "0110nnnnmmmm0001",
		"0110nnnnmmmm0010", "0110nnnnmmmm0011",
	}
	if strings.Join(codes(got), ",") != strings.Join(want, ",") {
		t.Errorf("codes = %v, want %v", codes(got), want)
	}
	for _, c := range got {
		if !c.Virgin {
			t.Errorf("%s: Virgin = false, want true (no claims given)", c.Code)
		}
	}
}

func TestSearchDropsAvoidedCollisions(t *testing.T) {
	claims := []Claim{
		claim(t, "0110nnnnmmmm0011", "mov\tRm,Rn", "Data Transfer Instructions", "SH1", "J2"),
	}
	got, err := Search(Options{Form: "0110nnnnmmmm00--", Avoid: []string{"J2"}}, claims)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	for _, c := range got {
		if c.Code == "0110nnnnmmmm0011" {
			t.Fatal("returned an encoding claimed by an avoided variant")
		}
	}
	if len(got) != 3 {
		t.Errorf("got %d candidates, want 3", len(got))
	}
}

func TestSearchOverlapNotJustEquality(t *testing.T) {
	// The claim's m-field spans the candidate's fixed bits. Key equality
	// would not catch this; overlap must.
	claims := []Claim{
		claim(t, "0000nnnnmmmm1011", "wide\tRm,Rn", "Logic Operation Instructions", "SH4"),
	}
	got, err := Search(Options{Form: "0000nnnn11--1011", Avoid: []string{"SH4"}}, claims)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(got) != 0 {
		t.Errorf("got %v, want none: every candidate overlaps the claim", codes(got))
	}
}

func TestSearchReportsShadowsForNonAvoidedClaims(t *testing.T) {
	claims := []Claim{
		claim(t, "0110nnnnmmmm0011", "mov\tRm,Rn", "Data Transfer Instructions", "SH4A"),
	}
	got, err := Search(Options{Form: "0110nnnnmmmm00--", Avoid: []string{"J2"}}, claims)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	var found *Candidate
	for i := range got {
		if got[i].Code == "0110nnnnmmmm0011" {
			found = &got[i]
		}
	}
	if found == nil {
		t.Fatal("candidate free w.r.t. --avoid was dropped, want it kept and flagged")
	}
	if found.Virgin {
		t.Error("Virgin = true, want false: SH4A claims it")
	}
	if len(found.Shadows) != 1 || !strings.HasPrefix(found.Shadows[0], "SH4A: mov") {
		t.Errorf("Shadows = %v, want one SH4A entry", found.Shadows)
	}
}

func TestSearchRegionFilter(t *testing.T) {
	got, err := Search(Options{Form: "----nnnnmmmm0011", Regions: []string{"4", "8"}}, nil)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	want := []string{"0100nnnnmmmm0011", "1000nnnnmmmm0011"}
	if strings.Join(codes(got), ",") != strings.Join(want, ",") {
		t.Errorf("codes = %v, want %v", codes(got), want)
	}
}

func TestSearchTwoWordSharesWord1(t *testing.T) {
	claims := []Claim{
		claim(t, "0000nnnniiii0000 iiiiiiiiiiiiiiii", "movi20\t#imm20,Rn",
			"Data Transfer Instructions", "SH2A"),
	}
	// Without --two-word this is a hard collision.
	got, err := Search(Options{Form: "0000nnnniiii000-", Avoid: []string{"SH2A"}}, claims)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(got) != 1 || got[0].Code != "0000nnnniiii0001" {
		t.Errorf("single-word search = %v, want only 0000nnnniiii0001", codes(got))
	}
	// With --two-word the shared word1 is reported as shareable, not dropped.
	got, err = Search(Options{Form: "0000nnnniiii000-", Avoid: []string{"SH2A"}, TwoWord: true}, claims)
	if err != nil {
		t.Fatalf("Search: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("two-word search = %v, want 2 candidates", codes(got))
	}
	if len(got[0].Shareable) != 1 {
		t.Errorf("Shareable = %v, want the movi20 word1", got[0].Shareable)
	}
}

func TestSearchRejectsBadForm(t *testing.T) {
	if _, err := Search(Options{Form: "0110"}, nil); err == nil {
		t.Error("Search accepted a 4-bit form, want error")
	}
	if _, err := Search(Options{Form: "----------------", Regions: []string{"zz"}}, nil); err == nil {
		t.Error("Search accepted a non-hex region, want error")
	}
	if _, err := Search(Options{Form: "----------------", Avoid: []string{"SH9"}}, nil); err == nil {
		t.Error("Search accepted an unknown variant, want error")
	}
}
