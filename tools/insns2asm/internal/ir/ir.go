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
		for _, tok := range p.Operands {
			o, err := operand.Classify(tok)
			if err != nil {
				return nil, fmt.Errorf("%q: %w", r.Format, err)
			}
			ops = append(ops, o)
		}
		out = append(out, Insn{
			Mnemonic: p.Mnemonic,
			Operands: ops,
			Words:    words,
			Fields:   encoding.ParseFields(words),
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
