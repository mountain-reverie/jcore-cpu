package model

import (
	"fmt"
	"maps"
	"math/bits"
	"sort"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/logic"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/microcode"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// DirectDecoder is the emission-ready view of decode_table_direct.vhd.
type DirectDecoder struct {
	ImpBits     []ImpBit     // alphabetical by Name
	CondSigs    []CondSig    // in declaration order
	OutputExprs []OutputExpr // alphabetical by LHS
}

// ImpBit is one named intermediate signal "imp_bit_N <= '1' when <expr> else '0';"
// extracted from a prime implicant that appears in ≥ 2 output expressions.
type ImpBit struct {
	Name string         // "imp_bit_42"
	Expr string         // VHDL boolean expression (used in "when <expr>")
	Map  logic.LogicMap // the underlying implicant
}

// CondSig is an intermediate concatenation signal "condN <= a & b & c;"
// used by multi-value enum outputs (with/select muxes).
type CondSig struct {
	Name  string
	Width int
	Bits  []string // VHDL bit expressions, MSB-first (each is a boolean expr)
}

// OutputExpr is one assignment in the direct decoder.
// For std_logic outputs with 2 values (0 and 1): a simple boolean "lhs <= '1' when (expr) else '0';".
// For 2-value enum outputs: a ternary "lhs <= VALUE when (expr) = '1' else OTHER;".
// For multi-value enum outputs: a with/select mux referencing a condN signal.
// Skipped outputs have Expr == "".
type OutputExpr struct {
	LHS   string
	Expr  string
	IsMux bool     // true iff this is a with/select multi-value mux
	Mux   *MuxArms // populated iff IsMux
}

// MuxArms describes a VHDL with/select mux for a multi-value enum output.
//
// Invariants (violating any of these silently produces wrong decoder output —
// commit aacd138 fixed one such violation):
//
//  1. Arms has exactly (nValues - 1) entries. The final enum value is
//     always the "when others" default and lives in Default, not in Arms.
//  2. Bits has exactly len(Arms) entries.
//  3. Bits is MSB-first: Bits[0] is the most significant bit of condN.
//     Bits[i] is the OR-of-primes boolean expression that, when true,
//     selects Arms[i].Value.
//  4. condN is declared as std_logic_vector(len(Arms)-1 downto 0). The
//     concatenation "Bits[0] & Bits[1] & ... & Bits[N-1]" forms its
//     assignment, naturally producing MSB-first ordering since VHDL's
//     '&' places the leftmost operand in the high bits.
//  5. Arm i's VHDL pattern places '1' at string position i (counted
//     left-to-right) and '0' elsewhere. In (downto 0) indexing this
//     means bit (len(Arms)-1-i) is set. This matches Bits[i] being
//     the i-th-most-significant bit of condN, so arm i fires exactly
//     when its corresponding Bits[i] is the only true bit.
//
// See BuildDirect (this file) for the construction logic. The unit-test
// TestBuildDirectSemanticSpotChecks asserts a representative shape.
type MuxArms struct {
	CondName string
	Arms     []MuxArm
	Default  string
	// Bits — see type doc above.
	Bits []string
}

// MuxArm is one "VALUE when pattern" arm in a with/select mux.
type MuxArm struct {
	Value string   // enum literal
	Codes []string // bit patterns (pipe-joined in VHDL)
}


// BuildDirect constructs the DirectDecoder model. The algorithm follows
// Clojure's gen-compressed-stmts:
//
//  1. For each (signal, value) pair across all slots, gather the union
//     LogicMaps of instructions that drive that pair. Each slot's logic map
//     includes the instruction opcode/plane bits AND the slot-index bits
//     (op.addr bits), mirroring Clojure's seq-bits expansion.
//  2. ReduceImplicants per (signal, value).
//  3. Count frequency of each prime implicant across ALL groups.
//  4. Implicants appearing ≥ 2 times become imp_bit_N (alphabetically
//     numbered).
//  5. Generate per-output expressions. Std_logic signals use simple
//     boolean OR. Two-value enum signals use a ternary. Multi-value
//     enum signals use a with/select mux via an intermediate condN signal.
func BuildDirect(s *spec.Spec, instrLogic map[string]logic.LogicMap,
	slotAssigns map[string][]microcode.AssignMap) *DirectDecoder {
	dd := &DirectDecoder{}

	// Step 1: build (signal, value) → []LogicMap (one per slot).
	// Each slot's logic map = instrLogicMap ∪ slot-index bits (op.addr / "s" sig).
	// Clojure seq-bits = ceil(log2(numSlots)) bits needed to distinguish slots.
	type sigVal struct {
		Sig microcode.Signal
		Val string
	}
	grouped := map[sigVal][]logic.LogicMap{}

	// Process instructions in sorted order for determinism.
	var names []string
	for name := range slotAssigns {
		names = append(names, name)
	}
	sort.Strings(names)

	for _, name := range names {
		ams := slotAssigns[name]
		instrMap := instrLogic[name]
		if instrMap == nil {
			continue // system-plane instructions not in instrLogic
		}
		numSlots := len(ams)
		// Number of bits needed to index slots: bit-length of (numSlots - 1),
		// equivalently ceil(log2(numSlots)) for numSlots >= 2, and 0 for
		// numSlots <= 1. Examples: 2 slots → 1 bit, 4 slots → 2 bits,
		// 5 slots → 3 bits. Mirrors Clojure's seq-bits:
		// (- Long/SIZE (Long/numberOfLeadingZeros (dec num-slots))).
		maxIdx := numSlots - 1
		seqBits := 0
		if maxIdx > 0 {
			seqBits = bits.Len(uint(maxIdx))
		}

		for slotIdx, am := range ams {
			// Build the slot's full logic map: instrMap + slot-index bits.
			slotMap := make(logic.LogicMap, len(instrMap)+seqBits)
			maps.Copy(slotMap, instrMap)
			// Add seq bits (op.addr bits). First add leading zeros for all
			// seqBits positions, then overwrite with actual slot index bits.
			// This mirrors Clojure's leading-zeros merge + slot binary expansion.
			// The slot index in binary (seqBits wide, MSB first).
			// We encode bit N of the slot index as SigBit{Sig:"s", Bit:N}.
			// "s" maps to op.addr in the VHDL rendering.
			for b := 0; b < seqBits; b++ {
				bitVal := (slotIdx >> b) & 1
				slotMap[logic.SigBit{Sig: "s", Bit: b}] = bitVal
			}

			// Build the effective assignment map for this slot by
			// merging in default values for every non-nillable signal
			// the slot does NOT explicitly assign. The direct decoder
			// has no process-level default block, so every signal must
			// be explicitly driven in every slot or we'd emit a
			// when/else that leaves the signal undriven (effectively
			// '1' or stale, depending on signal). This mirrors
			// Clojure's gen-compressed-stmts merge of default-controls
			// into every slot's assignments (interface.clj 219+,
			// genvhdl.clj 783-794).
			effectiveAM := make(microcode.AssignMap, len(am)+len(microcode.AllSignals))
			maps.Copy(effectiveAM, am)
			for _, s := range microcode.AllSignals {
				if _, has := effectiveAM[s]; has {
					continue
				}
				if def, ok := microcode.SignalDefault(s); ok {
					effectiveAM[s] = def
				}
			}

			// Iterate effectiveAM in a deterministic order. Go map
			// iteration order is randomized, and grouped[key] is a
			// slice whose contents are later consumed by QMC
			// reduction. Different append orders can produce
			// different (but semantically equivalent) prime
			// implicant choices and imp_bit numbering. Sort by
			// (signal name, value) so the resulting VHDL is
			// byte-identical across runs.
			amKeys := make([]microcode.Signal, 0, len(effectiveAM))
			for sig := range effectiveAM {
				amKeys = append(amKeys, sig)
			}
			sort.Slice(amKeys, func(i, j int) bool {
				if amKeys[i] != amKeys[j] {
					return string(amKeys[i]) < string(amKeys[j])
				}
				return effectiveAM[amKeys[i]] < effectiveAM[amKeys[j]]
			})
			for _, sig := range amKeys {
				val := effectiveAM[sig]
				key := sigVal{sig, val}
				grouped[key] = append(grouped[key], slotMap)
			}
		}
	}

	// Step 2: reduce per group. Sort keys for determinism.
	type reduced struct {
		key    sigVal
		primes []logic.LogicMap
	}
	var reducedList []reduced
	{
		keys := make([]sigVal, 0, len(grouped))
		for k := range grouped {
			keys = append(keys, k)
		}
		sort.Slice(keys, func(i, j int) bool {
			if keys[i].Sig != keys[j].Sig {
				return string(keys[i].Sig) < string(keys[j].Sig)
			}
			return keys[i].Val < keys[j].Val
		})
		for _, key := range keys {
			maps := grouped[key]
			r := reduced{key: key, primes: logic.ReduceImplicants(maps)}
			reducedList = append(reducedList, r)
		}
	}

	// Step 3: count implicant frequency across all groups.
	freq := map[string]int{}
	mapByKey := map[string]logic.LogicMap{}
	for _, r := range reducedList {
		for _, p := range r.primes {
			k := logic.CanonicalKey(p)
			freq[k]++
			mapByKey[k] = p
		}
	}

	// Step 4: extract imp_bit_N signals (frequency ≥ 2).
	// Sort keys alphabetically (mirrors Clojure's hash-map ordering surfaced
	// through iteration — alphabetical gives deterministic results).
	var impKeys []string
	for k, c := range freq {
		if c >= 2 {
			impKeys = append(impKeys, k)
		}
	}
	sort.Strings(impKeys)

	impByKey := map[string]string{} // canon key → imp_bit_N name
	sigs := map[string]string{"i": "op.code", "p": "p", "s": "op.addr"}
	for i, k := range impKeys {
		name := fmt.Sprintf("imp_bit_%d", i)
		impByKey[k] = name
		dd.ImpBits = append(dd.ImpBits, ImpBit{
			Name: name,
			Map:  mapByKey[k],
			Expr: logic.LogicMapToBoolExpr(mapByKey[k], sigs),
		})
	}

	// Step 5: build OutputExprs.
	// Group reducedList by signal (key.Sig) for multi-value handling.
	// Within each signal, collect all (value → primes) pairs.
	type valPrimes struct {
		val    string
		primes []logic.LogicMap
	}

	// Build per-signal map: signal → []valPrimes
	sigMap := map[microcode.Signal][]valPrimes{}
	for _, r := range reducedList {
		sig := r.key.Sig
		found := false
		for i := range sigMap[sig] {
			if sigMap[sig][i].val == r.key.Val {
				sigMap[sig][i].primes = append(sigMap[sig][i].primes, r.primes...)
				found = true
				break
			}
		}
		if !found {
			sigMap[sig] = append(sigMap[sig], valPrimes{val: r.key.Val, primes: r.primes})
		}
	}

	// Sort signals for determinism.
	var sigs2 []microcode.Signal
	for sig := range sigMap {
		sigs2 = append(sigs2, sig)
	}
	sort.Slice(sigs2, func(i, j int) bool {
		return string(sigs2[i]) < string(sigs2[j])
	})

	// condIdx tracks which condN signals have been allocated (by signal index).
	condIdx := 0

	for _, sig := range sigs2 {
		vps := sigMap[sig]
		lhs := signalLHS(sig)
		// Direct decoder special case: SigImmVal targets ex.imm_val directly
		// (no imm_enum intermediate). The "value" for each prime is the
		// immval_t enum literal (IMM_P4 etc.) which must expand to a
		// 32-bit vector expression via microcode.ImmLiteralToVHDL.
		if sig == microcode.SigImmVal {
			lhs = "ex.imm_val"
		}

		// Sort values: by total prime count (fewer primes = appears first in Clojure sort).
		sort.Slice(vps, func(i, j int) bool {
			ci := totalPrimeCount(vps[i].primes)
			cj := totalPrimeCount(vps[j].primes)
			if ci != cj {
				return ci < cj
			}
			return vps[i].val < vps[j].val
		})

		nValues := len(vps)

		// Build the OR expression for each value using imp_bit_N where available.
		orExpr := func(primes []logic.LogicMap) string {
			var parts []string
			for _, p := range primes {
				k := logic.CanonicalKey(p)
				if name, ok := impByKey[k]; ok {
					parts = append(parts, name)
				} else {
					e := logic.LogicMapToBoolExpr(p, sigs)
					if e != "" {
						parts = append(parts, e)
					}
				}
			}
			if len(parts) == 0 {
				return ""
			}
			return "(" + strings.Join(parts, " or ") + ")"
		}

		if sig.IsStdLogic() {
			// std_logic case: if only '0'/'1' values are present, emit a
			// simple OR-chain "lhs <= (or...);" — matches Clojure's
			// direct-assignment style.
			//
			// However, some std_logic signals carry multi-character VHDL
			// expressions as their "value" (e.g. wrpc_z, ma_issue can be
			// "t_bcc" / "not t_bcc" for conditional branches). When any
			// such value appears, we must NOT collapse to a binary OR —
			// that would drop the conditional and unconditionally drive
			// the signal to '1' wherever t_bcc/not t_bcc applied. Fall
			// through to the enum-style multi-value handling below.
			binaryOnly := true
			for _, vp := range vps {
				if vp.val != "0" && vp.val != "1" {
					binaryOnly = false
					break
				}
			}
			if binaryOnly {
				var oneSet []logic.LogicMap
				for _, vp := range vps {
					if vp.val == "1" {
						oneSet = vp.primes
						break
					}
				}
				expr := orExpr(oneSet)
				if expr == "" {
					continue
				}
				dd.OutputExprs = append(dd.OutputExprs, OutputExpr{
					LHS:  lhs,
					Expr: lhs + " <= " + expr + ";",
				})
				continue
			}
			// else: fall through to enum-style multi-value mux below.
		}

		// Enum signal case.
		switch nValues {
		case 1:
			val := directValue(sig, vps[0].val)
			dd.OutputExprs = append(dd.OutputExprs, OutputExpr{
				LHS:  lhs,
				Expr: lhs + " <= " + val + ";",
			})
		case 2:
			cond := orExpr(vps[0].primes)
			v1 := directValue(sig, vps[0].val)
			v2 := directValue(sig, vps[1].val)
			if cond == "" {
				dd.OutputExprs = append(dd.OutputExprs, OutputExpr{
					LHS:  lhs,
					Expr: lhs + " <= " + v1 + ";",
				})
			} else {
				dd.OutputExprs = append(dd.OutputExprs, OutputExpr{
					LHS:  lhs,
					Expr: lhs + " <= " + v1 + " when " + cond + " = '1' else " + v2 + ";",
				})
			}
		default:
			// Multi-value: emit a with/select mux using an intermediate condN signal.
			// condN is a std_logic_vector of width (nValues-1), with each bit
			// representing one value (except the last/default value).
			// Width = nValues - 1 (last value is the "others" default).
			condWidth := nValues - 1
			condName := fmt.Sprintf("cond%d", condIdx)
			condIdx++

			// Build condN bit expressions (MSB-first = first value first).
			// Each bit = OR of primes for that value.
			// We use all but the last value (last is the default).
			var condBits []string
			for i := range condWidth {
				e := orExpr(vps[i].primes)
				if e == "" {
					e = "'0'"
				}
				condBits = append(condBits, e)
			}
			dd.CondSigs = append(dd.CondSigs, CondSig{
				Name:  condName,
				Width: condWidth,
				Bits:  condBits,
			})

			// Build with/select arms. Pattern for arm i (0-indexed):
			// bit i is '1', all other bits are '0'.
			// condN(width-1 downto 0) — MSB is bit index (condWidth-1).
			// For arm i: the pattern has a '1' in position (condWidth-1-i).
			var arms []MuxArm
			for i := range condWidth {
				pat := make([]byte, condWidth)
				for j := range pat {
					pat[j] = '0'
				}
				pat[i] = '1'
				arms = append(arms, MuxArm{
					Value: directValue(sig, vps[i].val),
					Codes: []string{string(pat)},
				})
			}
			defaultVal := directValue(sig, vps[condWidth].val)

			dd.OutputExprs = append(dd.OutputExprs, OutputExpr{
				LHS:   lhs,
				IsMux: true,
				Mux: &MuxArms{
					CondName: condName,
					Arms:     arms,
					Default:  defaultVal,
					Bits:     condBits,
				},
			})
		}
	}

	// Sort OutputExprs by LHS for determinism.
	sort.Slice(dd.OutputExprs, func(i, j int) bool {
		return dd.OutputExprs[i].LHS < dd.OutputExprs[j].LHS
	})

	return dd
}

// directValue formats one (signal, value) for the direct decoder VHDL
// output. SigImmVal gets immval_t → vector expansion via
// microcode.ImmLiteralToVHDL; everything else delegates to signalRHS
// (which handles regnum tags and std_logic quoting).
func directValue(sig microcode.Signal, val string) string {
	if sig == microcode.SigImmVal {
		if v := microcode.ImmLiteralToVHDL(val); v != "" {
			return v
		}
	}
	return signalRHS(sig, val)
}

// totalPrimeCount returns the number of primes (for sorting).
func totalPrimeCount(primes []logic.LogicMap) int {
	return len(primes)
}

