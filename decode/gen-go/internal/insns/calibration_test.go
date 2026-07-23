package insns

import (
	"encoding/json"
	"os"
	"testing"
)

// TestJ2DerivedMatchesCommitted verifies that the timing heuristic + j2.toml
// overrides reproduce the hand-authored J2 columns captured in the frozen
// fixture. The fixture is the source of truth; docs/insns.json is NOT read
// here to avoid comparing derived-vs-derived after regeneration.
func TestJ2DerivedMatchesCommitted(t *testing.T) {
	type committed struct {
		J2      bool `json:"J2"`
		Issue   int  `json:"issue"`
		Latency int  `json:"latency"`
	}

	raw, err := os.ReadFile("testdata/j2_committed.json")
	if err != nil {
		t.Fatal(err)
	}
	var snapshot map[string]committed
	if err := json.Unmarshal(raw, &snapshot); err != nil {
		t.Fatal(err)
	}

	set, err := LoadVariant("../../spec", Variant{Name: "J2"})
	if err != nil {
		t.Fatal(err)
	}
	tab, err := LoadTable("../../timing/j2.toml")
	if err != nil {
		t.Fatal(err)
	}

	// Build a map from normOpcode → spec.Instr for fast lookup.
	byCode := map[string]bool{}
	for _, in := range set.Order {
		byCode[normOpcode(in.Opcode)] = true
	}

	var diffs int
	for code, want := range snapshot {
		// Find instruction in spec.
		in, found := set.ByKey[mustKey(t, code)]
		if !found {
			t.Logf("SKIP %s: not in J2 spec (system-plane?)", code)
			continue
		}
		got := tab.For(in)
		if got.Issue.N != want.Issue || got.Latency.N != want.Latency {
			diffs++
			t.Logf("MISMATCH %s: got issue=%d latency=%d  want issue=%d latency=%d",
				code, got.Issue.N, got.Latency.N, want.Issue, want.Latency)
		}
	}
	if diffs != 0 {
		t.Fatalf("%d J2 rows differ from committed snapshot; add overrides to timing/j2.toml", diffs)
	}
}

func mustKey(t *testing.T, code string) Key {
	t.Helper()
	k, ok := KeyOf(code)
	if !ok {
		t.Fatalf("cannot build key for %q", code)
	}
	return k
}
