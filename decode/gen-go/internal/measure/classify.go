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

// branchHandValue is the well-established branch-redirect-penalty value
// (issue=1, latency=2), reused verbatim from decode/gen-go/timing/j2.toml's
// branch overrides. Measuring branch redirect penalty cleanly in the
// straight-line auto-chain microbenchmark harness is out of scope for this
// iteration (a taken branch jumps past its own end marker) -- see Task 11
// iter2 recipes doc.
const branchHandIssue, branchHandLatency = 1, 2

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

	// XTRACT (J2 custom instruction) -- curated in timing/j2.toml.
	"XTRACT": {1, 4, "hand: J2 custom XTRACT, curated value from timing/j2.toml"},

	// MAC.W/MAC.L @Rm+,@Rn+ -- dual-pointer post-increment
	// read-modify-write into the MAC accumulator; not faithfully
	// representable by the plain-indirect load/store templates.
	"MAC.W": {2, 2, "hand: dual-pointer post-increment RMW into MAC accumulator"},
	"MAC.L": {2, 2, "hand: dual-pointer post-increment RMW into MAC accumulator"},

	// Byte RMW to GBR: TST.B/AND.B/XOR.B/OR.B #imm,@(R0,GBR) -- curated
	// in timing/j2.toml.
	"TST.B": {2, 3, "hand: byte read-modify-write to @(R0,GBR), curated value from timing/j2.toml"},
	"AND.B": {2, 3, "hand: byte read-modify-write to @(R0,GBR), curated value from timing/j2.toml"},
	"XOR.B": {2, 3, "hand: byte read-modify-write to @(R0,GBR), curated value from timing/j2.toml"},
	"OR.B":  {2, 3, "hand: byte read-modify-write to @(R0,GBR), curated value from timing/j2.toml"},
}

