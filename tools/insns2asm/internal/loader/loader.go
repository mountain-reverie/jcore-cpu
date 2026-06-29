// Package loader reads jcore docs/insns.json into RawInsn records,
// excluding the DSP family and non-emitted instruction groups.
package loader

import (
	"encoding/json"
	"io"
	"strings"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/format"
)

// RawInsn is one instruction as it appears in insns.json (Phase-1 subset).
type RawInsn struct {
	Group    string   `json:"group"`
	Format   string   `json:"format"`
	Code     string   `json:"code"`
	Abstract string   `json:"abstract"`
	T        string   `json:"T"`
	SH1      bool     `json:"SH1"`
	SH2      bool     `json:"SH2"`
	SH2E     bool     `json:"SH2E"`
	SH3      bool     `json:"SH3"`
	SH3E     bool     `json:"SH3E"`
	SH4      bool     `json:"SH4"`
	SH4A     bool     `json:"SH4A"`
	SH2A     bool     `json:"SH2A"`
	DSP      bool     `json:"DSP"`
	J1       bool     `json:"J1"`
	J2       bool     `json:"J2"`
	J4       bool     `json:"J4"`
	Collides []string `json:"collides"`
}

var emittedGroups = map[string]bool{
	"Data Transfer Instructions":        true,
	"Arithmetic Operation Instructions": true,
	"Logic Operation Instructions":      true,
	"Shift Instructions":                true,
	"Bit Manipulation Instructions":     true,
	"Branch Instructions":               true,
	"System Control Instructions":       true,
	// Single-precision FP (FPSCR.SZ=0 / FPSCR.PR=0) and FP control registers.
	"32 Bit Floating-Point Data Transfer Instructions (FPSCR.SZ = 0)":  true,
	"Floating-Point Single-Precision Instructions (FPSCR.PR = 0)":      true,
	"Floating-Point Control Instructions":                               true,
	// Double-precision FP (FPSCR.SZ=1 / FPSCR.PR=1).
	"64 Bit Floating-Point Data Transfer Instructions (FPSCR.SZ = 1)":  true,
	"Floating-Point Double-Precision Instructions (FPSCR.PR = 1)":      true,
}

// IsEmittedGroup reports whether group is emitted (Phase-1 GP-integer core plus
// Phase-2a Branch + System Control).
func IsEmittedGroup(group string) bool {
	return emittedGroups[group]
}

// deferredFPOperands was used to exclude vector/matrix FP tokens in earlier
// phases; all FP operands are now modelled so this map is empty.
var deferredFPOperands = map[string]bool{}

var dspCoprocOperands = map[string]bool{
	"A0": true, "X0": true, "X1": true, "Y0": true, "Y1": true,
	"RS": true, "RE": true, "MOD": true, "DSR": true,
	"CP0_COM": true, "CP0_Rm": true, "CP0_Rn": true,
	"CPI_COM": true, "CPI_Rm": true, "CPI_Rn": true,
	"Dx": true, "Dy": true, "Dz": true, "Da": true, "Dg": true, "Ds": true,
	"Se": true, "Sf": true, "Sx": true, "Sy": true,
}

// isDSPCoprocOperand reports whether a token names a DSP or coprocessor register.
func isDSPCoprocOperand(token string) bool {
	return dspCoprocOperands[token]
}

// Load decodes insns.json, keeping only emitted groups. Instructions in an
// emitted group whose operands reference a DSP/coproc register are excluded;
// the returned int is the count of such operand-excluded instructions.
func Load(r io.Reader) ([]RawInsn, int, error) {
	var doc struct {
		Instructions []RawInsn `json:"instructions"`
	}
	if err := json.NewDecoder(r).Decode(&doc); err != nil {
		return nil, 0, err
	}
	var out []RawInsn
	dropped := 0
	for _, in := range doc.Instructions {
		if strings.HasPrefix(in.Group, "DSP") {
			continue
		}
		if !IsEmittedGroup(in.Group) {
			continue
		}
		if hasDSPCoprocOperand(in.Format) {
			dropped++
			continue
		}
		if hasDeferredFPOperand(in.Format) {
			dropped++
			continue
		}
		out = append(out, in)
	}
	return out, dropped, nil
}

func hasDSPCoprocOperand(formatStr string) bool {
	for _, tok := range format.Parse(formatStr).Operands {
		if isDSPCoprocOperand(tok) {
			return true
		}
	}
	return false
}

func hasDeferredFPOperand(formatStr string) bool {
	for _, tok := range format.Parse(formatStr).Operands {
		if deferredFPOperands[tok] {
			return true
		}
	}
	return false
}
