package model

// TestDecoderDifferential is the highest-leverage semantic equivalence test
// for the Go decoder generator.  For every (instruction, slot) pair in the
// production spec it checks that:
//
//	evalDirectDecoder(dd, instrOpcode, instrPlane, slotIndex)
//	    ≡ effectiveAssignMap(AssignSlot(instr, slot))
//
// "Effective" means the raw AssignMap is augmented with per-signal defaults
// exactly as BuildDirect does, so the direct decoder (which always drives
// every signal) and the expected map describe the same state.
//
// This catches QMC reducer bugs (wrong prime implicants, missing defaults,
// bit-pattern reversals) that survive byte-identity of the simple decoder
// but would manifest as wrong hardware behavior for specific instructions.
//
// Signals excluded from comparison:
//   - SigImmVal ("imm_val"): the direct decoder emits ex.imm_val using a
//     32-bit vector expansion (ImmLiteralToVHDL) while AssignMap stores
//     the raw literal ("IMM_P4" etc.).  The two representations are
//     semantically identical but textually different; they are covered by
//     the byte-identity test of the simple decoder instead.
//   - Signals with "t_bcc" or "not t_bcc" values: these are VHDL runtime
//     expressions (the T-bit conditional) that are opaque to a static
//     evaluator.  The test verifies they appear on the same signal in both
//     decoders and records them as "runtime" matches.
//
// Coverage gap — nillable signals:
//
// When rawExp == "" for a nillable signal (i.e., the current slot's AssignMap
// does not set that signal), the comparison is skipped entirely for that signal.
// This means: if the QMC reducer drives a nillable signal to an incorrect value
// where it should be don't-care for this slot, this test will NOT catch it.
//
// What covers that gap instead:
//   (a) Byte-identity of the simple decoder against the Clojure golden output
//       in testdata/golden/clj/ — any wrong constant value in an if-branch would
//       produce a textual difference in the generated file.
//   (b) The simulator LED check in regression.sh Step 3 — the testrom exercises
//       every instruction category; a wrong nillable-signal value that affects
//       CPU behavior will manifest as a wrong LED write value or sequence.
//   (c) The synthesis check in Step 7 (yosys + ghdl-yosys-plugin) — a nillable
//       signal that is spuriously driven to a non-zero constant alongside another
//       instruction's assignment would appear as a multi-driver net and fail
//       `check -assert`. However, this only catches conflicts; a wrong but
//       non-conflicting don't-care-value assignment is NOT caught by synthesis.

