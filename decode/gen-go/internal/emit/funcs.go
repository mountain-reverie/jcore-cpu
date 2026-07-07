package emit

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
	"text/template"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
)

var funcMap = template.FuncMap{
	"hex16":          hex16,
	"formatString":   formatString,
	"registerArgs":   registerArgs,
	"vhdlEnumList":   vhdlEnumList,
	"join":           joinStr,
	"lastIdx":        lastIdx,
	"allEnums":       allEnums,
	"sub1":           sub1,
	"romTop":         romTop,
	"romLines":       romLines,
	"romConstBody":   romConstBody,
	"opcodeComment":  opcodeComment,
	"slotHex":        slotHex,
	"sortCondSigs":   sortCondSigs,
	"joinBits":       joinBits,
	"resetAggregate": resetAggregate,
}

// resetAggregate renders the comma-separated element list for a
// record's default-reset positional aggregate (e.g. the RHS of
// "ex_stall <= (...)" in decode_table_simple.vhd.tmpl), driven by
// model.Package instead of a hardcoded literal. It walks the named
// record's fields in declaration order and stops at the first field
// whose Default is empty (VHDL positional aggregates cannot skip a
// middle element, so a missing Default can only be reproduced as a
// truncation of the tuple — see RecordField.Default's doc comment).
func resetAggregate(pkg *model.Package, recordName string) (string, error) {
	for _, r := range pkg.Records {
		if r.Name != recordName {
			continue
		}
		var parts []string
		for _, f := range r.Fields {
			if f.Default == "" {
				break
			}
			for range f.Names {
				parts = append(parts, f.Default)
			}
		}
		return strings.Join(parts, ", "), nil
	}
	return "", fmt.Errorf("resetAggregate: record %q not found in Package.Records", recordName)
}

// hex16 formats a uint16 as a lowercase C hex literal with no leading
// zeros: 0x8, 0x300c, 0xffff. Matches Clojure (Integer/toString n 16).
func hex16(v uint16) string {
	return fmt.Sprintf("0x%x", v)
}

// opcodeComment converts an OpcodeHex string like "0x300C" or "0x8" into
// a 4-digit uppercase hex comment token like "300C" or "0008" (no "0x").
// Used in the decode_table_simple.vhd template to render "-- NAME [XXXX]".
func opcodeComment(opcodeHex string) string {
	// Strip leading "0x" or "0X".
	s := strings.TrimPrefix(opcodeHex, "0x")
	s = strings.TrimPrefix(s, "0X")
	// Pad to 4 digits.
	for len(s) < 4 {
		s = "0" + s
	}
	return strings.ToUpper(s)
}

// slotHex formats a slot index (0..15) as a single uppercase hex digit
// for use in VHDL case arms: when x"0", when x"A", etc.
func slotHex(idx int) string {
	return fmt.Sprintf("%X", idx)
}

// sortCondSigs returns a copy of sigs sorted alphabetically by name.
// Used by the decode_table_direct template to emit signal declarations
// in the same alphabetical order as the Clojure golden.
func sortCondSigs(sigs []model.CondSig) []model.CondSig {
	out := make([]model.CondSig, len(sigs))
	copy(out, sigs)
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// joinBits joins a slice of VHDL bit expressions with " & " to form
// the right-hand side of a condN concatenation assignment.
func joinBits(bits []string) string { return strings.Join(bits, " & ") }

var rnRmRE = regexp.MustCompile(`R[mn]`)

// formatString returns the snprintf format string for an instruction:
// the instruction name with every Rn/Rm replaced by R%hu.
func formatString(name, _ string) string {
	return rnRmRE.ReplaceAllString(name, "R%hu")
}

// registerArgs returns the comma-prefixed snprintf argument list for
// the register substitutions in the instruction. Returns "" when the
// format has no Rn/Rm. The order of arguments matches the order
// Rn/Rm appear in the instruction name (matching the Clojure
// re-seq behavior).
func registerArgs(in model.Instruction) string {
	rn := registerExpr(in.Format, "Rn")
	rm := registerExpr(in.Format, "Rm")

	// For extended instructions with format == "", the canonical format
	// fields are empty. Use the raw opcode string (e.g. "0010 nnnn mmmm 0011")
	// to identify which bit positions carry registers: "nnnn" at bits 11:8,
	// "mmmm" at bits 7:4.  Any occurrence of Rn in the instruction name maps
	// to the "nnnn" position and any Rm maps to the "mmmm" position, regardless
	// of which field is which absolute bit offset in this particular instruction.
	if rn == "" && rm == "" && in.Format == "" {
		vars := rnRmRE.FindAllString(in.Name, -1)
		if len(vars) == 0 {
			return ""
		}
		// Strip spaces so "0010 nnnn mmmm 0011" → "0010nnnnmmmm0011".
		opc := strings.ReplaceAll(in.OpcodeStr, " ", "")
		// Build per-token expressions from the opcode pattern.
		exprFor := map[string]string{}
		if strings.Contains(opc, "nnnn") {
			exprFor["Rn"] = "(instr >> 8) & 0xF"
		}
		if strings.Contains(opc, "mmmm") {
			// mmmm can appear at bits 11:8 (when nnnn is absent) or bits 7:4.
			if strings.Contains(opc, "nnnn") {
				exprFor["Rm"] = "(instr >> 4) & 0xF"
			} else {
				exprFor["Rm"] = "(instr >> 8) & 0xF"
			}
		}
		if len(exprFor) == 0 {
			return ""
		}
		var b strings.Builder
		for _, v := range vars {
			expr := exprFor[v]
			if expr == "" {
				expr = "0"
			}
			fmt.Fprintf(&b, ", (uint16_t)(%s)", expr)
		}
		return b.String()
	}

	if rn == "" && rm == "" {
		return ""
	}
	vars := rnRmRE.FindAllString(in.Name, -1)
	var b strings.Builder
	for _, v := range vars {
		var expr string
		switch v {
		case "Rn":
			expr = rn
		case "Rm":
			expr = rm
		}
		if expr == "" {
			expr = "0"
		}
		fmt.Fprintf(&b, ", (uint16_t)(%s)", expr)
	}
	return b.String()
}

// registerExpr returns the C expression that extracts the named
// register from the opcode, for the given format. Empty string if
// the format doesn't carry that register.
func registerExpr(format, reg string) string {
	switch format {
	case "n", "nd8", "ni":
		if reg == "Rn" {
			return "(instr >> 8) & 0xF"
		}
	case "m":
		if reg == "Rm" {
			return "(instr >> 8) & 0xF"
		}
	case "nm", "nmd":
		switch reg {
		case "Rn":
			return "(instr >> 8) & 0xF"
		case "Rm":
			return "(instr >> 4) & 0xF"
		}
	case "nd4":
		if reg == "Rn" {
			return "(instr >> 4) & 0xF"
		}
	case "md":
		if reg == "Rm" {
			return "(instr >> 4) & 0xF"
		}
	}
	return ""
}
