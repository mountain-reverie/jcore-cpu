package insns

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDocRoundTripPreservesOrder(t *testing.T) {
	src := []byte(`{
  "instructions": [
    {
      "group": "Data Transfer Instructions",
      "SH1": true,
      "code": "0110nnnnmmmm0011"
    }
  ]
}
`)
	p := filepath.Join(t.TempDir(), "in.json")
	if err := os.WriteFile(p, src, 0o644); err != nil {
		t.Fatal(err)
	}
	d, err := Load(p)
	if err != nil {
		t.Fatal(err)
	}
	out, err := d.Bytes()
	if err != nil {
		t.Fatal(err)
	}
	if string(out) != string(src) {
		t.Fatalf("round-trip changed bytes:\n--- got ---\n%s\n--- want ---\n%s", out, src)
	}
}

func TestRowSetUpdatesInPlaceAndAppends(t *testing.T) {
	r := &Row{}
	r.Set("a", true)
	r.Set("b", 1)
	r.Set("a", false) // update, must not reorder
	if got := r.keys; len(got) != 2 || got[0] != "a" || got[1] != "b" {
		t.Fatalf("key order wrong: %v", got)
	}
	if v, _ := r.Get("a"); v != false {
		t.Fatalf("update failed: %v", v)
	}
}
