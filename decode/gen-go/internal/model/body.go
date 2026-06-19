package model

import (
	"fmt"
	"sort"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/logic"
)

// Body is the emission-ready view of decode_body.vhd. The package body
// provides function bodies for three predeclared functions in decode_pkg.vhd.
type Body struct {
	Predecode    PredecodeFunc
	IllegalSlot  string // single boolean expression text for the function body
	IllegalInstr string // boolean expression text for the simpler check
	Privileged   string // boolean expression text for the privileged() predicate
	AddrSentinel string // VHDL literal for the predecode "unknown opcode" default
	// (the all-ones address — a reserved, unused slot)
}

// PredecodeFunc represents predecode_rom_addr's case-statement body.
// Each of the 16 top-nibble values maps to a PredecodeArm. Arms with
// only one instruction in their group emit a literal addr assignment;
// arms with multiple instructions emit per-bit boolean expressions.
type PredecodeFunc struct {
	Arms [16]PredecodeArm
}

// PredecodeArm holds the body of one case arm. If LiteralAddr != "", the
// arm assigns that VHDL hex literal directly (single-instruction case).
// Otherwise BitAssigns is non-nil and each entry is one "addr(N) := <expr>;"
// line. ListComment is the multi-line comment listing the instructions
// covered by this arm.
type PredecodeArm struct {
	TopNibble   int
	ListComment []string // one comment line per instruction in the arm
	LiteralAddr string   // VHDL hex literal like `x"9e"` — set iff single-instr arm
	BitAssigns  []PredecodeBitAssign
}

// PredecodeBitAssign is one VHDL line: "addr(N) := <expr>;"
type PredecodeBitAssign struct {
	Bit  int    // 0..7
	Expr string // VHDL boolean expression
}

// BuildBody constructs the Body model from all instructions and their
// ROM addresses. instrAddrs maps instruction name → its first ROM
// address (0..255). The address arrays drive predecode_rom_addr; the
// instruction set drives the two illegal checks.
//
// instrLogic maps instruction name → its full 17-bit LogicMap (1 plane
// bit + 16 opcode bits). For predecode we use only the lower 12 opcode
// bits within each top-nibble group; for the illegal checks we use the
// full map.
//
// writesPC is the set of instruction names that write PC (branches);
// drives check_illegal_delay_slot.
// droppedPredecode maps each dropped instruction name → its opcode LogicMap;
// illegalAddr is the ROM address of the General Illegal microcode. Dropped
// opcodes are added to the predecode pointing at illegalAddr so that — even
// with the Stage-2 read-ahead, which reads ROM[predecode(opcode)] one cycle
// early — a dropped opcode executes the illegal sequence instead of landing on
// some populated kept-instruction entry (e.g. XTRACT). The illegal/privileged
// checks still see only the real instruction set (scoped copies below).
func BuildBody(instrAddrs map[string]int, instrLogic map[string]logic.LogicMap, writesPC map[string]bool, privileged map[string]bool, addrBits int, droppedPredecode map[string]logic.LogicMap, illegalAddr int) *Body {
	body := &Body{}
	preAddrs := instrAddrs
	preLogic := instrLogic
	if len(droppedPredecode) > 0 {
		preAddrs = make(map[string]int, len(instrAddrs)+len(droppedPredecode))
		for k, v := range instrAddrs {
			preAddrs[k] = v
		}
		preLogic = make(map[string]logic.LogicMap, len(instrLogic)+len(droppedPredecode))
		for k, v := range instrLogic {
			preLogic[k] = v
		}
		for nm, lm := range droppedPredecode {
			preAddrs[nm] = illegalAddr
			preLogic[nm] = lm
		}
	}
	body.Predecode = buildPredecode(preAddrs, preLogic, addrBits)
	body.IllegalSlot = buildIllegalSlot(instrLogic, writesPC)
	body.IllegalInstr = `code(15 downto 8) = x"ff"`
	body.Privileged = buildPrivileged(instrLogic, privileged)
	body.AddrSentinel = addrLit((1<<addrBits)-1, addrBits)
	return body
}

