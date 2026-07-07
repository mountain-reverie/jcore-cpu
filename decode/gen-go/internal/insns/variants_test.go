package insns

import "testing"

func TestVariantsTable(t *testing.T) {
	vs := Variants()
	if len(vs) != 4 || vs[0].Name != "J2" || vs[1].Name != "J1" || vs[2].Name != "J4" || vs[3].Name != "J2A" {
		t.Fatalf("unexpected variants: %+v", vs)
	}
	if len(vs[2].Overlays) != 1 {
		t.Fatalf("J4 should carry one overlay, got %v", vs[2].Overlays)
	}
	// Guard against rename of J4's overlay
	if len(vs[2].Overlays) > 0 && vs[2].Overlays[0] != "sh4" {
		t.Fatalf("J4 overlay should be 'sh4', got %s", vs[2].Overlays[0])
	}
	// Guard against change in J4's group
	if vs[2].Group != "System Control Instructions" {
		t.Fatalf("J4 Group should be 'System Control Instructions', got %s", vs[2].Group)
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

func TestLoadVariantJ4OverlayCount(t *testing.T) {
	vs := Variants()
	if len(vs) < 3 {
		t.Fatalf("expected at least 3 variants, got %d", len(vs))
	}
	j4 := vs[2]
	is, err := LoadVariant("../../spec", j4)
	if err != nil {
		t.Fatalf("failed to load J4 variant: %v", err)
	}
	if len(is.Order) <= 154 {
		t.Fatalf("J4 overlay did not add instructions: expected > 154, got %d", len(is.Order))
	}
}

func TestJ2AVariantRegistered(t *testing.T) {
	var found bool
	for _, v := range Variants() {
		if v.Name == "J2A" {
			found = true
			if len(v.Overlays) != 1 || v.Overlays[0] != "sh2a" {
				t.Errorf("J2A overlays = %v", v.Overlays)
			}
		}
	}
	if !found {
		t.Fatal("J2A variant not registered")
	}
}