import (
	"fmt"
	"maps"
	"regexp"
	"sort"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/logic"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/microcode"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// referenceDefaults pins the expected default value for every signal that has
// a non-nillable, non-zero default.  Values are transcribed directly from the
// Clojure reference implementation's enum-default-value table in interface.clj
// (lines 219-232) and the mac_busy_t first-literal (interface.clj line 189).
//
// This table is STATIC — it does NOT call microcode.SignalDefault.
// TestSignalDefaultMatchesReference uses it to break the circular dependency
// that would otherwise allow a wrong default to silently propagate into both
// sides of the differential comparison.
//
// Signals that default to std_logic "0" are not listed here; they are covered
// by signalsStdLogicDefault.  Signals with no default belong in signalsNillable.
var referenceDefaults = map[microcode.Signal]string{
	// Bus selectors — xbus_sel_t / ybus_sel_t first literal is SEL_IMM.
	// (interface.clj: (apply vector :xbus-sel "xbus_sel_t" (map sel [:imm ...])))
	microcode.SigXbusSel: "SEL_IMM",
	microcode.SigYbusSel: "SEL_IMM",

	// ALU — aluinx_sel_t first literal SEL_XBUS, aluiny_sel_t first SEL_YBUS.
	// (interface.clj: (apply vector :aluinx-sel "aluinx_sel_t" (map sel [:xbus ...])))
	microcode.SigAluinxSel: "SEL_XBUS",
	microcode.SigAluinySel: "SEL_YBUS",

	// alumanip_t first literal SWAP_BYTE.
	// (interface.clj: [:alumanip "alumanip_t" [[:swap :b] "SWAP_BYTE"] ...])
	microcode.SigAluManip: "SWAP_BYTE",

	// sr_sel_t first literal SEL_PREV.
	// (interface.clj: (apply vector :sr-sel "sr_sel_t" (map sel [:prev ...])))
	microcode.SigSrSel: "SEL_PREV",

	// t_sel_t first literal SEL_CLEAR.
	// (interface.clj: (apply vector :t-sel "t_sel_t" (map sel [:clear ...])))
	microcode.SigTSel: "SEL_CLEAR",

	// mult_state_t (mac-op) first literal NOP — shared by ex_mulcom2 / wb_mulcom2.
	// (interface.clj: [:mac-op "mult_state_t" "NOP" ...])
	microcode.SigExMulcom2: "NOP",
	microcode.SigWbMulcom2: "NOP",

	// macin1_sel_t first literal SEL_XBUS — shared by ex_macsel1 / wb_macsel1.
	// (interface.clj: (apply vector :macsel1 "macin1_sel_t" (map sel [:xbus ...])))
	microcode.SigExMacsel1: "SEL_XBUS",
	microcode.SigWbMacsel1: "SEL_XBUS",

	// macin2_sel_t first literal SEL_YBUS — shared by ex_macsel2 / wb_macsel2.
	// (interface.clj: (apply vector :macsel2 "macin2_sel_t" (map sel [:ybus ...])))
	microcode.SigExMacsel2: "SEL_YBUS",
	microcode.SigWbMacsel2: "SEL_YBUS",

	// mac_busy_t first literal NOT_BUSY.
	// (interface.clj: [:mac-busy "mac_busy_t" [:nop "NOT_BUSY"] ...])
	microcode.SigMacBusy: "NOT_BUSY",

	// coproc_cmd_t first literal NOP.
	// (interface.clj: [:coproc-cmd "coproc_cmd_t" "NOP" ...])
	microcode.SigCopCmd: "NOP",

	// cpu_data_mux_t first literal DBUS.
	// (interface.clj: [:cpu-data-mux "cpu_data_mux_t" "DBUS" ...])
	microcode.SigCpuDataMux: "DBUS",

	// mmu_reg_sel_t first literal SEL_PTEH (M1 MMU registers).
	microcode.SigMmuRegSel:   "SEL_PTEH",
	microcode.SigMmuRegSelWr: "SEL_PTEH",
}

// signalsNillable is the set of signals that have no default and must NOT be
// force-driven when absent from a slot's AssignMap.  Transcribed from
// interface.clj lines 405-416 (:nillable-outputs set).
var signalsNillable = map[microcode.Signal]bool{
	microcode.SigShiftFunc:   true, // :shiftfunc
	microcode.SigImmVal:      true, // :imm-val
	microcode.SigMaWr:        true, // :ma-wr
	microcode.SigArithFunc:   true, // :arith-func
	microcode.SigArithSrFn:   true, // :arith-sr-func
	microcode.SigLogicFunc:   true, // :logic-func
	microcode.SigLogicSrFn:   true, // :logic-sr-func
	microcode.SigZbusSel:     true, // :zbus-sel
	microcode.SigMemAddrSel:  true, // :mem-addr-sel
	microcode.SigMemSize:     true, // :mem-size
	microcode.SigMemWdataSel: true, // :mem-wdata-sel
	microcode.SigRegnumW:     true, // :regnum-w
	microcode.SigRegnumX:     true, // :regnum-x
	microcode.SigRegnumY:     true, // :regnum-y
	microcode.SigRegnumZ:     true, // :regnum-z
}

// TestSignalDefaultMatchesReference verifies that microcode.SignalDefault
// agrees with the static reference tables above for every signal in AllSignals.
//
// This is the circuit-breaker that prevents a wrong SignalDefault value from
// silently propagating into both sides of TestDecoderDifferential (which calls
// SignalDefault when building its expected map, mirroring BuildDirect).  A bug
// in SignalDefault would be invisible to the differential test but is caught
// here immediately, with the name of the signal and the expected vs got value.
func TestSignalDefaultMatchesReference(t *testing.T) {
	for _, s := range microcode.AllSignals {
		wantNillable := signalsNillable[s]
		wantVal, wantDefault := referenceDefaults[s]
		wantStdLogic := s.IsStdLogic() && !wantNillable

		// Exhaustiveness: every signal must appear in exactly one of the three
		// categories (nillable, non-zero enum default, std_logic "0" default).
		// SigImmVal is nillable AND flagged by IsStdLogic — that would be a
		// table error, so check for double-classification first.
		if wantNillable && wantDefault {
			t.Errorf("signal %q is in BOTH referenceDefaults and signalsNillable — fix the tables", s)
			continue
		}
		if !wantNillable && !wantDefault && !wantStdLogic {
			t.Errorf("signal %q is in NEITHER reference table and is not std_logic — add it to referenceDefaults or signalsNillable", s)
			continue
		}

		got, ok := microcode.SignalDefault(s)

		if wantNillable {
			if ok {
				t.Errorf("signal %q: want nillable (no default), but SignalDefault returned (%q, true)", s, got)
			}
			continue
		}

		if wantDefault {
			if !ok {
				t.Errorf("signal %q: SignalDefault = (%q, false), want (%q, true)", s, got, wantVal)
			} else if got != wantVal {
				t.Errorf("signal %q: SignalDefault = %q, want %q", s, got, wantVal)
			}
			continue
		}

		// std_logic: default must be "0".
		if !ok {
			t.Errorf("signal %q (std_logic): SignalDefault = (%q, false), want (\"0\", true)", s, got)
		} else if got != "0" {
			t.Errorf("signal %q (std_logic): SignalDefault = %q, want \"0\"", s, got)
		}
	}
}

// TestDecoderDifferential enumerates every (instruction, slot) pair and
// checks that the direct decoder produces the same control-signal values as
// the effective AssignMap derived from AssignSlot.
func TestDecoderDifferential(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}

	// Build LHS string → Signal reverse map.  We need this to map the
	// OutputExpr.LHS back to the Signal key used in AssignMap.
	// SigImmVal is special-cased because BuildDirect uses "ex.imm_val"
	// as the LHS whereas SignalVHDLPath maps SigImmVal to "imm_enum".
	lhsToSignal := make(map[string]microcode.Signal, len(microcode.SignalVHDLPath)+1)
	for sig, lhs := range microcode.SignalVHDLPath {
		lhsToSignal[lhs] = sig
	}
	lhsToSignal["ex.imm_val"] = microcode.SigImmVal

	// Build an evaluator for the DirectDecoder.
	eval := buildDirectEvaluator(d.Direct)

	// Track format inheritance exactly as Build does (csvInstrOrder walk).
	instrByName := make(map[string]*spec.Instr, len(s.Instrs))
	for i := range s.Instrs {
		instrByName[s.Instrs[i].Name] = &s.Instrs[i]
	}
	resolvedFormat := make(map[string]string, len(s.Instrs))
	prevFormat := ""
	for _, name := range csvInstrOrder {
		si := instrByName[name]
		if si == nil {
			continue
		}
		if si.Format != "" {
			resolvedFormat[name] = si.Format
			prevFormat = si.Format
		} else {
			resolvedFormat[name] = prevFormat
		}
	}

	totalCases := 0
	runtimeMatches := 0 // t_bcc / not t_bcc — opaque runtime values

	for _, si := range s.Instrs {
		// Determine plane string used by OpToLogicMap.
		plane := "0"
		if si.Plane == "system" {
			plane = "1"
		}

		// Representative opcode: use the fixed bits of the opcode pattern.
		// Don't-care bits ('n','m','d','i','-') are left as 0, which is a
		// valid concrete opcode for QMC evaluation.
		instrMap := logic.OpToLogicMap(plane, si.Opcode)
		var opcode uint16
		for sb, v := range instrMap {
			if sb.Sig == "i" && v == 1 {
				opcode |= 1 << sb.Bit
			}
		}
		var planeBit uint8
		if plane == "1" {
			planeBit = 1
		}

		// Keep only non-empty slots (same filter as Build uses).
		var keptSlots []spec.Slot
		for _, slot := range si.Slots {
			if len(slot) > 0 {
				keptSlots = append(keptSlots, slot)
			}
		}
		if len(keptSlots) == 0 {
			continue
		}

		// Apply the Clojure format-inheritance rule for register placement.
		instrForAssign := si
		if rf, ok := resolvedFormat[si.Name]; ok {
			instrForAssign.Format = rf
		}

		n := len(keptSlots)
		for slotIdx, slot := range keptSlots {
			totalCases++
			testName := fmt.Sprintf("%s/slot%d", si.Name, slotIdx)
			t.Run(testName, func(t *testing.T) {
				// Build expected AssignMap from AssignSlot.
				am, err := microcode.AssignSlot(instrForAssign, slot)
				if err != nil {
					t.Fatalf("AssignSlot: %v", err)
				}
				// Apply the last-slot default rule (same as Build).
				if slotIdx == n-1 {
					_, hasIfIssue := am[microcode.SigIfIssue]
					_, hasDispatch := am[microcode.SigDispatch]
					if !hasIfIssue && !hasDispatch {
						am[microcode.SigIfIssue] = "1"
						am[microcode.SigDispatch] = "1"
					}
				}
				// Merge defaults, exactly as BuildDirect does for its
				// effectiveAM, so the direct decoder's "always drive
				// every signal" invariant is reflected in the expected.
				expected := make(microcode.AssignMap, len(am)+len(microcode.AllSignals))
				maps.Copy(expected, am)
				for _, sig := range microcode.AllSignals {
					if _, has := expected[sig]; has {
						continue
					}
					if def, ok := microcode.SignalDefault(sig); ok {
						expected[sig] = def
					}
				}

				// Evaluate the direct decoder for this (opcode, plane, slot).
				// evaluate returns an LHS-string → value map; convert to Signal-keyed
				// so it aligns with expected (Signal → value).
				gotLHS, evalErr := eval.evaluate(opcode, planeBit, uint8(slotIdx))
				if evalErr != nil {
					t.Fatalf("evalDirectDecoder: %v", evalErr)
				}
				got := make(microcode.AssignMap, len(gotLHS))
				for lhs, val := range gotLHS {
					if sig, ok := lhsToSignal[lhs]; ok {
						got[sig] = val
					}
					// LHS values not in lhsToSignal (e.g. condN signals,
					// the split mac_busy→ex.mac_busy/wb.mac_busy) are
					// intermediates driven by templates, not by OutputExprs.
				}

				// Compare per signal.  Build a sorted union of signals from both maps.
				allSigs := make(map[microcode.Signal]struct{}, len(expected)+len(got))
				for sig := range expected {
					allSigs[sig] = struct{}{}
				}
				for sig := range got {
					allSigs[sig] = struct{}{}
				}
				sortedSigs := make([]microcode.Signal, 0, len(allSigs))
				for sig := range allSigs {
					sortedSigs = append(sortedSigs, sig)
				}
				sort.Slice(sortedSigs, func(i, j int) bool {
					return string(sortedSigs[i]) < string(sortedSigs[j])
				})

				for _, sig := range sortedSigs {
					if sig == microcode.SigImmVal {
						// Excluded: different textual representations (see file doc).
						continue
					}
					rawExp := expected[sig]
					// Nillable signals have no default and may be absent in
					// expected when a slot doesn't set them.  In that case
					// the direct decoder may still drive some value (from
					// another instruction's QMC group that shares opcode bits),
					// but since this slot legitimately doesn't use the signal,
					// we skip the check.
					if rawExp == "" {
						continue
					}

					// t_bcc / not t_bcc are runtime values.  Both sides should
					// agree they are runtime (same string).
					if isRuntime(rawExp) {
						rawGot := got[sig]
						if rawExp != rawGot {
							t.Errorf("signal %s: expected runtime=%q, direct=%q", sig, rawExp, rawGot)
						} else {
							runtimeMatches++
						}
						continue
					}

					// Normalise both sides to a canonical string for comparison.
					// signalRHS converts raw AssignMap values (e.g. "RA", "1",
					// "SEL_ARITH") to the VHDL text that appears in the generated
					// file; stripStdLogicQuotes removes the surrounding single-quote
					// pairs that signalRHS adds for std_logic signals (e.g. "'1'" →
					// "1") so the comparison is stable regardless of which code path
					// in the evaluator produced the value.
					//
					// directValue (used internally by BuildDirect) equals signalRHS
					// for all signals except SigImmVal (already excluded above).
					expFormatted := stripStdLogicQuotes(signalRHS(sig, rawExp))
					gotFormatted, gotPresent := got[sig]
					if !gotPresent {
						// Direct decoder emitted nothing for this LHS.  For signals
						// that should be driven, this is a bug.
						t.Errorf("signal %s: expected %q, direct decoder produced no value", sig, expFormatted)
						continue
					}
					gotNorm := stripStdLogicQuotes(gotFormatted)
					if expFormatted != gotNorm {
						t.Errorf("signal %s: expected %q (raw=%q), direct decoder=%q", sig, expFormatted, rawExp, gotFormatted)
					}
				}
			})
		}
	}

	t.Logf("total (instruction, slot) cases: %d", totalCases)
	t.Logf("runtime (t_bcc) signal matches: %d", runtimeMatches)
}

