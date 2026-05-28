// Package logic ports the Clojure cpugen/logic.clj module: Quine-McCluskey
// minimization plus helpers that bridge between bit-pattern strings,
// instruction opcodes, and VHDL expressions. It does not depend on any
// other internal package so QMC can be tested in isolation.
package logic

// SigBit names one bit of an addressable bit-field. Sig is the bus name
// ("i" for instruction code, "p" for plane bit); Bit is the LSB-0 index
// within that field. Mirrors the Clojure [:i N] / [:p N] tuples.
type SigBit struct {
	Sig string
	Bit int
}

// LogicMap is one Boolean minterm or implicant. Keys not in the map are
// don't-cares. Values are 0 or 1.
type LogicMap map[SigBit]int

// Clone returns a deep copy of m.
func (m LogicMap) Clone() LogicMap {
	out := make(LogicMap, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}

// Implicant pairs a logic map with the set of original minterms it covers,
// used during Petrick's method.
type Implicant struct {
	Map     LogicMap
	Covered map[int]bool // indices into the original minterm list
}
