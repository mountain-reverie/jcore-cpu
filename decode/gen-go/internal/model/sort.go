package model

import (
	"sort"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/microcode"
)

// sortedSignals returns the keys of an AssignMap sorted lexicographically
// by the Signal's string form. Used wherever we need a deterministic
// iteration order over an AssignMap (every code path that contributes
// to generated VHDL must iterate deterministically — Go map iteration
// is randomized).
func sortedSignals(am microcode.AssignMap) []microcode.Signal {
	keys := make([]microcode.Signal, 0, len(am))
	for k := range am {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		return string(keys[i]) < string(keys[j])
	})
	return keys
}