// specialRegKind classifies STS/LDS special-register-move instructions
// (MACH/MACL/PR/CPI_COM/CP0_COM) into one of:
//   - "sreg": plain register form (STS <SPECIAL>, Rn / LDS Rm, <SPECIAL>),
//     measurable via the "sreg" template (issue-only; source/dest is a
//     fixed special register so no data-dependent chain is possible).
//   - "coproc": coprocessor STS/LDS CPI_COM/CP0_COM forms -- hand value.
//   - "stsl": STS.L <SPECIAL>, @-Rn (pre-decrement store) -- hand value,
//     reusing the STC-analog (issue=1, latency=2).
//   - "ldsl": LDS.L @Rm+, <SPECIAL> (post-increment load) -- hand value,
//     reusing the LDC.L-analog (issue=1, latency=3).
//   - "" if in is not an STS/LDS special-register-move instruction.
func specialRegKind(in spec.Instr) string {
	tok := leadToken(in.Name)
	coproc := strings.Contains(in.Name, "CPI_COM") || strings.Contains(in.Name, "CP0_COM")
	switch tok {
	case "STS":
		if coproc {
			return "coproc"
		}
		return "sreg"
	case "LDS":
		if coproc {
			return "coproc"
		}
		return "sreg"
	case "STS.L":
		return "stsl"
	case "LDS.L":
		return "ldsl"
	}
	return ""
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

// operandText returns in.Name with the leading mnemonic token stripped, e.g.
// "MOV.L @Rm, Rn" -> "@Rm, Rn". Empirically, in.Operation in spec/*.toml
// NEVER contains a literal "@" (the CSV import's arrow mojibake landed on
// "?", not on the memory-operand marker), so the memory operand and its
// direction must be read from Name, not Operation.
func operandText(in spec.Instr) string {
	name := strings.TrimSpace(in.Name)
	if i := strings.IndexAny(name, " \t"); i >= 0 {
		return strings.TrimSpace(name[i+1:])
	}
	return ""
}

// splitTopLevelCommas splits s on commas that are not nested inside
// parentheses, e.g. "@(R0, Rm), Rn" -> ["@(R0, Rm)", " Rn"] (2 operands,
// not 3) so displacement/indexed operand groups aren't mistaken for
// separate operands.
func splitTopLevelCommas(s string) []string {
	depth := 0
	var parts []string
	last := 0
	for i, r := range s {
		switch r {
		case '(':
			depth++
		case ')':
			depth--
		case ',':
			if depth == 0 {
				parts = append(parts, s[last:i])
				last = i + 1
			}
		}
	}
	parts = append(parts, s[last:])
	return parts
}

// isMemory reports whether in references a memory operand (its Name, once
// the mnemonic is stripped, contains "@"), and if so whether the "@"-side
// is the source (load, "@Rm, Rn") or the destination (store, "Rm, @Rn").
// MOVA computes an effective address into R0 -- it never accesses memory
// despite its "@(disp, PC)" operand syntax -- so it's excluded explicitly.
func isMemory(in spec.Instr) (mem bool, isLoad bool) {
	if leadToken(in.Name) == "MOVA" {
		return false, false
	}
	rest := operandText(in)
	if !strings.Contains(rest, "@") {
		return false, false
	}
	parts := splitTopLevelCommas(rest)
	if len(parts) < 2 {
		// Single-operand memory op (e.g. TAS.B @Rn): can't determine a
		// load/store direction reliably; treat as memory so Classify
		// routes it away from load/store's 2-operand templates instead
		// of silently defaulting to one.
		return true, true
	}
	first, last := parts[0], parts[len(parts)-1]
	firstMem := strings.Contains(first, "@")
	lastMem := strings.Contains(last, "@")
	switch {
	case firstMem && !lastMem:
		// @Rm (source, first operand) -> Rn : load. Also covers
		// post-increment loads ("@Rm+, Rn").
		return true, true
	case lastMem && !firstMem:
		// Rm, @Rn (dest, last operand) : store. Also covers
		// pre-decrement stores ("Rm, @-Rn").
		return true, false
	default:
		// both sides (or neither, or >2 operands e.g. CAS.L) reference
		// "@" -- RMW-shaped ops. Treat as load; Classify's plain-operand
		// count/shape check routes these away from the 2-operand
		// load/store templates regardless.
		return true, true
	}
}

// isImmediate reports whether in's format encodes an immediate operand
// (format token contains "i", e.g. "i8" or "ni") with no memory operand.
func isImmediate(in spec.Instr) bool {
	return strings.Contains(in.Format, "i")
}

// isR0FixedImmediate reports whether in is an immediate op whose
// destination is hard-wired to R0 (AND/OR/XOR/TST #imm,R0; CMP/EQ #imm,R0)
// rather than a general Rn -- the gas mnemonic table only accepts "r0" as
// the destination for these encodings ("and #1, r1" is rejected), so they
// need the "immr0" template instead of the general "imm" template. Excludes
// the @(R0,GBR) byte-RMW forms (those are routed to hand values earlier by
// their distinct .B mnemonic token, before this check is reached).
func isR0FixedImmediate(in spec.Instr) bool {
	if !isImmediate(in) {
		return false
	}
	parts := splitTopLevelCommas(operandText(in))
	if len(parts) == 0 {
		return false
	}
	return strings.TrimSpace(parts[len(parts)-1]) == "R0"
}

// specialRegOperand returns the gas-syntax lowercase special-register token
// (mach, macl, pr) for an STS/LDS "sreg"-template instruction, plus
// stsDirection reporting whether the special register is the source
// operand (STS: special -> Rn) as opposed to the destination (LDS: Rm ->
// special). ok is false if no special-register operand token could be
// found (defensive; specialRegKind should already have filtered to
// STS/LDS forms before this is called).
func specialRegOperand(in spec.Instr) (special string, stsDirection bool, ok bool) {
	parts := splitTopLevelCommas(operandText(in))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "Rn" && p != "Rm" && p != "" {
			return strings.ToLower(p), leadToken(in.Name) == "STS", true
		}
	}
	return "", false, false
}

// isUnary reports whether in is a plain single-register-operand op (format
// exactly "n" or "m", no memory reference) suitable for the "unary"
// template: shift/rotate/dt/movt/cmp-style ops that take one register and
// no other operand.
func isUnary(in spec.Instr) bool {
	if in.Format != "n" && in.Format != "m" {
		return false
	}
	if mem, _ := isMemory(in); mem {
		return false
	}
	return true
}

