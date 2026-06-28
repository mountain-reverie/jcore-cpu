// Package oracle verifies that the IR losslessly round-trips instruction
// encodings, the always-on pure-Go correctness gate.
package oracle

import (
	"fmt"
	"strings"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
)

// Reconstruct rebuilds the canonical code string from an insn's words.
func Reconstruct(i ir.Insn) string {
	parts := make([]string, len(i.Words))
	for wi, w := range i.Words {
		var b strings.Builder
		for _, bit := range w {
			if bit.Fixed {
				if bit.Val == 1 {
					b.WriteByte('1')
				} else {
					b.WriteByte('0')
				}
			} else {
				b.WriteByte(bit.Letter)
			}
		}
		parts[wi] = b.String()
	}
	return strings.Join(parts, " ")
}

// CheckAll compares each insn's reconstructed encoding to the original code
// looked up by format string in raw. Returns one error per mismatch.
func CheckAll(insns []ir.Insn, raw map[string]string) []error {
	var errs []error
	for _, in := range insns {
		key := in.Mnemonic
		if len(in.Operands) > 0 {
			toks := make([]string, len(in.Operands))
			for i, o := range in.Operands {
				toks[i] = o.Token
			}
			key += "\t" + strings.Join(toks, ",")
		}
		want, ok := raw[key]
		if !ok {
			errs = append(errs, fmt.Errorf("no raw code for %q", key))
			continue
		}
		if got := Reconstruct(in); got != want {
			errs = append(errs, fmt.Errorf("%q: reconstruct %q != %q", key, got, want))
		}
	}
	return errs
}
