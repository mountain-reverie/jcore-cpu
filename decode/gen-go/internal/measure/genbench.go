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
// "ADD Rm, Rn" -> "add".
func mnemonic(in spec.Instr) string {
	name := strings.TrimSpace(in.Name)
	if i := strings.IndexAny(name, " \t"); i >= 0 {
		name = name[:i]
	}
	return strings.ToLower(name)
}

// operandRegs returns the register operand names used to build the
// independent/dependent chains for in. Only register-register ops (dst, src)
// are supported by the default template; dst is what the dependent chain
// chains through, src is a fixed helper register.
func operandRegs(in spec.Instr) (dst, src string) {
	return depReg, "r2"
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
