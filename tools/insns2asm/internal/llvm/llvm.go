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

// ScaleOf returns the displacement scale for a mnemonic's data size.
func ScaleOf(mnemonic string) int {
	switch {
	case mnemonic == "mova" || strings.HasSuffix(mnemonic, ".l"):
		return 4
	case strings.HasSuffix(mnemonic, ".w"):
		return 2
	case strings.HasSuffix(mnemonic, ".b"):
		return 1
	case strings.HasSuffix(mnemonic, ".d"):
		return 8
	}
	return 4 // PC long-form default
}

func sizeLetter(scale int) string {
	switch scale {
	case 1:
		return "b"
	case 2:
		return "w"
	case 8:
		return "d"
	}
	return "l"
}

// boundField is one encoding field that an operand binds to a variable.
// varName, when non-empty, overrides the LetterVar(letter) name (used for
// fixed-register memory operands that have no encoding field letter).
type boundField struct {
	letter  byte
	varName string           // synthetic var name override (non-empty for fixed-mem)
	fields  []encoding.Field // empty for fixed-reg memory (constrained, no encoding)
	class   string           // TableGen operand class name (e.g. GPR, bdisp12)
}

// bfVar returns the TableGen variable name for a bound field.
func bfVar(bf boundField) string {
	if bf.varName != "" {
		return bf.varName
	}
	return LetterVar(bf.letter)
}