// buildPrivileged produces the boolean expression for the privileged()
// predicate: the OR of all instructions marked privileged, reduced via QMC.
// Mirrors buildIllegalSlot — strips the plane ("p") bits since the VHDL
// signature is (code : std_logic_vector(15 downto 0)) with no plane param.
// Returns "false" when no instruction is privileged.
func buildPrivileged(lm map[string]logic.LogicMap, privileged map[string]bool) string {
	var maps []logic.LogicMap
	names := make([]string, 0, len(privileged))
	for n := range privileged {
		if _, ok := lm[n]; ok {
			names = append(names, n)
		}
	}
	sort.Strings(names)
	for _, n := range names {
		stripped := logic.LogicMap{}
		for k, v := range lm[n] {
			if k.Sig != "p" {
				stripped[k] = v
			}
		}
		maps = append(maps, stripped)
	}
	reduced := logic.ReduceImplicants(maps)
	expr := orJoin(reduced, map[string]string{"i": "code"})
	if expr == "" {
		return "false"
	}
	return "(" + expr + ") = '1'"
}

// predecodeInstr is an internal type used during predecode table construction.
type predecodeInstr struct {
	name string
	addr int
	full logic.LogicMap // full 16-bit opcode LogicMap (for comments)
	lo12 logic.LogicMap // lower 12 bits LogicMap (top nibble removed; for QMC)
}

func buildPredecode(addrs map[string]int, lm map[string]logic.LogicMap, addrBits int) PredecodeFunc {
	// Group instruction names by top-nibble of opcode.
	groups := [16][]predecodeInstr{}
	for name, m := range lm {
		// Top nibble = bits 12..15. We use the LogicMap's i12..i15 values
		// (must be all set — they're from the original opcode) to compute
		// the nibble; if any of those bits is don't-care, default to 0.
		nibble := 0
		for b := 12; b < 16; b++ {
			if v, ok := m[logic.SigBit{Sig: "i", Bit: b}]; ok && v == 1 {
				nibble |= 1 << (b - 12)
			}
		}
		// Build lo12 = m restricted to i0..i11.
		lo12 := logic.LogicMap{}
		for k, v := range m {
			if k.Sig == "i" && k.Bit < 12 {
				lo12[k] = v
			}
		}
		groups[nibble] = append(groups[nibble], predecodeInstr{name, addrs[name], m, lo12})
	}

	var pf PredecodeFunc
	for nib := 0; nib < 16; nib++ {
		arm := PredecodeArm{TopNibble: nib}
		g := groups[nib]
		sort.Slice(g, func(i, j int) bool { return g[i].addr < g[j].addr })
		for _, in := range g {
			arm.ListComment = append(arm.ListComment, fmt.Sprintf(
				"%s => %s  %s",
				nibbleSpaced16Bit(in.full),
				fmt.Sprintf("%0*b", addrBits, in.addr),
				in.name))
		}
		if len(g) == 0 {
			arm.LiteralAddr = addrLit(0, addrBits)
		} else if len(g) == 1 {
			arm.LiteralAddr = addrLit(g[0].addr, addrBits)
		} else {
			arm.BitAssigns = buildAddrBitAssigns(g, addrBits)
		}
		pf.Arms[nib] = arm
	}
	return pf
}

