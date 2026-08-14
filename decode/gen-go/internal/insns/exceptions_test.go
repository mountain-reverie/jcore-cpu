package insns

import (
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestExceptionsForVariantSplit pins the case that motivated the annotation:
// the PC-relative fetches are slot-illegal on J4 and NOT on J2. That split was
// invisible before this field existed, and getting it backwards hangs the J2
// test ROM (testrom/tests/testmov2.s).
func TestExceptionsForVariantSplit(t *testing.T) {
	const slotIll = "Slot illegal instruction exception"
	pcRel := "MOVA @(disp, PC), R0"
	branch := "BT label"

	load := func(t *testing.T, v Variant) map[string]spec.Instr {
		t.Helper()
		set, err := LoadVariant("../../spec", v)
		if err != nil {
			t.Fatalf("%s: %v", v.Name, err)
		}
		m := map[string]spec.Instr{}
		for _, in := range set.Order {
			m[in.Name] = in
		}
		return m
	}

	has := func(t *testing.T, in spec.Instr, want string) bool {
		t.Helper()
		exc, err := exceptionsFor(in)
		if err != nil {
			t.Fatalf("%s: %v", in.Name, err)
		}
		for _, e := range exc {
			if e == want {
				return true
			}
		}
		return false
	}

	var j2v, j4v Variant
	for _, v := range Variants() {
		switch v.Name {
		case "J2":
			j2v = v
		case "J4":
			j4v = v
		}
	}
	j2, j4 := load(t, j2v), load(t, j4v)

	if has(t, j2[pcRel], slotIll) {
		t.Errorf("%s must NOT be slot-illegal on J2 (SH-2 allows it in a delay slot)", pcRel)
	}
	if !has(t, j4[pcRel], slotIll) {
		t.Errorf("%s must be slot-illegal on J4", pcRel)
	}
	// The conditional branches are slot-illegal on every variant — they are the
	// half that is NOT variant-scoped.
	for name, m := range map[string]map[string]spec.Instr{"J2": j2, "J4": j4} {
		if !has(t, m[branch], slotIll) {
			t.Errorf("%s must be slot-illegal on %s", branch, name)
		}
	}
}

// TestExceptionsForPrivileged: a privileged instruction reports General
// Illegal, and is NOT marked slot-illegal — it is legal in a delay slot in
// supervisor mode. See exceptionsFor's note on the reclassification.
func TestExceptionsForPrivileged(t *testing.T) {
	set, err := LoadVariant("../../spec", Variant{Name: "J2"})
	if err != nil {
		t.Fatal(err)
	}
	for _, in := range set.Order {
		if in.Name != "STC SR, Rn" {
			continue
		}
		exc, err := exceptionsFor(in)
		if err != nil {
			t.Fatal(err)
		}
		want := []string{"General illegal instruction exception"}
		if len(exc) != len(want) || exc[0] != want[0] {
			t.Errorf("STC SR, Rn exceptions = %v, want %v", exc, want)
		}
		return
	}
	t.Fatal("STC SR, Rn not found in the J2 spec")
}
