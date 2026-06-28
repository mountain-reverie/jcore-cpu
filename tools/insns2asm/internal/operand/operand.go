// Package operand maps Phase-1 assembler operand tokens to a canonical
// operand class and the encoding field letter each token binds.
package operand

import "fmt"

// Class is a canonical operand category.
type Class int

const (
	GPR Class = iota
	Imm
	Disp
	MemReg
	MemPostInc
	MemPreDec
	MemDisp
	MemR0
	MemPC
	MemGBR
	MemR0GBR
	FixedReg
	R0Fixed
)

func (c Class) String() string {
	switch c {
	case GPR:
		return "GPR"
	case Imm:
		return "Imm"
	case Disp:
		return "Disp"
	case MemReg:
		return "MemReg"
	case MemPostInc:
		return "MemPostInc"
	case MemPreDec:
		return "MemPreDec"
	case MemDisp:
		return "MemDisp"
	case MemR0:
		return "MemR0"
	case MemPC:
		return "MemPC"
	case MemGBR:
		return "MemGBR"
	case MemR0GBR:
		return "MemR0GBR"
	case FixedReg:
		return "FixedReg"
	case R0Fixed:
		return "R0Fixed"
	}
	return "??"
}

// Operand is a classified operand token.
type Operand struct {
	Token  string
	Class  Class
	Letter byte   // encoding field letter, 0 if none
	Fixed  string // fixed register name when Class is FixedReg/R0Fixed
}

type entry struct {
	class  Class
	letter byte
	fixed  string
}

// table maps the exact Phase-1 token vocabulary. Anything else is an error.
var table = map[string]entry{
	"Rn":            {class: GPR, letter: 'n'},
	"Rm":            {class: GPR, letter: 'm'},
	"R0":            {class: R0Fixed, fixed: "R0"},
	"#imm":          {class: Imm, letter: 'i'},
	"#imm20":        {class: Imm, letter: 'i'},
	"@Rm":           {class: MemReg, letter: 'm'},
	"@Rn":           {class: MemReg, letter: 'n'},
	"@Rm+":          {class: MemPostInc, letter: 'm'},
	"@Rn+":          {class: MemPostInc, letter: 'n'},
	"@R15+":         {class: MemPostInc, fixed: "R15"},
	"@-Rm":          {class: MemPreDec, letter: 'm'},
	"@-Rn":          {class: MemPreDec, letter: 'n'},
	"@-R15":         {class: MemPreDec, fixed: "R15"},
	"@(disp,Rm)":    {class: MemDisp, letter: 'd'},
	"@(disp,Rn)":    {class: MemDisp, letter: 'd'},
	"@(disp12,Rm)":  {class: MemDisp, letter: 'd'},
	"@(disp12,Rn)":  {class: MemDisp, letter: 'd'},
	"@R0":            {class: MemReg, fixed: "R0"},
	"@(R0,Rm)":      {class: MemR0, letter: 'm'},
	"@(R0,Rn)":      {class: MemR0, letter: 'n'},
	"@(R0,GBR)":     {class: MemR0GBR},
	"@(disp,PC)":    {class: MemPC, letter: 'd'},
	"@(disp,GBR)":   {class: MemGBR, letter: 'd'},
	"GBR":           {class: FixedReg, fixed: "GBR"},
	"VBR":           {class: FixedReg, fixed: "VBR"},
	"SR":            {class: FixedReg, fixed: "SR"},
	"MACH":          {class: FixedReg, fixed: "MACH"},
	"MACL":          {class: FixedReg, fixed: "MACL"},
	"PR":            {class: FixedReg, fixed: "PR"},
	"T":             {class: FixedReg, fixed: "T"},
}

// Classify maps an operand token to its canonical Operand.
func Classify(token string) (Operand, error) {
	e, ok := table[token]
	if !ok {
		return Operand{}, fmt.Errorf("unmapped operand token %q", token)
	}
	return Operand{Token: token, Class: e.class, Letter: e.letter, Fixed: e.fixed}, nil
}
