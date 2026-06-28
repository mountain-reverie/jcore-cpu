// Package loader reads jcore docs/insns.json into RawInsn records,
// excluding the DSP family and non-Phase-1 instruction groups.
package loader

import (
	"encoding/json"
	"io"
	"strings"
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

var phase1Groups = map[string]bool{
	"Data Transfer Instructions":       true,
	"Arithmetic Operation Instructions": true,
	"Logic Operation Instructions":     true,
	"Shift Instructions":               true,
	"Bit Manipulation Instructions":    true,
}

// IsPhase1Group reports whether group is in the Phase-1 GP-integer core.
func IsPhase1Group(group string) bool {
	return phase1Groups[group]
}

// Load decodes insns.json, keeping only Phase-1 groups (DSP excluded since
// no DSP group is a Phase-1 group).
func Load(r io.Reader) ([]RawInsn, error) {
	var doc struct {
		Instructions []RawInsn `json:"instructions"`
	}
	if err := json.NewDecoder(r).Decode(&doc); err != nil {
		return nil, err
	}
	var out []RawInsn
	for _, in := range doc.Instructions {
		if strings.HasPrefix(in.Group, "DSP") {
			continue
		}
		if !IsPhase1Group(in.Group) {
			continue
		}
		out = append(out, in)
	}
	return out, nil
}
