package measure

import (
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// branchNames lists mnemonics classified as the "branch" template. Matched
// against the leading whitespace-delimited token of Instr.Name (uppercase,
// as stored in the spec) so operand text ("Rm", "label", "@@(disp8,TBR)")
// doesn't interfere.
var branchNames = map[string]bool{
	"BRA": true, "BSR": true, "BT": true, "BF": true,
	"BT/S": true, "BF/S": true, "BRAF": true, "BSRF": true,
	"JMP": true, "JSR": true, "RTS": true,
	"RTS/N": true, "RTV/N": true, "JSR/N": true,
}

// handValues seeds latency/issue for un-measurable (system-control) ops,
// keyed by the leading mnemonic token of Instr.Name (uppercase). Reused
// from the already-curated timing/j2.toml + j4.toml overrides per the
// Task 11 plan.
var handValues = map[string]struct {
	issue, latency int
	why            string
}{
	"RTE":      {1, 4, "hand: delayed branch restoring PC/SR from stack; not standalone-runnable"},
	"SLEEP":    {1, 3, "hand: halts the core; cannot run standalone"},
	"TRAPA":    {2, 8, "hand: software exception entry; not standalone-runnable"},
	"TAS.B":    {2, 4, "hand: read-modify-write test-and-set with bus lock semantics"},
	"LDTLB":    {2, 2, "hand: MMU TLB reload; not standalone-runnable"},
	"LDTLB.RN": {2, 2, "hand: MMU TLB reload; not standalone-runnable"},
	// STC X,Rn (control-register read) and LDC.L @Rm+,X (control-register
	// post-inc load) are curated for SR/GBR/VBR in timing/j2.toml +
	// timing/j4.toml; reuse those numbers as the general hand value for
	// every STC/LDC.L control-register form (SSR/SPC/PTEH/... included) --
	// same bus/pipeline shape, no reason to expect a different cost.
	"STC":   {1, 2, "hand: control-register read, not standalone-runnable"},
	"LDC.L": {1, 3, "hand: control-register post-increment load, not standalone-runnable"},
}

// leadToken returns the first whitespace-delimited token of a spec.Instr
// Name, e.g. "STC SR, Rn" -> "STC", "BT/S label" -> "BT/S".
func leadToken(name string) string {
	name = strings.TrimSpace(name)
	if i := strings.IndexAny(name, " \t"); i >= 0 {
		return name[:i]
	}
	return name
}

// isSystemControl reports whether in is a system/control-register op that
// cannot be run standalone in the microbenchmark harness: any op the
// decoder marks Privileged, plus LDC/STC (control-register moves), RTE,
// SLEEP, TRAPA, LDTLB, LDBANK/STBANK/RESBANK.
func isSystemControl(in spec.Instr) bool {
	if in.Privileged {
		return true
	}
	tok := leadToken(in.Name)
	switch tok {
	case "RTE", "SLEEP", "TRAPA", "LDTLB", "LDTLB.RN",
		"LDBANK", "STBANK", "RESBANK":
		return true
	case "LDC", "STC":
		return true
	}
	return false
}

// isBranch reports whether in is a control-flow op that needs the
// "branch" template (delay-slot-aware benchmark shape) rather than a
// straight-line regreg/imm/load/store chain.
func isBranch(in spec.Instr) bool {
	if branchNames[leadToken(in.Name)] {
		return true
	}
	return strings.Contains(strings.ToLower(in.Operation), "branch")
}

// isMemory reports whether in.Operation references a memory operand
// (contains "@"), and if so whether the "@"-side is the source (load,
// "@Rm -> Rn") or the destination (store, "Rn -> @Rm"). The operation
// strings in spec/*.toml use "?" as the direction arrow (a mojibake
// artifact of the original spreadsheet's unicode arrow surviving CSV
// import) — split on it and see which side carries "@".
func isMemory(in spec.Instr) (mem bool, isLoad bool) {
	op := in.Operation
	if !strings.Contains(op, "@") {
		return false, false
	}
	idx := strings.Index(op, "?")
	if idx < 0 {
		// No arrow found; can't tell direction reliably. Default to
		// load (the more common case for @-bearing ops without a
		// parsed arrow) but this should be rare/unexpected.
		return true, true
	}
	lhs, rhs := op[:idx], op[idx+1:]
	lhsMem := strings.Contains(lhs, "@")
	rhsMem := strings.Contains(rhs, "@")
	switch {
	case lhsMem && !rhsMem:
		// @Rm (source, left of arrow) -> Rn : load. Also covers
		// post-increment loads ("@Rm+ -> Rn").
		return true, true
	case rhsMem && !lhsMem:
		// Rn -> @Rm (dest, right of arrow) : store. Also covers
		// pre-decrement stores ("Rn -> @-Rm").
		return true, false
	default:
		// both sides (or neither) reference "@" -- e.g. swap/RMW ops.
		// Treat as load (read side dominates the measured latency).
		return true, true
	}
}

// isImmediate reports whether in's format encodes an immediate operand
// (format token contains "i", e.g. "i8" or "ni") with no memory operand.
func isImmediate(in spec.Instr) bool {
	return strings.Contains(in.Format, "i")
}

// Classify derives a Recipe for in from spec metadata alone, per the
// Task 11 plan's classify() rules (evaluated in priority order):
//  1. Plane == "system" -> skip (microcode-internal pseudo-op, not a real
//     DUT instruction; excluded from the measured table entirely).
//  2. system-control (Privileged, or LDC/STC/RTE/SLEEP/TRAPA/LDTLB/
//     *BANK) -> hand value (Measurable=false, Why set, Issue/Latency from
//     handValues or a 2/2 provisional placeholder).
//  3. branch mnemonic or Operation mentions "branch" -> "branch" template.
//  4. Opcode2 present (SH-2A two-word op) -> "twoword" template.
//  5. Operation references "@" -> "load" or "store" template, by which
//     side of the arrow the memory operand is on.
//  6. Format contains "i" (immediate) with no memory operand -> "imm"
//     template.
//  7. else (plain register-register op) -> "default" template.
func Classify(in spec.Instr) Recipe {
	if in.Plane == "system" {
		return Recipe{Template: "skip"}
	}

	if isSystemControl(in) {
		tok := leadToken(in.Name)
		if hv, ok := handValues[tok]; ok {
			return Recipe{
				Measurable: false,
				Issue:      hv.issue,
				Latency:    hv.latency,
				Why:        hv.why,
			}
		}
		return Recipe{
			Measurable: false,
			Issue:      2,
			Latency:    2,
			Why:        "hand: provisional placeholder, no curated value for " + tok,
		}
	}

	if isBranch(in) {
		return Recipe{Template: "branch", Measurable: true}
	}

	if in.Opcode2 != "" {
		return Recipe{Template: "twoword", Measurable: true}
	}

	if mem, isLoad := isMemory(in); mem {
		if isLoad {
			return Recipe{Template: "load", Measurable: true}
		}
		return Recipe{Template: "store", Measurable: true}
	}

	if isImmediate(in) {
		return Recipe{Template: "imm", Measurable: true}
	}

	return Recipe{Template: "default", Measurable: true}
}
