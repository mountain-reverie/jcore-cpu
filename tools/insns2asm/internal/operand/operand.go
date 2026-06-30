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
	BranchDisp
	BankReg
	MemTBRDisp
	FReg
	FR0Fixed
	DReg
	XReg
	FVReg
	CP0Reg
	CPIReg
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
	case BranchDisp:
		return "BranchDisp"
	case BankReg:
		return "BankReg"
	case MemTBRDisp:
		return "MemTBRDisp"
	case FReg:
		return "FReg"
	case FR0Fixed:
		return "FR0Fixed"
	case DReg:
		return "DReg"
	case XReg:
		return "XReg"
	case FVReg:
		return "FVReg"
	case CP0Reg:
		return "CP0Reg"
	case CPIReg:
		return "CPIReg"
	}
	return "??"
}

// Operand is a classified operand token.
type Operand struct {
	Token      string
	Class      Class
	Letter     byte   // primary encoding field letter, 0 if none
	BaseLetter byte   // base-register field letter for compound mem-disp, else 0
	Fixed      string // fixed register name when Class is FixedReg/R0Fixed
	Width      int    // bit width of the primary field (set by ir.Build)
}

type entry struct {
	class      Class
	letter     byte
	baseLetter byte
	fixed      string
}

// table maps the exact Phase-1 token vocabulary. Anything else is an error.
var table = map[string]entry{
	"Rn":            {class: GPR, letter: 'n'},
	"Rm":            {class: GPR, letter: 'm'},
	"R0":            {class: R0Fixed, fixed: "R0"},
	"#imm":          {class: Imm, letter: 'i'},
	"#imm3":         {class: Imm, letter: 'i'},
	"#imm20":        {class: Imm, letter: 'i'},
	"@Rm":           {class: MemReg, letter: 'm'},
	"@Rn":           {class: MemReg, letter: 'n'},
	"@Rm+":          {class: MemPostInc, letter: 'm'},
	"@Rn+":          {class: MemPostInc, letter: 'n'},
	"@R15+":         {class: MemPostInc, fixed: "R15"},
	"@-Rm":          {class: MemPreDec, letter: 'm'},
	"@-Rn":          {class: MemPreDec, letter: 'n'},
	"@-R15":         {class: MemPreDec, fixed: "R15"},
	"@(disp,Rm)":    {class: MemDisp, letter: 'd', baseLetter: 'm'},
	"@(disp,Rn)":    {class: MemDisp, letter: 'd', baseLetter: 'n'},
	"@(disp12,Rm)":  {class: MemDisp, letter: 'd', baseLetter: 'm'},
	"@(disp12,Rn)":  {class: MemDisp, letter: 'd', baseLetter: 'n'},
	"label":         {class: BranchDisp, letter: 'd'},
	"@@(disp8,TBR)": {class: MemTBRDisp, letter: 'd'},
	"Rm_BANK":       {class: BankReg, letter: 'm'},
	"Rn_BANK":       {class: BankReg, letter: 'n'},
	"SSR":           {class: FixedReg, fixed: "SSR"},
	"SPC":           {class: FixedReg, fixed: "SPC"},
	"DBR":           {class: FixedReg, fixed: "DBR"},
	"SGR":           {class: FixedReg, fixed: "SGR"},
	"TBR":           {class: FixedReg, fixed: "TBR"},
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
	"PTEH":          {class: FixedReg, fixed: "PTEH"},
	"PTEL":          {class: FixedReg, fixed: "PTEL"},
	"ASIDR":         {class: FixedReg, fixed: "ASIDR"},
	"TSBPTR":        {class: FixedReg, fixed: "TSBPTR"},
	"CP0_Rm":        {class: CP0Reg, letter: 'm'},
	"CP0_Rn":        {class: CP0Reg, letter: 'n'},
	"CPI_Rm":        {class: CPIReg, letter: 'm'},
	"CPI_Rn":        {class: CPIReg, letter: 'n'},
	"CP0_COM":       {class: FixedReg, fixed: "CP0_COM"},
	"CPI_COM":       {class: FixedReg, fixed: "CPI_COM"},
	"FRn":           {class: FReg, letter: 'n'},
	"FRm":           {class: FReg, letter: 'm'},
	"DRn":           {class: DReg, letter: 'n'},
	"DRm":           {class: DReg, letter: 'm'},
	"XDn":           {class: XReg, letter: 'n'},
	"XDm":           {class: XReg, letter: 'm'},
	"FR0":           {class: FR0Fixed, fixed: "FR0"},
	"FPUL":          {class: FixedReg, fixed: "FPUL"},
	"FPSCR":         {class: FixedReg, fixed: "FPSCR"},
	"FVn":           {class: FVReg, letter: 'n'},
	"FVm":           {class: FVReg, letter: 'm'},
	"XMTRX":         {class: FixedReg, fixed: "XMTRX"},
}

// Classify maps an operand token to its canonical Operand.
func Classify(token string) (Operand, error) {
	e, ok := table[token]
	if !ok {
		return Operand{}, fmt.Errorf("unmapped operand token %q", token)
	}
	return Operand{Token: token, Class: e.class, Letter: e.letter, BaseLetter: e.baseLetter, Fixed: e.fixed}, nil
}
