// Package llvm emits LLVM TableGen instruction-encoding records (bootstrap
// mode) from the IR, including operand-class defs, dag operand lists, and
// per-field operand-bit bindings. Register classes and MC C++ glue are
// authored separately (RISC-V-style layout).
package llvm

import (
	"fmt"
	"sort"
	"strings"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/encoding"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/operand"
)

// boundField is one encoding field that an operand binds to a variable.
type boundField struct {
	letter byte
	fields []encoding.Field // all encoding fields for this letter, in word order (MSB word first)
	class  string           // TableGen operand class name (e.g. GPR, bdisp12)
}

// EmitInstrInfo renders generated operand-class defs followed by one
// instruction def per insn.
func EmitInstrInfo(insns []ir.Insn) string {
	var b strings.Builder

	// Collect the set of generated Operand classes used (non-builtin).
	classes := map[string]bool{}
	for _, in := range insns {
		for _, bf := range boundFields(in) {
			if isGeneratedClass(bf.class) {
				classes[bf.class] = true
			}
		}
	}
	names := make([]string, 0, len(classes))
	for n := range classes {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		fmt.Fprintf(&b, "def %s : Operand<i32>;\n", n)
	}
	if len(names) > 0 {
		b.WriteString("\n")
	}

	seen := map[string]int{}
	for _, in := range insns {
		name := defName(in, seen)
		bfs := boundFields(in)
		fmt.Fprintf(&b, "def %s : Instruction {\n", name)
		fmt.Fprintf(&b, "  let Namespace = \"SH\";\n")
		width := 16 * len(in.Words)
		fmt.Fprintf(&b, "  bits<%d> Inst;\n", width)
		fmt.Fprintf(&b, "  let Size = %d;\n", 2*len(in.Words))
		fmt.Fprintf(&b, "  let DecoderNamespace = \"SH\";\n")

		// operand bit variables
		for _, bf := range bfs {
			total := 0
			for _, f := range bf.fields {
				total += f.Width
			}
			fmt.Fprintf(&b, "  bits<%d> %s;\n", total, LetterVar(bf.letter))
		}

		// fixed bits
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
		// operand field bindings (high..low LLVM bit numbers)
		for _, bf := range bfs {
			total := 0
			for _, f := range bf.fields {
				total += f.Width
			}
			cursor := total - 1
			single := len(bf.fields) == 1
			for _, f := range bf.fields {
				instHi := bitPos(f.Word, 15-f.Hi, len(in.Words))
				instLo := bitPos(f.Word, 15-f.Lo, len(in.Words))
				varHi := cursor
				varLo := cursor - f.Width + 1
				cursor -= f.Width
				if single {
					fmt.Fprintf(&b, "  let Inst{%d-%d} = %s;\n", instHi, instLo, LetterVar(bf.letter))
				} else {
					fmt.Fprintf(&b, "  let Inst{%d-%d} = %s{%d-%d};\n", instHi, instLo, LetterVar(bf.letter), varHi, varLo)
				}
			}
		}

		fmt.Fprintf(&b, "  dag OutOperandList = (outs);\n")
		fmt.Fprintf(&b, "  dag InOperandList = (ins %s);\n", inOperandList(bfs))
		fmt.Fprintf(&b, "  let AsmString = %q;\n", AsmString(in))
		fmt.Fprintf(&b, "  let Predicates = [%s];\n", strings.Join(in.Arch.LLVMPredicates(), ", "))
		fmt.Fprintf(&b, "}\n\n")
	}
	return b.String()
}

// boundFields returns, in operand order, the encoding fields bound by the
// instruction's operands. A MemDisp operand binds both its base register and
// its displacement. Fixed registers bind nothing.
func boundFields(in ir.Insn) []boundField {
	var out []boundField
	for _, o := range in.Operands {
		switch o.Class {
		case operand.FixedReg, operand.R0Fixed:
			// no field
		case operand.MemDisp:
			if fs := fieldsFor(in, o.BaseLetter); len(fs) > 0 {
				out = append(out, boundField{letter: o.BaseLetter, fields: fs, class: "GPR"})
			}
			if fs := fieldsFor(in, o.Letter); len(fs) > 0 {
				out = append(out, boundField{letter: o.Letter, fields: fs, class: dispClass(o)})
			}
		default:
			if o.Letter == 0 {
				continue
			}
			if fs := fieldsFor(in, o.Letter); len(fs) > 0 {
				out = append(out, boundField{letter: o.Letter, fields: fs, class: operandClassName(o)})
			}
		}
	}
	return out
}

