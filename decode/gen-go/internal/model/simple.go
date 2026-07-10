package model

import (
	"fmt"
	"sort"
	"strings"

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

// SimpleInstr is one if/elsif arm of the main decode process. Ordinarily
// this is exactly one spec instruction. Two-word instructions that share
// word1 (their StdMatchPattern is identical -- e.g. SH-2A's MOV.L
// @(disp12,Rm),Rn / MOV.L Rm,@(disp12,Rn)) are merged into ONE arm by
// BuildSimple: GroupNames/GroupOps carry every member's name/operation
// (used for the comment header) and per-slot control fields that differ
// between members become an ext_word(15 downto 12) case inside that slot
// (see SimpleSlotArm.ExtCases). Without this merge, the elsif chain would
// contain two arms with byte-identical std_match conditions and the first
// would permanently shadow the second.
type SimpleInstr struct {
	Name            string
	GroupNames      []string // >1 entries iff this arm merges a word1-colliding two-word group
	OpcodeHex       string   // e.g. "0x300C" — for comment
	Operation       string   // human-readable description from the spec (e.g. "no operation")
	StdMatchPattern string   // 17-character pattern ("00100--00000000")
	Slots           []SimpleSlotArm
}

// SimpleSlotArm is one case-when arm for op.addr(3 downto 0). Index is
// 0..15 (matching x"0".."xF"). Assignments are the per-slot direct
// signal-name → value-text pairs sorted for stability (control fields that
// are identical across every member of a merged two-word group, or the
// entirety of a non-merged instruction's slot). ExtCases holds the
// per-member fields that DIFFER across a merged group, nested behind a
// "case ext_word(15 downto 12)" -- empty for non-merged instructions.
type SimpleSlotArm struct {
	Index       int
	Assignments []SimpleAssignment
	ExtCases    []SimpleExtCase
}

// SimpleExtCase is one "when x\"N\" =>" arm of the ext_word(15 downto 12)
// case nested inside a merged two-word group's slot arm. Nibble is the
// single hex digit (e.g. "6", "2") for that group member's fixed
// opcode2[15:12] value.
type SimpleExtCase struct {
	Nibble      string
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

	// byPattern groups instruction names by StdMatchPattern (word1+plane).
	// Ordinarily each group has exactly one member; two-word instructions
	// that collide on word1 (disambiguated only by ext_word[15:12])
	// produce groups with >1 member, which are merged below instead of
	// emitted as separate (and for the 2nd..Nth member, permanently
	// shadowed) elsif arms.
	type patInfo struct {
		pattern string
		hex     string
	}
	info := make(map[string]patInfo, len(s.Instrs))
	byPattern := make(map[string][]string)
	var order []string // pattern discovery order, for stable-ish grouping
	for _, si := range s.Instrs {
		m, ok := instrLogic[si.Name]
		if !ok {
			continue // not in LogicMap (shouldn't happen for production spec)
		}
		if _, ok := slotAssigns[si.Name]; !ok {
			continue // no slots — skip
		}
		opPart := logic.LogicMapToStdMatch(m, "i", 16)
		planePart := logic.LogicMapToStdMatch(m, "p", 1)
		pattern := planePart + opPart
		info[si.Name] = patInfo{pattern: pattern, hex: fmt.Sprintf("0x%X", representativeHex(m))}
		if _, seen := byPattern[pattern]; !seen {
			order = append(order, pattern)
		}
		byPattern[pattern] = append(byPattern[pattern], si.Name)
	}

	opByName := make(map[string]string, len(s.Instrs))
	opcode2ByName := make(map[string]string, len(s.Instrs))
	for _, si := range s.Instrs {
		opByName[si.Name] = si.Operation
		opcode2ByName[si.Name] = si.Opcode2
	}

	for _, pattern := range order {
		names := byPattern[pattern]
		if len(names) == 1 {
			name := names[0]
			instr := SimpleInstr{
				Name:            name,
				OpcodeHex:       info[name].hex,
				Operation:       opByName[name],
				StdMatchPattern: pattern,
			}
			for i, am := range slotAssigns[name] {
				instr.Slots = append(instr.Slots, SimpleSlotArm{
					Index:       i,
					Assignments: simpleAssignmentsFor(am),
				})
			}
			sd.Instructions = append(sd.Instructions, instr)
			continue
		}
		// Word1 collision: merge into one arm, splitting per-slot fields
		// that differ across members behind ext_word(15 downto 12).
		instr, err := mergeSimpleGroup(names, pattern, info[names[0]].hex, opByName, opcode2ByName, slotAssigns)
		if err != nil {
			// Should not happen for a well-formed spec (spec.Validate
			// requires two-word instructions sharing word1 to have
			// distinct, fully-fixed opcode2 high nibbles). Fail loudly
			// rather than silently emit a shadowed/ambiguous arm.
			panic(fmt.Sprintf("BuildSimple: %v", err))
		}
		sd.Instructions = append(sd.Instructions, *instr)
	}

	sort.Slice(sd.Instructions, func(i, j int) bool {
		return sd.Instructions[i].StdMatchPattern < sd.Instructions[j].StdMatchPattern
	})
	return sd
}

// mergeSimpleGroup merges >=2 word1-colliding two-word instructions (names)
// into one SimpleInstr. Every member must declare a fully-fixed opcode2 high
// nibble (ext_word[15:12]) and the same slot count; per-slot fields that
// agree across every member stay in that slot's Assignments (common,
// unconditional), fields that differ (present with a different value, or
// present in only some members) move into that member's SimpleExtCase.
func mergeSimpleGroup(names []string, pattern, hex string,
	opByName, opcode2ByName map[string]string,
	slotAssigns map[string][]microcode.AssignMap) (*SimpleInstr, error) {

	type member struct {
		name   string
		nibble string // single hex digit, e.g. "6"
		slots  []microcode.AssignMap
	}
	members := make([]member, 0, len(names))
	for _, name := range names {
		nb, ok := hexNibble(opcode2ByName[name])
		if !ok {
			return nil, fmt.Errorf("instruction %q shares word1 pattern %q with %d other "+
				"instructions but its opcode2 high nibble is not fully fixed; cannot "+
				"discriminate by ext_word(15 downto 12)", name, pattern, len(names)-1)
		}
		members = append(members, member{name: name, nibble: nb, slots: slotAssigns[name]})
	}
	sort.Slice(members, func(i, j int) bool { return members[i].nibble < members[j].nibble })

	numSlots := len(members[0].slots)
	for _, mem := range members[1:] {
		if len(mem.slots) != numSlots {
			return nil, fmt.Errorf("word1-colliding group %v has mismatched slot counts "+
				"(%q has %d, %q has %d)", names, members[0].name, numSlots, mem.name, len(mem.slots))
		}
	}

	var groupNames, groupOps []string
	for _, mem := range members {
		groupNames = append(groupNames, mem.name)
		groupOps = append(groupOps, opByName[mem.name])
	}

	instr := &SimpleInstr{
		Name:            members[0].name,
		GroupNames:      groupNames,
		OpcodeHex:       hex,
		Operation:       strings.Join(groupOps, " / "),
		StdMatchPattern: pattern,
	}

	for slotIdx := 0; slotIdx < numSlots; slotIdx++ {
		arm := SimpleSlotArm{Index: slotIdx}

		// Union of signals assigned at this slot index across all members.
		allSigs := map[microcode.Signal]bool{}
		for _, mem := range members {
			for sig := range mem.slots[slotIdx] {
				allSigs[sig] = true
			}
		}
		var sigs []microcode.Signal
		for sig := range allSigs {
			sigs = append(sigs, sig)
		}
		sort.Slice(sigs, func(i, j int) bool { return string(sigs[i]) < string(sigs[j]) })

		common := microcode.AssignMap{}
		perMember := make([]microcode.AssignMap, len(members))
		for i := range perMember {
			perMember[i] = microcode.AssignMap{}
		}
		for _, sig := range sigs {
			vals := make([]string, len(members))
			presentEverywhere := true
			for i, mem := range members {
				v, ok := mem.slots[slotIdx][sig]
				if !ok {
					presentEverywhere = false
					continue
				}
				vals[i] = v
			}
			sameEverywhere := presentEverywhere
			if sameEverywhere {
				for i := 1; i < len(vals); i++ {
					if vals[i] != vals[0] {
						sameEverywhere = false
						break
					}
				}
			}
			if sameEverywhere {
				common[sig] = vals[0]
				continue
			}
			for i, mem := range members {
				if v, ok := mem.slots[slotIdx][sig]; ok {
					perMember[i][sig] = v
				}
			}
		}

		arm.Assignments = simpleAssignmentsFor(common)
		anyExt := false
		for _, am := range perMember {
			if len(am) > 0 {
				anyExt = true
				break
			}
		}
		if anyExt {
			for i, mem := range members {
				arm.ExtCases = append(arm.ExtCases, SimpleExtCase{
					Nibble:      mem.nibble,
					Assignments: simpleAssignmentsFor(perMember[i]),
				})
			}
		}
		instr.Slots = append(instr.Slots, arm)
	}
	return instr, nil
}

// hexNibble parses a two-word instruction's opcode2 field (e.g. "0010 dddd
// dddd dddd") into a single hex digit for its fully-fixed high nibble
// (ext_word[15:12]). Returns ok=false if any of the first 4 non-space
// characters is not '0'/'1'.
func hexNibble(opcode2 string) (string, bool) {
	clean := strings.ReplaceAll(opcode2, " ", "")
	if len(clean) < 4 {
		return "", false
	}
	v := 0
	for i := 0; i < 4; i++ {
		v <<= 1
		switch clean[i] {
		case '0':
		case '1':
			v |= 1
		default:
			return "", false
		}
	}
	return fmt.Sprintf("%x", v), true
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