// isNullary reports whether in takes no register/immediate operand at all
// (format "0" or empty, no memory reference): CLRT, SETT, CLRMAC, DIV0U,
// NOP, ... Excludes NOP itself (routed to "skip" by the caller -- NOP is
// the calibration filler, not a DUT under measurement).
func isNullary(in spec.Instr) bool {
	if in.Format != "0" && in.Format != "" {
		return false
	}
	if mem, _ := isMemory(in); mem {
		return false
	}
	return true
}

// isPlainIndirect reports whether in expresses ONLY a plain
// register-indirect memory operand (@Rm / @Rn), in an exactly-2-operand
// form, with no displacement, R0-indexed, post-increment, pre-decrement, or
// RMW (1- or 3-operand, e.g. TAS.B @Rn / CAS.L Rm,Rn,@R0) shape -- the only
// memory shape the "load"/"store" templates can faithfully emit. Other
// addressing modes are routed by classifyMemoryMode to their own dedicated
// templates (displacement, R0-indexed, post-increment, pre-decrement); any
// mode still not representable is left unmeasured (see Classify) rather
// than mis-measure the wrong instruction shape.
func isPlainIndirect(in spec.Instr) bool {
	name := in.Name
	if strings.Contains(name, "(disp") || strings.Contains(name, "(R0") {
		return false
	}
	if strings.Contains(name, "Rm+") || strings.Contains(name, "Rn+") {
		return false
	}
	if strings.Contains(name, "-Rn") || strings.Contains(name, "-Rm") {
		return false
	}
	if len(splitTopLevelCommas(operandText(in))) != 2 {
		return false
	}
	return true
}

// storeDecRegion is the base pointer value used by the "storedec" template:
// high enough above the plain-indirect load/store region that count
// pre-decrements (any of the B/W/L strides) never run outside RAM, even
// without a mid-body reset (genStoreDec resets between brackets anyway, but
// the margin is kept generous for defense in depth).
const storeDecRegion = 0x00008000 + 0x400

// classifyMemoryMode classifies a memory-referencing instruction (isMemory
// already reported mem==true and isPlainIndirect==false, i.e. it's some
// non-plain addressing mode) into one of the dedicated iteration-4
// templates, or leaves it as a "skip"/hand entry if the mode still isn't
// faithfully representable:
//   - GBR-relative (@(disp,GBR)): dedicated base register with a different
//     scale factor per size -- not covered by these templates, skip.
//   - PC-relative (@(disp,PC)): PC as the base register moves every
//     instruction issued before it, so a fixed disp doesn't stay valid the
//     same way -- not covered, skip.
//   - Not exactly 2 top-level operands (e.g. CAS.L Rm,Rn,@R0): a genuine
//     multi-operand RMW shape the load/store family can't express, skip.
//   - @(disp,Rm) with a general Rn destination or Rm source (format "nmd")
//     -> "loaddisp"/"storedisp".
//   - @(disp,Rm)/(disp,Rn) with a fixed R0 (format "md" load-into-R0 or
//     "nd4" store-from-R0) -> "loaddispr0"/"storedispr0".
//   - @(R0,Rm)/(R0,Rn) -> "loadr0idx"/"storer0idx".
//   - @Rm+ (post-increment) -> "loadinc".
//   - Rm,@-Rn (pre-decrement) -> "storedec".
func classifyMemoryMode(in spec.Instr, isLoad bool) Recipe {
	name := in.Name
	switch {
	case strings.Contains(name, "GBR"):
		return Recipe{
			Template: "skip",
			Why:      "hand: GBR-relative displacement addressing uses a dedicated base register with distinct per-size scaling; not covered by iter4 templates for " + name,
		}
	case strings.Contains(name, ", PC)") || strings.Contains(name, "(disp, PC)"):
		return Recipe{
			Template: "skip",
			Why:      "hand: PC-relative displacement addressing (PC as base) is not faithfully representable in the auto-chain microbenchmark; not covered by iter4 templates for " + name,
		}
	case len(splitTopLevelCommas(operandText(in))) != 2:
		return Recipe{
			Template: "skip",
			Why:      "hand: multi-operand memory RMW shape not representable by the load/store template family for " + name,
		}
	case strings.Contains(name, "(disp"):
		if in.Format == "md" || in.Format == "nd4" {
			if isLoad {
				return Recipe{Template: "loaddispr0", Measurable: true, Ptr: "r10", Region: 0x00008000}
			}
			return Recipe{Template: "storedispr0", Measurable: true, Ptr: "r10", Region: 0x00008000}
		}
		if isLoad {
			return Recipe{Template: "loaddisp", Measurable: true, Ptr: "r10", Region: 0x00008000}
		}
		return Recipe{Template: "storedisp", Measurable: true, Ptr: "r10", Region: 0x00008000}
	case strings.Contains(name, "(R0"):
		if isLoad {
			return Recipe{Template: "loadr0idx", Measurable: true, Ptr: "r10", Region: 0x00008000}
		}
		return Recipe{Template: "storer0idx", Measurable: true, Ptr: "r10", Region: 0x00008000}
	case strings.Contains(name, "Rm+") || strings.Contains(name, "Rn+"):
		return Recipe{Template: "loadinc", Measurable: true, Ptr: "r10", Region: 0x00008000}
	case strings.Contains(name, "-Rn") || strings.Contains(name, "-Rm"):
		return Recipe{Template: "storedec", Measurable: true, Ptr: "r10", Region: storeDecRegion}
	default:
		return Recipe{
			Template: "skip",
			Why:      "hand: non-plain memory addressing not faithfully representable by any iter4 template for " + name,
		}
	}
}

