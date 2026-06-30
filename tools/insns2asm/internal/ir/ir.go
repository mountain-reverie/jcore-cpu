// Package ir assembles the normalized instruction model consumed by the
// gas and llvm emitters.
package ir

import (
	"fmt"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/arch"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/encoding"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/format"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/loader"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/operand"
)

// Insn is one fully-parsed instruction.
type Insn struct {
	Mnemonic string
	Operands []operand.Operand
	Words    []encoding.Word
	Fields   []encoding.Field
	Arch     arch.Set
	Group    string
	Abstract string
	T        string
	Collides []string
}

// aliasMnemonic corrects known SH-reference-dataset spelling quirks so the
// emitted assembler uses the canonical mnemonic. "ldtbl" is the dataset's
// misspelling of LDTLB (opcode 0x0038). Mirrors decode/gen-go's aliasMnemonic.
var aliasMnemonic = map[string]string{"ldtbl": "ldtlb"}

func canonMnemonic(m string) string {
	return CanonMnemonic(m)
}

// CanonMnemonic applies the dataset alias map (exported for use by main).
func CanonMnemonic(m string) string {
	if a, ok := aliasMnemonic[m]; ok {
		return a
	}
	return m
}

// FieldFor returns the encoding field bound to a letter.
func (i Insn) FieldFor(letter byte) (encoding.Field, bool) {
	for _, f := range i.Fields {
		if f.Letter == letter {
			return f, true
		}
	}
	return encoding.Field{}, false
}

// Build converts raw insns into the IR, failing on any unmapped operand
// or unparsable encoding.
func Build(raw []loader.RawInsn) ([]Insn, error) {
	out := make([]Insn, 0, len(raw))
	for _, r := range raw {
		words, err := encoding.ParseCode(r.Code)
		if err != nil {
			return nil, fmt.Errorf("%q: %w", r.Format, err)
		}
		p := format.Parse(r.Format)
		ops := make([]operand.Operand, 0, len(p.Operands))
		fields := encoding.ParseFields(words)
		for _, tok := range p.Operands {
			o, err := operand.Classify(tok)
			if err != nil {
				return nil, fmt.Errorf("%q: %w", r.Format, err)
			}
			if o.Letter != 0 {
				w := 0
				for _, f := range fields {
					if f.Letter == o.Letter {
						w += f.Width
					}
				}
				o.Width = w
			}
			ops = append(ops, o)
		}
		out = append(out, Insn{
			Mnemonic: canonMnemonic(p.Mnemonic),
			Operands: ops,
			Words:    words,
			Fields:   fields,
			Arch: arch.Set{
				SH1: r.SH1, SH2: r.SH2, SH2E: r.SH2E, SH3: r.SH3, SH3E: r.SH3E,
				SH4: r.SH4, SH4A: r.SH4A, SH2A: r.SH2A, J1: r.J1, J2: r.J2, J4: r.J4,
			},
			Group:    r.Group,
			Abstract: r.Abstract,
			T:        r.T,
			Collides: r.Collides,
		})
	}
	return out, nil
}
