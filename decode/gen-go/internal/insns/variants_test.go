package insns

import "testing"

func TestVariantsTable(t *testing.T) {
	vs := Variants()
	if len(vs) != 3 || vs[0].Name != "J2" || vs[1].Name != "J1" || vs[2].Name != "J4" {
		t.Fatalf("unexpected variants: %+v", vs)
	}
	if len(vs[2].Overlays) != 1 {
		t.Fatalf("J4 should carry one overlay, got %v", vs[2].Overlays)
	}
}

func TestLoadVariantExcludesSystemPlane(t *testing.T) {
	is, err := LoadVariant("../../spec", Variant{Name: "J2"})
	if err != nil {
		t.Fatal(err)
	}
	for _, in := range is.Order {
		if in.Plane == "system" {
			t.Fatalf("system-plane instr leaked: %s", in.Name)
		}
	}
	if len(is.Order) == 0 {
		t.Fatal("expected non-empty instruction set")
	}
}