// isFPUOrCoprocessor reports whether in is an FPU or coprocessor op that
// sh2-elf-as cannot assemble in this integer-variant harness: either its
// normalized opcode pattern starts with "1111" (the SH-2/SH-4 FPU/coproc
// opcode plane) or its mnemonic starts with "F" (FADD, FMOV, FMUL, ...).
func isFPUOrCoprocessor(in spec.Instr) bool {
	op := strings.ReplaceAll(in.Opcode, " ", "")
	if strings.HasPrefix(op, "1111") {
		return true
	}
	return strings.HasPrefix(leadToken(in.Name), "F")
}

// Classify derives a Recipe for in from spec metadata alone, per the
// Task 11 plan's classify() rules (evaluated in priority order):
//  1. Plane == "system" -> skip (microcode-internal pseudo-op, not a real
//     DUT instruction; excluded from the measured table entirely).
//  2. FPU/coprocessor op (normalized opcode starts with "1111", or mnemonic
//     starts with "F") -> skip (sh2-elf-as can't assemble these, and
//     they aren't part of the integer variant).
//  3. STS/LDS special-register move (MACH/MACL/PR/CPI_COM/CP0_COM) ->
//     "sreg" template (plain register form) or a hand value (coprocessor
//     form, or .L pre-dec/post-inc memory form).
//  4. leading mnemonic token has a curated handValues entry (TAS.B,
//     XTRACT, MAC.W/MAC.L, byte-RMW-to-GBR, STC/LDC.L/RTE/SLEEP/TRAPA/
//     LDTLB) -> hand value (Measurable=false, Why set).
//  5. system-control (Privileged, or LDC/STC/RTE/SLEEP/TRAPA/LDTLB/
//     *BANK) with no curated entry -> hand value with a 2/2 provisional
//     placeholder.
//  6. branch mnemonic or Operation mentions "branch" -> "branch" template.
//  7. Opcode2 present (SH-2A two-word op) -> "twoword" template.
//  8. Operation references "@" -> "load" or "store" template for the plain
//     register-indirect (@Rm/@Rn) shape, by which side of the arrow the
//     memory operand is on; other addressing modes (displacement,
//     R0-indexed, post-increment, pre-decrement) route through
//     classifyMemoryMode to their own dedicated templates, or a hand/skip
//     entry if genuinely un-representable (GBR-relative, PC-relative,
//     multi-operand RMW).
//  9. Format contains "i" (immediate) with no memory operand -> "imm"
//     template, or "immr0" if the destination is hard-wired to R0
//     (AND/OR/XOR/TST #imm,R0; CMP/EQ #imm,R0).
//  10. Format is exactly "n" or "m" with no memory operand -> "unary"
//     template (single-register ops: shll, dt, movt, cmp/pl, ...).
//  11. else (plain register-register op) -> "default" template.
func Classify(in spec.Instr) Recipe {
	if in.Plane == "system" {
		return Recipe{Template: "skip"}
	}

	if isFPUOrCoprocessor(in) {
		return Recipe{Template: "skip"}
	}

	// SH-2A single-instruction DIVS/DIVU R0,Rn (divisor hard-wired to R0) use
	// the dedicated divfixed template. leadToken is exactly "DIVS"/"DIVU" and
	// never matches the base step-division ops DIV0S/DIV0U/DIV1.
	switch leadToken(in.Name) {
	case "DIVS", "DIVU":
		return Recipe{Template: "divfixed", Measurable: true}
	}

	switch specialRegKind(in) {
	case "sreg":
		return Recipe{Template: "sreg", Measurable: true}
	case "coproc":
		return Recipe{
			Measurable: false,
			Issue:      1,
			Latency:    2,
			Why:        "hand: coprocessor STS/LDS CPI_COM/CP0_COM, not standalone-runnable",
		}
	case "stsl":
		return Recipe{
			Measurable: false,
			Issue:      1,
			Latency:    2,
			Why:        "hand: STS.L special-reg pre-decrement store, reuses STC-analog value",
		}
	case "ldsl":
		return Recipe{
			Measurable: false,
			Issue:      1,
			Latency:    3,
			Why:        "hand: LDS.L special-reg post-increment load, reuses LDC.L-analog value",
		}
	}

	// Direct hand-value lookup by leading mnemonic token, independent of
	// isSystemControl (privileged-register moves) below: covers
	// non-privileged ops with well-established hand values (TAS.B,
	// XTRACT, MAC.W/MAC.L, byte-RMW-to-GBR forms) that would otherwise
	// mis-measure through the generic memory/immediate templates.
	if hv, ok := handValues[leadToken(in.Name)]; ok {
		return Recipe{
			Measurable: false,
			Issue:      hv.issue,
			Latency:    hv.latency,
			Why:        hv.why,
		}
	}

	if isSystemControl(in) {
		return Recipe{
			Measurable: false,
			Issue:      2,
			Latency:    2,
			Why:        "hand: provisional placeholder, no curated value for " + leadToken(in.Name),
		}
	}

	if isBranch(in) {
		return Recipe{
			Measurable: false,
			Issue:      branchHandIssue,
			Latency:    branchHandLatency,
			Why:        "branch redirect penalty; microbenchmark control-flow not isolatable",
		}
	}

	if in.Opcode2 != "" {
		return Recipe{Template: "twoword", Measurable: true}
	}

	if mem, isLoad := isMemory(in); mem {
		if !isPlainIndirect(in) {
			return classifyMemoryMode(in, isLoad)
		}
		if isLoad {
			return Recipe{Template: "load", Measurable: true, Ptr: "r10", Region: 0x00008000}
		}
		return Recipe{Template: "store", Measurable: true, Ptr: "r10", Region: 0x00008000}
	}

	if isImmediate(in) {
		if isR0FixedImmediate(in) {
			return Recipe{Template: "immr0", Measurable: true}
		}
		return Recipe{Template: "imm", Measurable: true}
	}

	// NOP is the calibration filler used inside every bracket, not a DUT
	// under measurement -- route it to skip rather than nullary.
	if leadToken(in.Name) == "NOP" {
		return Recipe{Template: "skip"}
	}

	if isNullary(in) {
		return Recipe{Template: "nullary", Measurable: true}
	}

	if isUnary(in) {
		return Recipe{Template: "unary", Measurable: true}
	}

	return Recipe{Template: "default", Measurable: true}
}