// buildAddrBitAssigns produces eight "addr(N) := <expr>" lines. For each
// bit, pick the shorter of {minterms where bit=1, OR'd together} vs
// {minterms where bit=0, AND'd as "not (...)"}. Reduce both candidate
// sets via logic.ReduceImplicants then choose the cheaper. The "lo12"
// LogicMaps already exclude the top nibble (op.code(11 downto 0)).
func buildAddrBitAssigns(g []predecodeInstr, addrBits int) []PredecodeBitAssign {
	var out []PredecodeBitAssign
	sigs := map[string]string{"i": "code"}
	for bit := 0; bit < addrBits; bit++ {
		var onSet, offSet []logic.LogicMap
		for _, in := range g {
			if (in.addr>>bit)&1 == 1 {
				onSet = append(onSet, in.lo12)
			} else {
				offSet = append(offSet, in.lo12)
			}
		}

		// Trivial cases: all instructions agree on this bit.
		if len(onSet) == 0 {
			out = append(out, PredecodeBitAssign{Bit: bit, Expr: "'0'"})
			continue
		}
		if len(offSet) == 0 {
			out = append(out, PredecodeBitAssign{Bit: bit, Expr: "'1'"})
			continue
		}

		// Reduce both halves.
		onReduced := logic.ReduceImplicants(onSet)
		offReduced := logic.ReduceImplicants(offSet)

		// An empty-map implicant in the reduced set means "always true"
		// (covers all minterms). This happens when QMC fully collapses
		// the set. Treat as a constant bit.
		onHasEmpty := hasEmptyImplicant(onReduced)
		offHasEmpty := hasEmptyImplicant(offReduced)
		if onHasEmpty {
			out = append(out, PredecodeBitAssign{Bit: bit, Expr: "'1'"})
			continue
		}
		if offHasEmpty {
			out = append(out, PredecodeBitAssign{Bit: bit, Expr: "'0'"})
			continue
		}

		// Choose the smaller representation.
		var expr string
		if len(onReduced) <= len(offReduced) {
			expr = orJoin(onReduced, sigs)
		} else {
			inner := orJoin(offReduced, sigs)
			if inner == "" {
				expr = "'1'"
			} else {
				expr = "not (" + inner + ")"
			}
		}
		if expr == "" {
			expr = "'0'"
		}
		out = append(out, PredecodeBitAssign{Bit: bit, Expr: expr})
	}
	return out
}

// hasEmptyImplicant reports whether any implicant in the set is the
// empty map (all-don't-care = covers everything = always true).
func hasEmptyImplicant(implicants []logic.LogicMap) bool {
	for _, m := range implicants {
		if len(m) == 0 {
			return true
		}
	}
	return false
}

func orJoin(implicants []logic.LogicMap, sigs map[string]string) string {
	if len(implicants) == 0 {
		return ""
	}
	parts := make([]string, 0, len(implicants))
	for _, m := range implicants {
		expr := logic.LogicMapToBoolExpr(m, sigs)
		if expr != "" {
			parts = append(parts, expr)
		}
	}
	if len(parts) == 0 {
		return ""
	}
	return strings.Join(parts, " or ")
}

// nibbleSpaced16Bit renders the full 16 opcode bits as a nibble-spaced
// pattern like "0000 nnnn 0010 1001" (matching the Clojure golden's
// comment format in decode_body.vhd). Don't-care bits render as '-'.
func nibbleSpaced16Bit(m logic.LogicMap) string {
	raw := logic.LogicMapToStdMatch(m, "i", 16) // 16 chars, MSB-first
	return raw[0:4] + " " + raw[4:8] + " " + raw[8:12] + " " + raw[12:16]
}

func buildIllegalSlot(lm map[string]logic.LogicMap, writesPC map[string]bool) string {
	var pcMaps []logic.LogicMap
	names := make([]string, 0, len(writesPC))
	for n := range writesPC {
		if _, ok := lm[n]; ok {
			names = append(names, n)
		}
	}
	sort.Strings(names)
	for _, n := range names {
		// check_illegal_delay_slot's VHDL signature is
		//   (code : std_logic_vector(15 downto 0)) return std_logic
		// — no plane parameter. Strip the "p" bits from each map so QMC
		// reduces over opcode bits only, leaving p(0) unreferenced.
		stripped := logic.LogicMap{}
		for k, v := range lm[n] {
			if k.Sig != "p" {
				stripped[k] = v
			}
		}
		pcMaps = append(pcMaps, stripped)
	}
	reduced := logic.ReduceImplicants(pcMaps)
	expr := orJoin(reduced, map[string]string{"i": "code"})
	if expr == "" {
		return "false"
	}
	// orJoin returns std_logic; wrap with "= '1'" for the `if ... then`
	// boolean context in check_illegal_delay_slot.
	return "(" + expr + ") = '1'"
}
