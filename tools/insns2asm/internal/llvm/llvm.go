// Package llvm emits LLVM TableGen instruction-encoding records (bootstrap
// mode) from the IR. Register classes and MC C++ glue are authored separately.
package llvm

import (
	"fmt"
	"strings"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
)

// EmitInstrInfo renders one TableGen def per instruction.
func EmitInstrInfo(insns []ir.Insn) string {
	var b strings.Builder
	seen := map[string]int{}
	for _, in := range insns {
		name := defName(in, seen)
		fmt.Fprintf(&b, "def %s : Instruction {\n", name)
		fmt.Fprintf(&b, "  let Namespace = \"SH\";\n")
		width := 16 * len(in.Words)
		fmt.Fprintf(&b, "  bits<%d> Inst;\n", width)
		// Fixed bits, MSB-first across words. Bit number across words:
		// word0 bit15 is the most significant; we use LLVM convention where
		// Inst{0} is the LSB of the last word.
		for wi, w := range in.Words {
			for i := 0; i < 16; i++ {
				bit := w[i]
				if !bit.Fixed {
					continue
				}
				pos := bitPos(wi, i, len(in.Words))
				fmt.Fprintf(&b, "  let Inst{%d} = %d;\n", pos, bit.Val)
			}
		}
		fmt.Fprintf(&b, "  let AsmString = %q;\n", asmString(in))
		fmt.Fprintf(&b, "  let Predicates = [%s];\n", strings.Join(in.Arch.LLVMPredicates(), ", "))
		fmt.Fprintf(&b, "}\n\n")
	}
	return b.String()
}

// bitPos maps (word index, MSB-first index) to LLVM Inst{} bit number,
// where Inst{0} is the LSB of the final word.
func bitPos(wordIdx, msbIdx, nWords int) int {
	bitInWord := 15 - msbIdx
	wordsAfter := nWords - 1 - wordIdx
	return wordsAfter*16 + bitInWord
}

func defName(in ir.Insn, seen map[string]int) string {
	base := strings.ToUpper(strings.NewReplacer(".", "_", "/", "_").Replace(in.Mnemonic))
	for _, o := range in.Operands {
		base += "_" + o.Class.String()
	}
	seen[base]++
	if n := seen[base]; n > 1 {
		return fmt.Sprintf("%s_%d", base, n)
	}
	return base
}

func asmString(in ir.Insn) string {
	toks := make([]string, len(in.Operands))
	for i, o := range in.Operands {
		toks[i] = o.Token
	}
	if len(toks) == 0 {
		return in.Mnemonic
	}
	return in.Mnemonic + "\t" + strings.Join(toks, ", ")
}