// isRuntime reports whether a signal value is a VHDL runtime expression
// ("t_bcc" or "not t_bcc") that cannot be evaluated statically.
func isRuntime(v string) bool {
	return v == "t_bcc" || v == "not t_bcc"
}

// directEvaluator evaluates a DirectDecoder for a concrete (opcode, plane,
// slotAddr) tuple and returns the reconstructed signal→value map.
type directEvaluator struct {
	dd *DirectDecoder
	// impBitExprByName maps "imp_bit_N" → its ImpBit.Expr (string) so
	// substituteImpBits can locate the underlying expression for expansion.
	impByName map[string]*ImpBit
	// lhsToOE maps OutputExpr.LHS → &OutputExpr for O(1) lookup.
	lhsToOE map[string]*OutputExpr
}

func buildDirectEvaluator(dd *DirectDecoder) *directEvaluator {
	ev := &directEvaluator{
		dd:        dd,
		impByName: make(map[string]*ImpBit, len(dd.ImpBits)),
		lhsToOE:   make(map[string]*OutputExpr, len(dd.OutputExprs)),
	}
	for i := range dd.ImpBits {
		ev.impByName[dd.ImpBits[i].Name] = &dd.ImpBits[i]
	}
	for i := range dd.OutputExprs {
		ev.lhsToOE[dd.OutputExprs[i].LHS] = &dd.OutputExprs[i]
	}
	return ev
}

