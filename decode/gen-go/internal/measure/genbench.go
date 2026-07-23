package measure

import (
	"fmt"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// header is the fixed vector-table + prologue + epilogue, copied verbatim
// from the Task-1 spike (decode/gen-go/measure/spike/latspike.S), with the
// LED/PIO marker address parameterized. %s is substituted with the payload
// (calibration + independent + dependent brackets) emitted between "begin:"
// and the "bra _done" epilogue.
const headerTmpl = `#include "sim_instr.h"
        .section .vect
        .long start
        .long 0x00007000
        .long start
        .long 0x00007000
        .rept 60
        .long 0
        .endr
        .long SIM_INSTR_MAGIC
        .long _sim_instr_end
        .long _done
        .long _fail
        .long CMD_ENABLE_TEST_RESULT
_sim_instr_end: .long 0
        .text
        .global start
start:
        mov.l   led, r14           ! r14 = 0x%08X (PIO marker addr)
        bra     begin
        nop
        .align 2
led:    .long   0x%08X
begin:
%s        bra     _done
        nop
        .align 2
_done:
        mov.l   p_res, r0
        mov     #0, r9
        mov.l   r9, @r0
        bra     _done
        nop
_fail:
        mov.l   p_res, r0
        mov     #1, r9
        mov.l   r9, @r0
        bra     _fail
        nop
        .align 2
p_res:  .long   TEST_RESULT_ADDRESS
`

// scratch registers used by the independent chain, rotating so no two
// adjacent ops share a destination.
var indepRegs = []string{"r1", "r2", "r3", "r4", "r5", "r6", "r7", "r8"}

// dependent chain destination: every copy chains through this single reg.
const depReg = "r1"

// marker writes a byte marker id (mov #0xNN,r0; mov.b r0,@r14) to sb.
func marker(sb *strings.Builder, id uint8) {
	fmt.Fprintf(sb, "        mov     #0x%02X, r0\n", id)
	sb.WriteString("        mov.b   r0, @r14\n")
}

// mnemonic extracts the gas mnemonic from a spec.Instr.Name, e.g.
// "ADD Rm, Rn" -> "add". Slash-suffixed forms ("CMP /EQ Rm, Rn", "CMP /PL
// Rn") are spec-table shorthand for gas's "cmp/eq", "cmp/pl" mnemonics: if
// the token immediately following the leading mnemonic starts with "/",
// join it (lowercased, no space) rather than discarding it -- discarding it
// silently emits the base mnemonic ("cmp r9,r1"), which gas rejects (or
// worse, assembles a different instruction than intended).
func mnemonic(in spec.Instr) string {
	name := strings.TrimSpace(in.Name)
	fields := strings.Fields(name)
	if len(fields) == 0 {
		return ""
	}
	mn := strings.ToLower(fields[0])
	if len(fields) > 1 && strings.HasPrefix(fields[1], "/") {
		mn += strings.ToLower(fields[1])
	}
	return mn
}

// operandRegs returns the register operand names used to build the
// independent/dependent chains for in. Only register-register ops (dst, src)
// are supported by the default template; dst is what the dependent chain
// chains through, src is a fixed helper register preloaded with #1 once by
// the register-register template.
func operandRegs(in spec.Instr) (dst, src string) {
	return depReg, "r9"
}

// instrLine formats a single indented assembly instruction line, padding the
// mnemonic to an 8-column field to match the hand-written style used
// throughout this package (e.g. "        add     #1, r1\n").
func instrLine(mn, operand string) string {
	if operand == "" {
		return fmt.Sprintf("        %s\n", mn)
	}
	return fmt.Sprintf("        %-8s%s\n", mn, operand)
}

// GenDefault emits the default auto-chain microbenchmark .S for in: the
// fixed vector-table/epilogue header (parameterized by ledAddr) plus
// calibration-A (0x11/0x12, 100 nops), calibration-B (0x13/0x14, 200 nops),
// an independent chain (0x33/0x44, count copies rotating disjoint dest
// regs), and a dependent chain (0x55/0x66, count copies all chained through
// one dest register).
func GenDefault(in spec.Instr, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}
	dst, _ := operandRegs(in)

	var body strings.Builder

	// --- calibration A: 100 nops ---
	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	// --- calibration B: 200 nops ---
	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	// --- independent chain: count copies, rotating disjoint regs ---
	marker(&body, 0x33)
	for i := 0; i < count; i++ {
		reg := indepRegs[i%len(indepRegs)]
		fmt.Fprintf(&body, "        %s     #1, %s\n", mn, reg)
	}
	marker(&body, 0x44)

	// --- dependent chain: count copies, all chained through dst ---
	marker(&body, 0x55)
	body.WriteString("        .rept " + fmt.Sprint(count) + "\n")
	fmt.Fprintf(&body, "        %s     #1, %s\n", mn, dst)
	body.WriteString("        .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// Gen dispatches on rec.Template to produce the microbenchmark .S for in.
// It is the general entry point used by the harness driver; GenDefault
// remains available directly for the "imm" template and for callers that
// pre-date the template dispatch.
//
// A recipe that is explicitly marked non-measurable (a genuine hand-entered
// latency value: Measurable==false with a Why explaining it) yields the
// ("", nil) sentinel so the driver falls back to the hand value instead of
// generating a benchmark. Zero-value Recipe literals (Measurable defaults to
// false with no Why) are treated as ordinary, measurable recipes -- that
// default only becomes meaningful once populated via Recipes.For, which
// always sets Measurable explicitly one way or the other.
func Gen(in spec.Instr, rec Recipe, count int, ledAddr uint32) (string, error) {
	if !rec.Measurable && rec.Why != "" {
		return "", nil
	}
	switch rec.Template {
	case "", "default":
		return genRegReg(in, count, ledAddr)
	case "imm":
		return GenDefault(in, count, ledAddr)
	case "unary":
		return genUnary(in, count, ledAddr)
	case "nullary":
		return genNullary(in, count, ledAddr)
	case "load":
		return genLoad(in, rec, count, ledAddr)
	case "store":
		return genStore(in, rec, count, ledAddr)
	case "branch":
		return genBranch(in, rec, count, ledAddr)
	case "twoword":
		return genTwoWord(in, rec, count, ledAddr)
	case "sreg":
		return genSreg(in, count, ledAddr)
	case "immr0":
		return genImmR0(in, count, ledAddr)
	case "loaddisp":
		return genLoadDisp(in, rec, count, ledAddr)
	case "storedisp":
		return genStoreDisp(in, rec, count, ledAddr)
	case "loaddispr0":
		return genLoadDispR0(in, rec, count, ledAddr)
	case "storedispr0":
		return genStoreDispR0(in, rec, count, ledAddr)
	case "loadr0idx":
		return genLoadR0Idx(in, rec, count, ledAddr)
	case "storer0idx":
		return genStoreR0Idx(in, rec, count, ledAddr)
	case "loadinc":
		return genLoadInc(in, rec, count, ledAddr)
	case "storedec":
		return genStoreDec(in, rec, count, ledAddr)
	default:
		return "", fmt.Errorf("unknown template %q", rec.Template)
	}
}

// genRegReg emits the register-register form of the auto-chain
// microbenchmark: <mn> src, dst. This is the "default" template and covers
// ALU ops that have no immediate form (sub, and, or, xor, mov Rm,Rn, ...).
// src (r9) is preloaded once with #1 before the calibration brackets; the
// independent chain rotates dst over r1..r8 against the fixed src, and the
// dependent chain chains count copies through a single dst (r1).
func genRegReg(in spec.Instr, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}
	dst, src := operandRegs(in)

	var body strings.Builder

	// --- preload the fixed src operand once ---
	body.WriteString(instrLine("mov", fmt.Sprintf("#1, %s", src)))

	// --- calibration A: 100 nops ---
	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	// --- calibration B: 200 nops ---
	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	// --- independent chain: count copies, rotating disjoint dst regs ---
	marker(&body, 0x33)
	for i := 0; i < count; i++ {
		reg := indepRegs[i%len(indepRegs)]
		body.WriteString(instrLine(mn, fmt.Sprintf("%s, %s", src, reg)))
	}
	marker(&body, 0x44)

	// --- dependent chain: count copies, all chained through dst ---
	marker(&body, 0x55)
	body.WriteString("        .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, fmt.Sprintf("%s, %s", src, dst)))
	body.WriteString("        .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genUnary emits the "unary" template: <mn> rn, a single-register-operand
// form (shll rn, dt rn, movt rn, cmp/pl rn, ...) with no memory reference.
// No operand needs preloading: shift/rotate/dt/movt/cmp-style ops read and
// write the same register (or need no meaningful initial value for a
// latency measurement). The independent chain rotates the operand register
// over r1..r8 so consecutive ops don't share a register (no dependency);
// the dependent chain runs count copies all through r1 so each op depends
// on the previous op's result.
func genUnary(in spec.Instr, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}

	var body strings.Builder

	// --- calibration A: 100 nops ---
	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	// --- calibration B: 200 nops ---
	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	// --- independent chain: count ops, rotating disjoint operand regs ---
	marker(&body, 0x33)
	for i := 0; i < count; i++ {
		reg := indepRegs[i%len(indepRegs)]
		body.WriteString(instrLine(mn, reg))
	}
	marker(&body, 0x44)

	// --- dependent chain: count ops, all chained through r1 ---
	marker(&body, 0x55)
	body.WriteString("        .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, depReg))
	body.WriteString("        .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genNullary emits the "nullary" template: <mn> with no operand at all
// (CLRT, SETT, CLRMAC, DIV0U, ...). There is no data dependency possible
// between successive copies (no register/memory operand carries state), so
// independent and dependent chains are identical back-to-back sequences;
// only the issue-rate bracket is a meaningful measurement, and latency is
// reported equal to issue (no distinguishable load-use-style delay to
// isolate for a zero-operand op).
func genNullary(in spec.Instr, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}

	var body strings.Builder

	// --- calibration A: 100 nops ---
	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	// --- calibration B: 200 nops ---
	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	// --- independent chain: count copies, no operand ---
	marker(&body, 0x33)
	body.WriteString("        .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, ""))
	body.WriteString("        .endr\n")
	marker(&body, 0x44)

	// --- dependent chain: identical to independent (no data dependency
	// possible for a zero-operand op) ---
	marker(&body, 0x55)
	body.WriteString("        .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, ""))
	body.WriteString("        .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genImmR0 emits the "immr0" template: <mn> #1, r0 -- immediate ops whose
// destination is hard-wired to R0 (AND/OR/XOR/TST #imm,R0; CMP/EQ #imm,R0).
// Unlike the general "imm" template, the destination register can't be
// rotated in the independent chain (there is only ever r0), so both
// brackets emit the identical back-to-back sequence through r0 -- there is
// no distinguishable independent-vs-dependent shape for a fixed-register
// op, so issue and latency are expected to measure equal by construction
// (mirrors genNullary's rationale).
func genImmR0(in spec.Instr, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}

	var body strings.Builder

	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	// --- independent chain: count copies, fixed r0 (can't rotate) ---
	marker(&body, 0x33)
	body.WriteString("        .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, "#1, r0"))
	body.WriteString("        .endr\n")
	marker(&body, 0x44)

	// --- dependent chain: identical (r0 is always the operand) ---
	marker(&body, 0x55)
	body.WriteString("        .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, "#1, r0"))
	body.WriteString("        .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genSreg emits the "sreg" template: STS <SPECIAL>, Rn / LDS Rm, <SPECIAL>
// for the special-register move ops (MACH/MACL/PR). The special register
// is a fixed operand (source for STS, destination for LDS) with no
// data-dependent chain possible across successive copies, so -- like
// genImmR0/genNullary -- both brackets emit the identical sequence and
// issue/latency are expected to measure equal by construction.
func genSreg(in spec.Instr, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}
	special, stsDirection, ok := specialRegOperand(in)
	if !ok {
		return "", fmt.Errorf("could not derive special-register operand from instruction name %q", in.Name)
	}
	var operand string
	if stsDirection {
		operand = fmt.Sprintf("%s, %s", special, depReg)
	} else {
		operand = fmt.Sprintf("%s, %s", depReg, special)
	}

	var body strings.Builder

	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	// --- independent chain: count copies, fixed operand (no rotation possible) ---
	marker(&body, 0x33)
	body.WriteString("        .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, operand))
	body.WriteString("        .endr\n")
	marker(&body, 0x44)

	// --- dependent chain: identical (special register is a fixed operand) ---
	marker(&body, 0x55)
	body.WriteString("        .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, operand))
	body.WriteString("        .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genLoad emits the "load" template: a pointer register is preloaded (via a
// branch-around literal pool, same trick the header uses for led) from
// rec.Ptr/rec.Region, then memory at that address is seeded to point at
// itself (mem[region] == region) so the pointer can safely "chase itself"
// across an arbitrary number of dependent loads without ever faulting.
//
// The independent chain issues count loads from the fixed pointer into
// rotating disjoint dest regs (no register dependency between them, only
// structural issue rate; the pointer register itself is never touched).
// The dependent chain issues count loads that each use the previous load's
// result as the next address (@ptr, ptr) -- because mem[region] == region,
// the reloaded value is always the valid pointer again, so the chain is
// both execution-safe and a genuine load-use latency measurement.
func genLoad(in spec.Instr, rec Recipe, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}
	ptr := rec.Ptr
	if ptr == "" {
		ptr = "r10"
	}

	var body strings.Builder

	// --- set up the pointer register from a nearby literal pool ---
	// (pc-relative mov.l requires a forward displacement, so the literal
	// must follow the load, skipped over via a branch -- same trick the
	// header uses for led.)
	body.WriteString(instrLine("mov.l", fmt.Sprintf("ptr_lit, %s", ptr)))
	body.WriteString("        bra     1f\n        nop\n        .align 2\n")
	fmt.Fprintf(&body, "ptr_lit:        .long   0x%08X\n", rec.Region)
	body.WriteString("1:\n")

	// --- self-pointer-chase seed: mem[region] = region ---
	// after this, @ptr always reloads a valid pointer to itself, so a
	// dependent chain of loads-through-ptr can run for any count without
	// ever dereferencing garbage.
	body.WriteString(instrLine("mov.l", fmt.Sprintf("%s, @%s", ptr, ptr)))

	// --- calibration A: 100 nops ---
	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	// --- calibration B: 200 nops ---
	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	// --- independent chain: count loads into rotating disjoint dest regs ---
	// ptr is never overwritten, so every load reads the same valid address.
	marker(&body, 0x33)
	for i := 0; i < count; i++ {
		reg := indepRegs[i%len(indepRegs)]
		body.WriteString(instrLine(mn, fmt.Sprintf("@%s, %s", ptr, reg)))
	}
	marker(&body, 0x44)

	// --- dependent chain: load-use, each load's result is the next address ---
	// execution-safe self-chase: mem[region] == region, so ptr stays valid.
	marker(&body, 0x55)
	body.WriteString("        .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, fmt.Sprintf("@%s, %s", ptr, ptr)))
	body.WriteString("        .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genStore emits the "store" template: independent chain issues count
// back-to-back stores of a fixed value register to the same address (no
// inter-op register dependency); the dependent chain alternates
// store-then-load-back through the same address to force store->load
// ordering.
func genStore(in spec.Instr, rec Recipe, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}
	ptr := rec.Ptr
	if ptr == "" {
		ptr = "r10"
	}
	valReg := depReg

	var body strings.Builder

	body.WriteString(instrLine("mov.l", fmt.Sprintf("ptr_lit, %s", ptr)))
	body.WriteString("        bra     1f\n        nop\n        .align 2\n")
	fmt.Fprintf(&body, "ptr_lit:        .long   0x%08X\n", rec.Region)
	body.WriteString("1:\n")
	body.WriteString(instrLine("mov", fmt.Sprintf("#1, %s", valReg)))

	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	// --- independent chain: back-to-back stores, no register dependency ---
	marker(&body, 0x33)
	for i := 0; i < count; i++ {
		body.WriteString(instrLine(mn, fmt.Sprintf("%s, @%s", valReg, ptr)))
	}
	marker(&body, 0x44)

	// --- dependent chain: store then read back to force ordering ---
	marker(&body, 0x55)
	body.WriteString("        .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, fmt.Sprintf("%s, @%s", valReg, ptr)))
	body.WriteString(instrLine("mov.l", fmt.Sprintf("@%s, %s", ptr, valReg)))
	body.WriteString("        .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genBranch emits the "branch" template: T is set once (sett), then both
// brackets are an identical .rept-bounded sequence of always-taken
// conditional/unconditional branches to a numeric local label placed right
// after the branch (a "+2" target), so every branch redirects the pipeline
// even though it lands where sequential execution would have gone anyway --
// isolating the taken-branch penalty from any useful work skipped.
func genBranch(in spec.Instr, rec Recipe, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}

	trips := count
	if rec.Loop > 0 {
		trips = rec.Loop
	}

	branchBracket := func(body *strings.Builder) {
		body.WriteString("        .rept " + fmt.Sprint(trips) + "\n")
		body.WriteString(instrLine(mn, "1f"))
		body.WriteString("1:\n")
		body.WriteString("        .endr\n")
	}

	var body strings.Builder

	body.WriteString("        sett\n")

	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	marker(&body, 0x33)
	branchBracket(&body)
	marker(&body, 0x44)

	marker(&body, 0x55)
	branchBracket(&body)
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// opcodeToWord folds a 16-bit spec opcode pattern (chars '0'/'1' plus
// variable-field letters such as n/m/d) into a concrete machine word with
// every variable bit set to 0.
func opcodeToWord(pattern string) (uint16, error) {
	pattern = strings.TrimSpace(pattern)
	if len(pattern) != 16 {
		return 0, fmt.Errorf("opcode pattern %q must be 16 bits, got %d", pattern, len(pattern))
	}
	var w uint16
	for _, c := range pattern {
		w <<= 1
		if c == '1' {
			w |= 1
		}
	}
	return w, nil
}

// genTwoWord emits the "twoword" template for extension-word instructions
// that sh2-elf-as's mnemonic table does not know: the opcode (variable
// fields zeroed) and a zero extension word are emitted directly via .word,
// mirroring the approach used in sim/tests/sh2a_movml0.S.
func genTwoWord(in spec.Instr, rec Recipe, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	word, err := opcodeToWord(in.Opcode)
	if err != nil {
		return "", err
	}
	const extWord = 0x0000

	twoWordOp := func(body *strings.Builder) {
		fmt.Fprintf(body, "        .word   0x%04X\n        .word   0x%04X\n", word, extWord)
	}

	var body strings.Builder

	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	marker(&body, 0x33)
	for i := 0; i < count; i++ {
		twoWordOp(&body)
	}
	marker(&body, 0x44)

	marker(&body, 0x55)
	body.WriteString("        .rept " + fmt.Sprint(count) + "\n")
	twoWordOp(&body)
	body.WriteString("        .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// dispOffset is the fixed displacement (in bytes) used by every
// displacement-addressed template below. It is small, word-aligned, and
// well within any reasonable RAM region, so no bounds arithmetic is needed.
const dispOffset = 4

// emitPtrSetup emits the branch-around-literal-pool sequence that loads ptr
// with the 32-bit constant region, the same trick the header uses for led
// (pc-relative mov.l needs a forward literal). literalLabel must be unique
// within the emitted .S if emitPtrSetup is called more than once (e.g. to
// reset ptr mid-body for the "loadinc"/"storedec" templates); the "1:"/"1f"
// branch target is a numeric local label and may be freely redefined by gas.
func emitPtrSetup(body *strings.Builder, ptr, literalLabel string, region uint32) {
	body.WriteString(instrLine("mov.l", fmt.Sprintf("%s, %s", literalLabel, ptr)))
	body.WriteString("        bra     1f\n        nop\n        .align 2\n")
	fmt.Fprintf(body, "%s:        .long   0x%08X\n", literalLabel, region)
	body.WriteString("1:\n")
}

// genLoadDisp emits the "loaddisp" template: <mn> @(4, Rm), Rn -- the
// general-register displacement load (MOV.L @(disp,Rm),Rn). disp is fixed
// (dispOffset) so ptr never moves: independent chain rotates the
// destination over disjoint regs with ptr untouched; dependent chain
// self-chases through dest=ptr (mem[ptr+disp] is seeded to ptr itself, so
// each reload keeps ptr valid), giving a genuine load-use latency
// measurement without ever drifting the address.
func genLoadDisp(in spec.Instr, rec Recipe, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}
	ptr := rec.Ptr
	if ptr == "" {
		ptr = "r10"
	}

	var body strings.Builder
	emitPtrSetup(&body, ptr, "ptr_lit", rec.Region)

	// --- self-chase seed: mem[ptr+disp] = ptr ---
	body.WriteString(instrLine("mov.l", fmt.Sprintf("%s, @(%d, %s)", ptr, dispOffset, ptr)))

	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	// --- independent chain: count loads into rotating disjoint dest regs ---
	marker(&body, 0x33)
	for i := 0; i < count; i++ {
		reg := indepRegs[i%len(indepRegs)]
		body.WriteString(instrLine(mn, fmt.Sprintf("@(%d, %s), %s", dispOffset, ptr, reg)))
	}
	marker(&body, 0x44)

	// --- dependent chain: load-use, self-chase through dest=ptr ---
	marker(&body, 0x55)
	body.WriteString(" .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, fmt.Sprintf("@(%d, %s), %s", dispOffset, ptr, ptr)))
	body.WriteString(" .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genStoreDisp emits the "storedisp" template: <mn> Rm, @(4, Rn) -- the
// general-register displacement store (MOV.L Rm,@(disp,Rn)). Same shape as
// genStore, just with the fixed-disp address form.
func genStoreDisp(in spec.Instr, rec Recipe, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}
	ptr := rec.Ptr
	if ptr == "" {
		ptr = "r10"
	}
	valReg := depReg

	var body strings.Builder
	emitPtrSetup(&body, ptr, "ptr_lit", rec.Region)
	body.WriteString(instrLine("mov", fmt.Sprintf("#1, %s", valReg)))

	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	// --- independent chain: count back-to-back stores, fixed address ---
	marker(&body, 0x33)
	for i := 0; i < count; i++ {
		body.WriteString(instrLine(mn, fmt.Sprintf("%s, @(%d, %s)", valReg, dispOffset, ptr)))
	}
	marker(&body, 0x44)

	// --- dependent chain: store then read back to force ordering ---
	marker(&body, 0x55)
	body.WriteString(" .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, fmt.Sprintf("%s, @(%d, %s)", valReg, dispOffset, ptr)))
	body.WriteString(instrLine("mov.l", fmt.Sprintf("@(%d, %s), %s", dispOffset, ptr, valReg)))
	body.WriteString(" .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genLoadDispR0 emits the "loaddispr0" template: <mn> @(4, Rm), R0 -- the
// R0-fixed-destination displacement load (MOV.B/W @(disp,Rm),R0). Like
// genImmR0/genSreg, the destination is hard-wired to R0 so no rotation is
// possible: both brackets emit the identical back-to-back sequence, so
// issue rate is what's measured. Memory is seeded with a known value (not
// used as a chase pointer, just so no uninitialized read propagates X).
func genLoadDispR0(in spec.Instr, rec Recipe, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}
	ptr := rec.Ptr
	if ptr == "" {
		ptr = "r10"
	}

	var body strings.Builder
	emitPtrSetup(&body, ptr, "ptr_lit", rec.Region)
	body.WriteString(instrLine("mov", "#0, r0"))
	body.WriteString(instrLine("mov.l", fmt.Sprintf("r0, @(%d, %s)", dispOffset, ptr)))

	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	operand := fmt.Sprintf("@(%d, %s), r0", dispOffset, ptr)

	marker(&body, 0x33)
	body.WriteString(" .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, operand))
	body.WriteString(" .endr\n")
	marker(&body, 0x44)

	marker(&body, 0x55)
	body.WriteString(" .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, operand))
	body.WriteString(" .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genStoreDispR0 emits the "storedispr0" template: <mn> R0, @(4, Rn) -- the
// R0-fixed-source displacement store (MOV.B/W R0,@(disp,Rn)). Source is
// hard-wired to R0, so like genLoadDispR0 both brackets are identical.
func genStoreDispR0(in spec.Instr, rec Recipe, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}
	ptr := rec.Ptr
	if ptr == "" {
		ptr = "r10"
	}

	var body strings.Builder
	emitPtrSetup(&body, ptr, "ptr_lit", rec.Region)
	body.WriteString(instrLine("mov", "#1, r0"))

	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	operand := fmt.Sprintf("r0, @(%d, %s)", dispOffset, ptr)

	marker(&body, 0x33)
	body.WriteString(" .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, operand))
	body.WriteString(" .endr\n")
	marker(&body, 0x44)

	marker(&body, 0x55)
	body.WriteString(" .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, operand))
	body.WriteString(" .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genLoadR0Idx emits the "loadr0idx" template: <mn> @(r0, Rm), Rn -- the
// R0-indexed load (MOV.B/W/L @(R0,Rm),Rn). r0 is preloaded to 0 and never
// touched again, so @(r0,ptr) behaves exactly like the plain-indirect
// @ptr self-chase in genLoad: mem[ptr] is seeded to ptr, and the dependent
// chain reloads through dest=ptr to stay valid indefinitely.
func genLoadR0Idx(in spec.Instr, rec Recipe, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}
	ptr := rec.Ptr
	if ptr == "" {
		ptr = "r10"
	}

	var body strings.Builder
	emitPtrSetup(&body, ptr, "ptr_lit", rec.Region)
	// NOTE: r0 must be re-set to 0 immediately before each bracket, not just
	// once up front -- marker() clobbers r0 as scratch (mov #0xNN, r0), so a
	// one-time preload here would leave a stale marker byte in r0 as the
	// address offset by the time the load loop runs (@(r0,ptr) then reads
	// from the wrong -- and potentially misaligned -- address).
	body.WriteString(instrLine("mov", "#0, r0"))
	body.WriteString(instrLine("mov.l", fmt.Sprintf("%s, @(r0, %s)", ptr, ptr)))

	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	// --- independent chain: count loads into rotating disjoint dest regs ---
	marker(&body, 0x33)
	body.WriteString(instrLine("mov", "#0, r0"))
	for i := 0; i < count; i++ {
		reg := indepRegs[i%len(indepRegs)]
		body.WriteString(instrLine(mn, fmt.Sprintf("@(r0, %s), %s", ptr, reg)))
	}
	marker(&body, 0x44)

	// --- dependent chain: load-use, self-chase through dest=ptr ---
	marker(&body, 0x55)
	body.WriteString(instrLine("mov", "#0, r0"))
	body.WriteString(" .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, fmt.Sprintf("@(r0, %s), %s", ptr, ptr)))
	body.WriteString(" .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genStoreR0Idx emits the "storer0idx" template: <mn> Rm, @(r0, Rn) -- the
// R0-indexed store (MOV.B/W/L Rm,@(R0,Rn)). r0 preloaded to 0, ptr never
// touched; shape mirrors genStore (back-to-back independent, store+readback
// dependent).
func genStoreR0Idx(in spec.Instr, rec Recipe, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}
	ptr := rec.Ptr
	if ptr == "" {
		ptr = "r10"
	}
	valReg := depReg

	var body strings.Builder
	emitPtrSetup(&body, ptr, "ptr_lit", rec.Region)
	body.WriteString(instrLine("mov", fmt.Sprintf("#1, %s", valReg)))

	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	// r0 is re-set to 0 immediately before each bracket -- marker() clobbers
	// r0 as scratch, so a one-time preload up front would leave a stale
	// marker byte as the address offset for @(r0,ptr) (see genLoadR0Idx).
	marker(&body, 0x33)
	body.WriteString(instrLine("mov", "#0, r0"))
	for i := 0; i < count; i++ {
		body.WriteString(instrLine(mn, fmt.Sprintf("%s, @(r0, %s)", valReg, ptr)))
	}
	marker(&body, 0x44)

	marker(&body, 0x55)
	body.WriteString(instrLine("mov", "#0, r0"))
	body.WriteString(" .rept " + fmt.Sprint(count) + "\n")
	body.WriteString(instrLine(mn, fmt.Sprintf("%s, @(r0, %s)", valReg, ptr)))
	body.WriteString(instrLine("mov.l", fmt.Sprintf("@(r0, %s), %s", ptr, valReg)))
	body.WriteString(" .endr\n")
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genLoadInc emits the "loadinc" template: <mn> @Rm+, Rn -- post-increment
// load (MOV.B/W/L @Rm+,Rn). Every copy reads and rewrites ptr (structural
// RAW/WAW hazard on the base register itself), so the two brackets are
// necessarily identical in shape regardless of which dest reg is used --
// there's no distinct dest-value dependency to isolate for a "dependent"
// bracket here, so latency == issue by construction. ptr is reset (via a
// second literal pool) before the second bracket so the total advance
// across both brackets never has to be bounded by count alone.
func genLoadInc(in spec.Instr, rec Recipe, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}
	ptr := rec.Ptr
	if ptr == "" {
		ptr = "r10"
	}

	var body strings.Builder
	emitPtrSetup(&body, ptr, "ptr_lit", rec.Region)

	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	marker(&body, 0x33)
	for i := 0; i < count; i++ {
		reg := indepRegs[i%len(indepRegs)]
		body.WriteString(instrLine(mn, fmt.Sprintf("@%s+, %s", ptr, reg)))
	}
	marker(&body, 0x44)

	// --- reset ptr: post-inc has no dest-value dependency, both brackets
	// are structurally identical; reset keeps the address bounded ---
	marker(&body, 0x55)
	emitPtrSetup(&body, ptr, "ptr_lit2", rec.Region)
	for i := 0; i < count; i++ {
		reg := indepRegs[i%len(indepRegs)]
		body.WriteString(instrLine(mn, fmt.Sprintf("@%s+, %s", ptr, reg)))
	}
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}

// genStoreDec emits the "storedec" template: <mn> Rm, @-Rn -- pre-decrement
// store (MOV.B/W/L Rm,@-Rn). Same structural-hazard reasoning as genLoadInc
// applies (every copy reads/rewrites ptr), so both brackets are identical
// and ptr is reset between them. rec.Region is expected to already be a
// base high enough that count pre-decrements stay within RAM (classify sets
// it to the load/store region plus a safety margin).
func genStoreDec(in spec.Instr, rec Recipe, count int, ledAddr uint32) (string, error) {
	if count <= 0 {
		return "", fmt.Errorf("count must be positive, got %d", count)
	}
	mn := mnemonic(in)
	if mn == "" {
		return "", fmt.Errorf("could not derive mnemonic from instruction name %q", in.Name)
	}
	ptr := rec.Ptr
	if ptr == "" {
		ptr = "r10"
	}
	valReg := depReg

	var body strings.Builder
	emitPtrSetup(&body, ptr, "ptr_lit", rec.Region)
	body.WriteString(instrLine("mov", fmt.Sprintf("#1, %s", valReg)))

	marker(&body, 0x11)
	body.WriteString("        .rept 100\n        nop\n        .endr\n")
	marker(&body, 0x12)

	marker(&body, 0x13)
	body.WriteString("        .rept 200\n        nop\n        .endr\n")
	marker(&body, 0x14)

	marker(&body, 0x33)
	for i := 0; i < count; i++ {
		body.WriteString(instrLine(mn, fmt.Sprintf("%s, @-%s", valReg, ptr)))
	}
	marker(&body, 0x44)

	marker(&body, 0x55)
	emitPtrSetup(&body, ptr, "ptr_lit2", rec.Region)
	for i := 0; i < count; i++ {
		body.WriteString(instrLine(mn, fmt.Sprintf("%s, @-%s", valReg, ptr)))
	}
	marker(&body, 0x66)

	return fmt.Sprintf(headerTmpl, ledAddr, ledAddr, body.String()), nil
}
