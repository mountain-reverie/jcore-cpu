package insns

import (
	"path/filepath"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestJ1TimingModel(t *testing.T) {
	tab, err := LoadTable(filepath.Join("..", "..", "timing", "j1.toml"))
	if err != nil {
		t.Fatalf("LoadTable j1.toml: %v", err)
	}

	tests := []struct {
		name        string
		instr       spec.Instr
		wantLatency int
		cmp         string // "==" or ">="
	}{
		{
			name: "mul.l sequential multiplier",
			instr: spec.Instr{
				Opcode: "0000nnnnmmmm0111",
				Slots:  []spec.Slot{{"mac_op": "MULL", "mac_stage": "EX"}},
			},
			wantLatency: 30,
			cmp:         ">=",
		},
		{
			name:        "shll16 iterative shift",
			instr:       spec.Instr{Opcode: "0100nnnn00101000"},
			wantLatency: 16,
			cmp:         "==",
		},
		{
			name:        "shll8 iterative shift",
			instr:       spec.Instr{Opcode: "0100nnnn00011000"},
			wantLatency: 8,
			cmp:         "==",
		},
		{
			name:        "shad dynamic worst-case",
			instr:       spec.Instr{Opcode: "0100nnnnmmmm1100"},
			wantLatency: 32,
			cmp:         "==",
		},
		{
			name:        "shll 1-bit shift unchanged",
			instr:       spec.Instr{Opcode: "0100nnnn00000000"},
			wantLatency: 1,
			cmp:         "==",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tab.For(tc.instr)
			switch tc.cmp {
			case ">=":
				if got.Latency < tc.wantLatency {
					t.Errorf("latency %d < %d", got.Latency, tc.wantLatency)
				}
			default: // "=="
				if got.Latency != tc.wantLatency {
					t.Errorf("latency %d != %d", got.Latency, tc.wantLatency)
				}
			}
		})
	}
}
