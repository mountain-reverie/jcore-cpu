package insns

import (
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestForPrefersMeasured(t *testing.T) {
	tab := &Table{
		Overrides: map[string]Timing{"0100nnnn10010100": {Issue: II(1), Latency: II(1)}},
		Measured:  map[string]Timing{"0100nnnn10010100": {Issue: II(33), Latency: II(33)}},
	}
	in := spec.Instr{Opcode: "0100 nnnn 1001 0100"}
	got := tab.For(in)
	if got.Latency.String() != "33" {
		t.Fatalf("want measured 33, got %s", got.Latency)
	}
}

func TestVariableCellRoundTrips(t *testing.T) {
	c := ParseCell("2+")
	if !c.Variable || c.N != 2 || c.String() != "2+" {
		t.Fatalf("bad cell: %+v", c)
	}
}