// evaluate evaluates all OutputExprs in dd for the given (opcode, plane,
// slotAddr) and returns the signal→value map in the same raw-value encoding
// as AssignMap (before VHDL formatting).
//
// The evaluation proceeds in two passes:
//
//  1. Pre-evaluate every ImpBit's LogicMap against (opcode, plane, slotAddr)
//     directly — this avoids any string parsing for the imp_bit values.
//
//  2. For each OutputExpr, substitute imp_bit references with '1'/'0'
//     literals, then call EvalBoolExpr on the resulting expression string
//     to determine which value to select.
func (ev *directEvaluator) evaluate(opcode uint16, plane uint8, slotAddr uint8) (map[string]string, error) {
	// Pass 1: evaluate each ImpBit's LogicMap.
	// A LogicMap is a conjunction: all specified bits must match.
	impTrue := make(map[string]bool, len(ev.dd.ImpBits))
	for _, ib := range ev.dd.ImpBits {
		impTrue[ib.Name] = evalLogicMap(ib.Map, opcode, plane, slotAddr)
	}

	// buildResolver returns a SigValue resolver for EvalBoolExpr after
	// op.code/op.addr have been renamed to opcode/opaddr by preprocessExpr.
	resolver := func(sig string, bit int) int {
		switch sig {
		case "opcode":
			return int((opcode >> bit) & 1)
		case "p":
			return int((plane >> bit) & 1)
		case "opaddr":
			return int((slotAddr >> bit) & 1)
		default:
			return 0
		}
	}

	// evalExprStr evaluates a VHDL boolean sub-expression string that may
	// reference op.code(N), op.addr(N), p(N), and bare imp_bit_N signals.
	// Returns (bool, error).
	evalExprStr := func(expr string) (bool, error) {
		preprocessed := preprocessExpr(expr, impTrue)
		return logic.EvalBoolExpr(preprocessed, resolver)
	}

	// Pass 2: evaluate each OutputExpr.
	out := make(map[string]string, len(ev.dd.OutputExprs))
	for i := range ev.dd.OutputExprs {
		oe := &ev.dd.OutputExprs[i]
		lhs := oe.LHS

		if oe.IsMux && oe.Mux != nil {
			// Multi-value mux: evaluate Mux.Bits[i] in order; the first
			// true bit selects Arms[i].Value.  If none is true, use Default.
			selected := oe.Mux.Default
			for j, bitExpr := range oe.Mux.Bits {
				ok, err := evalExprStr(bitExpr)
				if err != nil {
					return nil, fmt.Errorf("mux %s bit[%d] %q: %w", lhs, j, bitExpr, err)
				}
				if ok {
					selected = oe.Mux.Arms[j].Value
					break
				}
			}
			out[lhs] = selected
			continue
		}

		// Non-mux: parse the Expr string to extract kind and value.
		// Known formats (from BuildDirect):
		//   single-value:   "lhs <= VAL;"
		//   std_logic OR:   "lhs <= (bool_expr);"
		//   2-value enum:   "lhs <= V1 when COND = '1' else V2;"
		expr := oe.Expr
		if expr == "" {
			continue // skipped output
		}
		rhs, err := extractRHS(expr)
		if err != nil {
			return nil, fmt.Errorf("OutputExpr %q: %w", lhs, err)
		}

		if v1, rest, hasWhen := strings.Cut(rhs, " when "); hasWhen {
			// 2-value enum: "V1 when COND = '1' else V2"
			elseIdx := strings.LastIndex(rest, " else ")
			if elseIdx < 0 {
				return nil, fmt.Errorf("OutputExpr %q: malformed 2-value: missing 'else' in %q", lhs, rhs)
			}
			condStr := rest[:elseIdx]
			v2 := rest[elseIdx+len(" else "):]
			// condStr has the form "COND = '1'" — strip the trailing " = '1'".
			condStr = strings.TrimSuffix(condStr, " = '1'")
			ok, err := evalExprStr(condStr)
			if err != nil {
				return nil, fmt.Errorf("OutputExpr %q cond %q: %w", lhs, condStr, err)
			}
			if ok {
				out[lhs] = v1
			} else {
				out[lhs] = v2
			}
			continue
		}

		// Either std_logic OR-chain "(bool_expr)" or bare single value "VAL".
		if strings.HasPrefix(rhs, "(") {
			// std_logic boolean: "(bool_expr)" — true → "1", false → absent.
			ok, err := evalExprStr(rhs)
			if err != nil {
				return nil, fmt.Errorf("OutputExpr %q rhs %q: %w", lhs, rhs, err)
			}
			if ok {
				out[lhs] = "1"
			}
			// When false, the signal takes the signal's default ('0' for
			// std_logic).  We omit it here; the caller merges defaults
			// from the expected side, so an absent entry on the direct
			// side is compared against '0' from the expected map.
			// Actually: the direct decoder drives every signal to 0 when
			// the OR is false (the VHDL process has no default for
			// std_logic — the statement itself drives 0 via the else).
			// To keep the comparison symmetric, emit the explicit "0".
			if !ok {
				out[lhs] = "0"
			}
			continue
		}

		// Bare single value (enum or std_logic constant).
		out[lhs] = rhs
	}

	return out, nil
}