func fieldsFor(in ir.Insn, letter byte) []encoding.Field {
	if letter == 0 {
		return nil
	}
	var fs []encoding.Field
	for _, f := range in.Fields {
		if f.Letter == letter {
			fs = append(fs, f)
		}
	}
	return fs
}

// operandClassName maps an operand to its TableGen operand class name.
func operandClassName(o operand.Operand) string {
	switch o.Class {
	case operand.GPR, operand.MemReg, operand.MemPostInc, operand.MemPreDec, operand.MemR0:
		return "GPR"
	case operand.BankReg:
		return "BankReg"
	case operand.Imm:
		return "SHImm"
	case operand.BranchDisp:
		return dispClass(o)
	case operand.MemTBRDisp:
		return "tbrdisp8"
	case operand.MemPC:
		return "pcdisp"
	case operand.MemGBR:
		return "gbrdisp"
	case operand.MemR0GBR:
		return "GPR"
	}
	return "SHImm"
}

func dispClass(o operand.Operand) string {
	switch o.Class {
	case operand.BranchDisp:
		if o.Width == 12 {
			return "bdisp12"
		}
		return "bdisp8"
	case operand.MemDisp:
		return fmt.Sprintf("memdisp%d", o.Width)
	}
	return "i32imm"
}

// isGeneratedClass reports whether a class name needs a generated
// `def NAME : Operand<i32>;` (i.e. not a builtin or hand-written register class).
func isGeneratedClass(name string) bool {
	switch name {
	case "GPR", "BankReg", "SHImm":
		return false
	}
	return true
}

func inOperandList(bfs []boundField) string {
	parts := make([]string, len(bfs))
	for i, bf := range bfs {
		parts[i] = fmt.Sprintf("%s:$%s", bf.class, LetterVar(bf.letter))
	}
	return strings.Join(parts, ", ")
}

// LetterVar maps an encoding field letter to its TableGen operand variable name.
func LetterVar(letter byte) string {
	switch letter {
	case 'n':
		return "rn"
	case 'm':
		return "rm"
	case 'i':
		return "imm"
	case 'd':
		return "disp"
	}
	return string(letter)
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

// AsmString builds the AsmString with $vars for bound operands and lowercased
// literals for fixed registers.
func AsmString(in ir.Insn) string {
	if len(in.Operands) == 0 {
		return in.Mnemonic
	}
	parts := make([]string, len(in.Operands))
	for i, o := range in.Operands {
		parts[i] = asmOperand(o)
	}
	return in.Mnemonic + "\t" + strings.Join(parts, ", ")
}

// asmOperand renders one operand for the AsmString, preserving addressing
// punctuation and substituting $vars for bound fields.
func asmOperand(o operand.Operand) string {
	switch o.Class {
	case operand.FixedReg:
		return strings.ToLower(o.Fixed)
	case operand.R0Fixed:
		return "r0"
	case operand.GPR, operand.BankReg, operand.Imm, operand.BranchDisp:
		return "${" + LetterVar(o.Letter) + "}"
	case operand.MemReg:
		if o.Fixed != "" {
			return "@" + strings.ToLower(o.Fixed)
		}
		return "@${" + LetterVar(o.Letter) + "}"
	case operand.MemPostInc:
		if o.Fixed != "" {
			return "@" + strings.ToLower(o.Fixed) + "+"
		}
		return "@${" + LetterVar(o.Letter) + "}+"
	case operand.MemPreDec:
		if o.Fixed != "" {
			return "@-" + strings.ToLower(o.Fixed)
		}
		return "@-${" + LetterVar(o.Letter) + "}"
	case operand.MemDisp:
		return "@(${" + LetterVar(o.Letter) + "}, ${" + LetterVar(o.BaseLetter) + "})"
	case operand.MemR0:
		return "@(r0, ${" + LetterVar(o.Letter) + "})"
	case operand.MemR0GBR:
		return "@(r0, gbr)"
	case operand.MemPC:
		return "@(${" + LetterVar(o.Letter) + "}, pc)"
	case operand.MemGBR:
		return "@(${" + LetterVar(o.Letter) + "}, gbr)"
	case operand.MemTBRDisp:
		return "@@(${" + LetterVar(o.Letter) + "}, tbr)"
	}
	return o.Token
}
