package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestProfileDropsInstrFromBuild(t *testing.T) {
	s, err := spec.Load(filepath.Join("..", "..", "spec"))
	if err != nil {
		t.Fatal(err)
	}
	prof, err := spec.ReadProfile(filepath.Join("..", "..", "spec", "profiles", "j1.toml"))
	if err != nil {
		t.Skip("j1 profile not present yet")
	}
	if err := spec.ApplyDrops(s, prof.Drop); err != nil {
		t.Fatal(err)
	}
	for _, in := range s.Instrs {
		if strings.HasPrefix(in.Name, "CAS.L") {
			t.Fatalf("CAS.L still in Instrs after drop")
		}
	}
	d, err := model.Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(d.Body.IllegalInstr, `x"2003"`) {
		t.Fatalf("CAS.L not routed to illegal: %q", d.Body.IllegalInstr)
	}
	_ = os.Stdout
}