// evalLogicMap evaluates a LogicMap (conjunction of bit constraints) against
// concrete (opcode, plane, slotAddr) values.  All specified bits must match;
// absent bits are don't-cares.
func evalLogicMap(m logic.LogicMap, opcode uint16, plane uint8, slotAddr uint8) bool {
	for sb, want := range m {
		var got int
		switch sb.Sig {
		case "i":
			got = int((opcode >> sb.Bit) & 1)
		case "p":
			got = int((plane >> sb.Bit) & 1)
		case "s":
			got = int((slotAddr >> sb.Bit) & 1)
		default:
			// Unknown sig — treat as don't-care (shouldn't happen in production).
			continue
		}
		if got != want {
			return false
		}
	}
	return true
}

// impBitPattern is a regexp that matches bare "imp_bit_NNN" names in
// expression strings (whole-word, not inside other identifiers).
var impBitPattern = regexp.MustCompile(`\bimp_bit_\d+\b`)

// preprocessExpr prepares an expression string for EvalBoolExpr:
//  1. Replaces "op.code(" → "opcode(" and "op.addr(" → "opaddr(" so
//     EvalBoolExpr's identifier parser (which does not handle dots) can
//     parse them.
//  2. Substitutes each bare "imp_bit_N" reference with its pre-evaluated
//     VHDL literal ('1' or '0').  After substitution no imp_bit names
//     remain, so the standard resolver only needs to handle opcode/opaddr/p.
func preprocessExpr(expr string, impTrue map[string]bool) string {
	// Step 1: rename dotted signal names.
	expr = strings.ReplaceAll(expr, "op.code(", "opcode(")
	expr = strings.ReplaceAll(expr, "op.addr(", "opaddr(")
	// Step 2: substitute imp_bit_N references with '1'/'0'.
	expr = impBitPattern.ReplaceAllStringFunc(expr, func(name string) string {
		if impTrue[name] {
			return "'1'"
		}
		return "'0'"
	})
	return expr
}

// extractRHS extracts the right-hand side value string from a VHDL
// assignment statement of the form "lhs <= RHS;".
// Returns an error if the expected delimiters are not found.
func extractRHS(stmt string) (string, error) {
	_, rhs, ok := strings.Cut(stmt, " <= ")
	if !ok {
		return "", fmt.Errorf("missing ' <= ' in %q", stmt)
	}
	rhs = strings.TrimSuffix(rhs, ";")
	return rhs, nil
}

// stripStdLogicQuotes removes the surrounding single-quote pair that
// signalRHS adds for std_logic bit values ("'0'" → "0", "'1'" → "1").
// Other strings (enum literals, VHDL expressions) pass through unchanged.
// This makes the comparison robust to whether the value went through
// signalRHS/directValue (quoted) or through the direct evaluator's
// std_logic OR-chain path (unquoted).
func stripStdLogicQuotes(v string) string {
	if len(v) == 3 && v[0] == '\'' && v[2] == '\'' {
		return string(v[1:2])
	}
	return v
}
