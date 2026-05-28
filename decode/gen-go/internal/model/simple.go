package model

import (
	"fmt"
	"sort"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/logic"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/microcode"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// SimpleDecoder is the emission-ready view of decode_table_simple.vhd.
// Instructions are sorted by StdMatchPattern for diff stability; the
// Clojure golden uses a different (bin-packing-optimized) order, so
// L1 diff is expected.
type SimpleDecoder struct {
	Instructions []SimpleInstr
}

// SimpleInstr is one if/elsif arm of the main decode process.
type SimpleInstr struct {
	Name            string
	OpcodeHex       string // e.g. "0x300C" — for comment
	Operation       string // human-readable description from the spec (e.g. "no operation")
	StdMatchPattern string // 17-character pattern ("00100--00000000")
	Slots           []SimpleSlotArm
}

// SimpleSlotArm is one case-when arm for op.addr(3 downto 0). Index is
// 0..15 (matching x"0".."xF"). Assignments are the per-slot direct
// signal-name → value-text pairs sorted for stability.
type SimpleSlotArm struct {
	Index       int
	Assignments []SimpleAssignment
}

// SimpleAssignment renders as "lhs <= rhs;" inside a slot case arm.
// LHS is the full VHDL signal path ("ex.regnum_x", "id.incpc").
// RHS is the VHDL expression text. The model precomputes both.
type SimpleAssignment struct {
	LHS string
	RHS string
}

// BuildSimple constructs the SimpleDecoder model from the spec, the
// resolved per-instruction LogicMaps, and the per-(instruction, slot)
// AssignMaps. System-plane instructions are INCLUDED — the simple
// decoder table must drive their if_issue/dispatch slots for the
// interrupt/exception handling path. Their LogicMaps in instrLogic
// must carry plane=1 (built upstream).
func BuildSimple(s *spec.Spec, instrLogic map[string]logic.LogicMap,
	slotAssigns map[string][]microcode.AssignMap) *SimpleDecoder {
	sd := &SimpleDecoder{}
	for _, si := range s.Instrs {
		m, ok := instrLogic[si.Name]
		if !ok {
			continue // not in LogicMap (shouldn't happen for production spec)
		}
		// 17 bits: 1 plane + 16 opcode.
		opPart := logic.LogicMapToStdMatch(m, "i", 16)
		planePart := logic.LogicMapToStdMatch(m, "p", 1)
		pattern := planePart + opPart
		ams, ok := slotAssigns[si.Name]
		if !ok {
			continue // no slots — skip
		}
		instr := SimpleInstr{
			Name:            si.Name,
			OpcodeHex:       fmt.Sprintf("0x%X", representativeHex(m)),
			Operation:       si.Operation,
			StdMatchPattern: pattern,
		}
		for i, am := range ams {
			arm := SimpleSlotArm{Index: i}
			arm.Assignments = simpleAssignmentsFor(am)
			instr.Slots = append(instr.Slots, arm)
		}
		sd.Instructions = append(sd.Instructions, instr)
	}
	sort.Slice(sd.Instructions, func(i, j int) bool {
		return sd.Instructions[i].StdMatchPattern < sd.Instructions[j].StdMatchPattern
	})
	return sd
}

// representativeHex returns a 16-bit value with all fixed bits set
// and don't-cares zeroed. Used for the comment heading; not for matching.
func representativeHex(m logic.LogicMap) uint16 {
	var v uint16
	for k, val := range m {
		if k.Sig != "i" || val != 1 {
			continue
		}
		v |= 1 << k.Bit
	}
	return v
}

// simpleAssignmentsFor translates an AssignMap into ordered SimpleAssignment
// pairs. The LHS uses the VHDL record-field path (ex.X, ex_stall.X,
// wb_stall.X, id.X, or scalar) determined by Signal name lookup.
func simpleAssignmentsFor(am microcode.AssignMap) []SimpleAssignment {
	keys := sortedSignals(am)
	var out []SimpleAssignment
	for _, k := range keys {
		lhs := signalLHS(k)
		rhs := am[k]
		if rhs == "" {
			continue
		}
		out = append(out, SimpleAssignment{LHS: lhs, RHS: signalRHS(k, rhs)})
	}
	return out
}

// signalLHS returns the VHDL record-field path on the LHS of a decoder
// assignment for s. The mapping lives in microcode.SignalVHDLPath;
// exhaustiveness is enforced by TestSignalVHDLPathCoversAllSignals.
func signalLHS(s microcode.Signal) string {
	if path, ok := microcode.SignalVHDLPath[s]; ok {
		return path
	}
	panic(fmt.Sprintf("signalLHS: no VHDL path for signal %q", s))
}

// signalRHS quotes/formats a value for the given signal's VHDL type.
// std_logic signals get '1'/'0' quoted when the value is a single
// character; multi-character values (e.g. "t_bcc", "not t_bcc") are
// VHDL expressions and render bare. Regnum signals translate their
// tag (R0, R15, GBR, RA, RB, ...) to the corresponding 5-bit literal
// or opcode-slice expression via microcode.RegnumVHDL. Enum literals
// (SEL_REG, etc.) render bare.
func signalRHS(s microcode.Signal, v string) string {
	if s.IsStdLogic() && len(v) == 1 {
		return "'" + v + "'"
	}
	switch s {
	case microcode.SigRegnumX, microcode.SigRegnumY,
		microcode.SigRegnumZ, microcode.SigRegnumW:
		if vhdl := microcode.RegnumVHDL(v); vhdl != "" {
			return vhdl
		}
	}
	return v
}
