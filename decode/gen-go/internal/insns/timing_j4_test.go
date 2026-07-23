package insns

import (
	"path/filepath"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestJ4TimingMatchesJ2(t *testing.T) {
	j4tab, err := LoadTable(filepath.Join("..", "..", "timing", "j4.toml"))
	if err != nil {
		t.Fatalf("LoadTable j4.toml: %v", err)
	}
	j2tab, err := LoadTable(filepath.Join("..", "..", "timing", "j2.toml"))
	if err != nil {
		t.Fatalf("LoadTable j2.toml: %v", err)
	}

	// mul.l: J4 and J2 share the array multiplier, so they must have the same
	// mul.l latency — and it must be the array value (measured ~4 on the sim's
	// mult), never J1's sequential ~34. The exact value now comes from the
	// measured timing tables, so assert the J4==J2 invariant + an array-vs-seq
	// bound rather than a frozen constant.
	mulL := spec.Instr{
		Opcode: "0000nnnnmmmm0111",
		Slots:  []spec.Slot{{"mac_op": "MULL", "mac_stage": "EX"}},
	}
	j4tm := j4tab.For(mulL)
	j2tm := j2tab.For(mulL)
	if j4tm.Latency.N != j2tm.Latency.N {
		t.Errorf("mul.l: J4 latency %d != J2 latency %d (want equal, not J1's ~34)", j4tm.Latency.N, j2tm.Latency.N)
	}
	if j4tm.Latency.N <= 0 || j4tm.Latency.N >= 10 {
		t.Errorf("mul.l: J4 latency %d out of array-multiplier range (want the shared J2 array value, not J1's ~34)", j4tm.Latency.N)
	}
}
