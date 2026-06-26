package insns

import (
	"path/filepath"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestTimingBaseIsSlotCount(t *testing.T) {
	tab := &Table{}
	in := spec.Instr{Opcode: "0110nnnnmmmm0011", Slots: []spec.Slot{{}, {}}}
	if got := tab.For(in); got.Issue != 1 || got.Latency != 2 {
		t.Fatalf("base 2-slot: got %+v want issue1 latency2", got)
	}
}

func TestTimingOverrideWins(t *testing.T) {
	tab := &Table{Overrides: map[string]Timing{"11000011iiiiiiii": {Issue: 2, Latency: 8}}}
	in := spec.Instr{Opcode: "1100 0011 iiii iiii", Slots: []spec.Slot{{}}}
	got := tab.For(in)
	if got.Issue != 2 || got.Latency != 8 {
		t.Fatalf("override: got %+v want 2/8", got)
	}
}

func TestLoadTable(t *testing.T) {
	p := filepath.Join("testdata", "timing_min.toml")
	tab, err := LoadTable(p)
	if err != nil {
		t.Fatal(err)
	}
	if tab.Units["mult"] == 0 {
		t.Fatal("expected mult unit cost from table")
	}
}

func TestTimingMultUnit(t *testing.T) {
	tab := &Table{Units: map[string]int{"mult": 3}}
	// MUL.L-like: 1 slot with mac_op set
	in := spec.Instr{
		Opcode: "0000nnnnmmmm0111",
		Slots:  []spec.Slot{{"mac_op": "MULL", "mac_stage": "EX"}},
	}
	got := tab.For(in)
	if got.Issue != 3 {
		t.Fatalf("mult unit: got issue=%d want 3", got.Issue)
	}
}
