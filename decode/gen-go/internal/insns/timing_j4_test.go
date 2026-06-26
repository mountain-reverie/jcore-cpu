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

	// mul.l: array multiplier (mult=2) → latency 2, matching J2
	mulL := spec.Instr{
		Opcode: "0000nnnnmmmm0111",
		Slots:  []spec.Slot{{"mac_op": "MULL", "mac_stage": "EX"}},
	}
	j4tm := j4tab.For(mulL)
	j2tm := j2tab.For(mulL)
	if j4tm.Latency != j2tm.Latency {
		t.Errorf("mul.l: J4 latency %d != J2 latency %d (want equal, not J1's ~34)", j4tm.Latency, j2tm.Latency)
	}
	if j4tm.Latency != 2 {
		t.Errorf("mul.l: J4 latency %d, want 2 (array multiplier)", j4tm.Latency)
	}
}
