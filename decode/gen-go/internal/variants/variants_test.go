package variants

import "testing"

func TestLoadJ4(t *testing.T) {
	m, err := Load("../../../../variants.toml")
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	j4, ok := m["j4"]
	if !ok {
		t.Fatal("j4 variant missing")
	}
	if j4.Generics["PRIV_ARCH"] != "true" {
		t.Errorf("PRIV_ARCH = %q, want true", j4.Generics["PRIV_ARCH"])
	}
	if _, bad := j4.Generics["MMU_ARCH"]; bad {
		t.Error("MMU_ARCH must not exist: PRIV_ARCH implies MMU")
	}
	if j4.Overlay != "sh4" {
		t.Errorf("Overlay = %q, want sh4", j4.Overlay)
	}
	if len(j4.ExtraFiles) != 1 || j4.ExtraFiles[0] != "core/tlb.vhd" {
		t.Errorf("ExtraFiles = %v, want [core/tlb.vhd]", j4.ExtraFiles)
	}
}

func TestJ2HasNoGenericsAndNoOverlay(t *testing.T) {
	m, err := Load("../../../../variants.toml")
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	j2 := m["j2"]
	if len(j2.Generics) != 0 {
		t.Errorf("j2 generics = %v, want empty", j2.Generics)
	}
	if j2.Overlay != "" {
		t.Errorf("j2 overlay = %q, want empty", j2.Overlay)
	}
}

func TestNamesSorted(t *testing.T) {
	m, _ := Load("../../../../variants.toml")
	got := Names(m)
	want := []string{"j1", "j2", "j2a", "j4"}
	if len(got) != len(want) {
		t.Fatalf("Names = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("Names = %v, want %v", got, want)
		}
	}
}