// fixedMemClass returns the constrained operand class for a fixed-register
// memory operand (@R0 → MemR0Fixed, @-R15 → MemDecR15, @R15+ → MemIncR15).
func fixedMemClass(o operand.Operand) string {
	switch o.Class {
	case operand.MemReg:
		return "MemR0Fixed"
	case operand.MemPreDec:
		return "MemDecR15"
	case operand.MemPostInc:
		return "MemIncR15"
	}
	return "MemFixed"
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

		// Instructions with a fixed-register memory operand (@R0, @-R15, @R15+)
		// have an implicit register with no encoding field. Use an
		// instruction-level DecoderMethod that decodes the GPR field(s) and adds
		// the implicit register, so they round-trip through the disassembler.
		if dec, ok := fixedMemDecoder(in); ok {
			fmt.Fprintf(&b, "  let DecoderMethod = %q;\n", dec)
		}

		// operand bit variables (skip fixed-mem: no encoding field)
		for _, bf := range bfs {
			if len(bf.fields) == 0 {
				continue
			}
			total := 0
			for _, f := range bf.fields {
				total += f.Width
			}
			fmt.Fprintf(&b, "  bits<%d> %s;\n", total, bfVar(bf))
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
		// operand field bindings (high..low LLVM bit numbers); skip fixed-mem
		for _, bf := range bfs {
			if len(bf.fields) == 0 {
				continue
			}
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
					fmt.Fprintf(&b, "  let Inst{%d-%d} = %s;\n", instHi, instLo, bfVar(bf))
				} else {
					fmt.Fprintf(&b, "  let Inst{%d-%d} = %s{%d-%d};\n", instHi, instLo, bfVar(bf), varHi, varLo)
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

// fixedMemDecoder returns the instruction-level disassembler DecoderMethod for
// an instruction whose memory operand has a fixed (implicit) register — @R0,
// @-R15, @R15+ — keyed by the constrained operand class. The implicit register
// has no encoding field, so per-operand decoding cannot locate it; an
// instruction-level decoder extracts the GPR field(s) and adds the implicit
// operand. ok is false when the instruction has no fixed-register memory operand.
func fixedMemDecoder(in ir.Insn) (string, bool) {
	for _, o := range in.Operands {
		switch o.Class {
		case operand.FR0Fixed:
			return "decodeFmacFR0", true
		case operand.MemReg, operand.MemPostInc, operand.MemPreDec:
			if o.Fixed == "" {
				continue
			}
			switch fixedMemClass(o) {
			case "MemR0Fixed":
				return "decodeCasFixed", true
			case "MemDecR15":
				return "decodeMovMemDecR15", true
			case "MemIncR15":
				return "decodeMovMemIncR15", true
			}
		}
	}
	return "", false
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
		case operand.FR0Fixed:
			// Constrained operand — no encoding field but must appear in InOperandList
			// so the AsmMatcher uses the isFR0 predicate (not a literal token match).
			out = append(out, boundField{varName: "fr0", class: "FR0Fixed"})
		case operand.MemDisp:
			if fs := fieldsFor(in, o.BaseLetter); len(fs) > 0 {
				out = append(out, boundField{letter: o.BaseLetter, fields: fs, class: "GPR"})
			}
			if fs := fieldsFor(in, o.Letter); len(fs) > 0 {
				// Compute width-aware and scale-aware class name for MemDisp
				scale := ScaleOf(in.Mnemonic)
				W := 0
				for _, f := range fs {
					W += f.Width
				}
				class := fmt.Sprintf("memdisp_%s%d", sizeLetter(scale), W)
				out = append(out, boundField{letter: o.Letter, fields: fs, class: class})
			}
		case operand.MemGBR:
			if o.Letter == 0 {
				continue
			}
			if fs := fieldsFor(in, o.Letter); len(fs) > 0 {
				// Compute scale-aware class name for MemGBR
				scale := ScaleOf(in.Mnemonic)
				class := fmt.Sprintf("gbrdisp_%s8", sizeLetter(scale))
				out = append(out, boundField{letter: o.Letter, fields: fs, class: class})
			}
		case operand.MemPC:
			if o.Letter == 0 {
				continue
			}
			if fs := fieldsFor(in, o.Letter); len(fs) > 0 {
				// Compute scale-aware class name for MemPC
				scale := ScaleOf(in.Mnemonic)
				class := fmt.Sprintf("pcdisp_%s8", sizeLetter(scale))
				out = append(out, boundField{letter: o.Letter, fields: fs, class: class})
			}
		case operand.MemReg, operand.MemPostInc, operand.MemPreDec:
			if o.Fixed != "" {
				// Fixed-register memory: constrained class, no encoding field.
				out = append(out, boundField{varName: "fm", class: fixedMemClass(o)})
			} else if o.Letter != 0 {
				if fs := fieldsFor(in, o.Letter); len(fs) > 0 {
					out = append(out, boundField{letter: o.Letter, fields: fs, class: operandClassName(o)})
				}
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
	case operand.GPR, operand.MemReg, operand.MemPostInc:
		return "GPR"
	case operand.MemPreDec:
		return "MemDec"
	case operand.MemR0:
		return "MemR0Idx"
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
	case operand.FReg:
		return "FReg"
	case operand.DReg:
		return "DReg"
	case operand.XReg:
		return "XReg"
	case operand.FVReg:
		return "FVReg"
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
	case "GPR", "BankReg", "FReg", "DReg", "XReg", "FVReg", "SHImm", "MemDec", "MemR0Idx", "MemR0Fixed", "MemDecR15", "MemIncR15", "FR0Fixed":
		return false
	}
	// Scaled-displacement operand classes are hand-written in SHOperands.td
	// (with ParserMethod/EncoderMethod/DecoderMethod), not auto Operand<i32> stubs.
	if strings.HasPrefix(name, "memdisp_") ||
		strings.HasPrefix(name, "gbrdisp_") ||
		strings.HasPrefix(name, "pcdisp_") ||
		strings.HasPrefix(name, "tbrdisp") ||
		strings.HasPrefix(name, "bdisp") {
		return false
	}
	return true
}

func inOperandList(bfs []boundField) string {
	parts := make([]string, len(bfs))
	for i, bf := range bfs {
		parts[i] = fmt.Sprintf("%s:$%s", bf.class, bfVar(bf))
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
	case operand.FR0Fixed:
		return "${fr0}"
	case operand.FReg, operand.DReg, operand.XReg, operand.FVReg:
		return "${" + LetterVar(o.Letter) + "}"
	case operand.GPR, operand.BankReg, operand.Imm, operand.BranchDisp:
		return "${" + LetterVar(o.Letter) + "}"
	case operand.MemReg:
		if o.Fixed != "" {
			return "${fm}"
		}
		return "@${" + LetterVar(o.Letter) + "}"
	case operand.MemPostInc:
		if o.Fixed != "" {
			return "${fm}"
		}
		return "@${" + LetterVar(o.Letter) + "}+"
	case operand.MemPreDec:
		if o.Fixed != "" {
			return "${fm}"
		}
		return "${" + LetterVar(o.Letter) + "}"
	case operand.MemDisp:
		return "@(${" + LetterVar(o.Letter) + "}, ${" + LetterVar(o.BaseLetter) + "})"
	case operand.MemR0:
		return "${" + LetterVar(o.Letter) + "}"
	case operand.MemR0GBR:
		return "@(r0,gbr)"
	case operand.MemPC:
		return "@(${" + LetterVar(o.Letter) + "}, pc)"
	case operand.MemGBR:
		return "@(${" + LetterVar(o.Letter) + "}, gbr)"
	case operand.MemTBRDisp:
		return "@@(${" + LetterVar(o.Letter) + "}, tbr)"
	}
	return o.Token
}
