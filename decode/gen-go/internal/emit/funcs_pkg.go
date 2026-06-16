package emit

import (
	"fmt"
	"reflect"
	"sort"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
)

// vhdlEnumList formats a slice of enum literal names as a
// parenthesized comma-separated list: "(IMM_ZERO, IMM_P1, ...)".
func vhdlEnumList(items []string) string {
	return "(" + strings.Join(items, ", ") + ")"
}

// joinStr joins a slice of strings with a separator. Exposed as "join"
// in the template funcMap.
func joinStr(items []string, sep string) string { return strings.Join(items, sep) }

// lastIdx returns the last valid index of a slice (len-1). Used in
// templates to detect whether the current loop index is the last.
// Works with any slice type via reflect.
func lastIdx(v interface{}) int {
	rv := reflect.ValueOf(v)
	if rv.Kind() != reflect.Slice {
		return -1
	}
	return rv.Len() - 1
}

// sub1 returns n-1. Used in templates to compute Hi bit index from TotalBits.
func sub1(n int) int { return n - 1 }

// romTop returns the top ROM index for a given address width: 2^addrBits - 1.
// Used in decode_table_rom.vhd for the "array (0 to romTop)" bound.
func romTop(addrBits int) int { return (1 << addrBits) - 1 }

// ROMLine is one logical line in the ROM constant body. Text is the
// pre-formatted VHDL text for one or more consecutive ROM entries
// belonging to the same instruction; the renderer indents each line
// with 4 spaces and adds a trailing newline. The final ROMLine carries
// the closing ");" as part of its Text.
//
// Examples:
//
//	0 => "00101...", -- CLRT
//	4 => "...", 5 => "...", 6 => "...", 7 => "...", -- RTE
//	254 => "000...000", 255 => "000...000");
type ROMLine struct {
	Text string
}

// romConstBody returns the full text of the VHDL ROM constant block, from
// "constant microcode_rom..." through the closing ");", ready to embed
// into the architecture body. Each line is 4-space indented. Lines end
// with \n.
func romConstBody(words []model.ROMWord) string {
	lines := romLines(words)
	if len(lines) == 0 {
		return "    constant microcode_rom : mem := ();\n"
	}
	var b strings.Builder
	fmt.Fprintf(&b, "    constant microcode_rom : mem := (%s\n", lines[0].Text)
	for _, rl := range lines[1:] {
		fmt.Fprintf(&b, "    %s\n", rl.Text)
	}
	return b.String()
}

// romLines converts the ROM word slice into logical lines for
// the ROM constant body. Each instruction's slots are collapsed onto one
// line with a trailing "-- InstrName" comment. Unused trailing entries
// (all-zero with no comment after the last instruction) are emitted as
// a final closing line containing ");".
//
// Rule: words[addr].Comment is set only on the last slot of an instruction.
// Consecutive words with empty Comment followed by one with a non-empty
// Comment form one group (the multi-slot instruction). Words with Comment=""
// that are not part of any group are trailing zeros.
func romLines(words []model.ROMWord) []ROMLine {
	var lines []ROMLine

	n := len(words)
	i := 0
	for i < n {
		start := i
		// Advance past intermediate slots (Comment == "").
		for i < n && words[i].Comment == "" {
			i++
		}
		if i < n {
			// words[i].Comment != "": this is the last slot of an instruction.
			// Group is [start..i].
			var b strings.Builder
			for j := start; j <= i; j++ {
				fmt.Fprintf(&b, "%d => \"%s\", ", j, words[j].Bits)
			}
			fmt.Fprintf(&b, "-- %s", words[i].Comment)
			lines = append(lines, ROMLine{Text: b.String()})
			i++
		} else {
			// Ran out of addressed words before finding a comment. This means
			// [start..n-1] are all trailing zeros. Emit as the closing line.
			var b strings.Builder
			for j := start; j < n; j++ {
				fmt.Fprintf(&b, "%d => \"%s\"", j, words[j].Bits)
				if j < n-1 {
					b.WriteString(", ")
				}
			}
			b.WriteString(");")
			lines = append(lines, ROMLine{Text: b.String()})
			return lines
		}
	}

	// All words consumed with instructions — highly unlikely but handle it:
	// close the last line (which currently ends with ", -- InstrName").
	// Rewrite the last entry's trailing comma to ");".
	if len(lines) > 0 {
		last := &lines[len(lines)-1]
		if idx := strings.LastIndex(last.Text, ", --"); idx >= 0 {
			last.Text = last.Text[:idx] + ");"
		}
	}
	return lines
}

// allEnums returns all enum types (StaticEnums + immval_t) sorted
// alphabetically by name. immval_t is the dynamic enum derived from
// ImmValLiterals. This produces the correct alphabetical interleaving
// as seen in the golden decode_pkg.vhd (immval_t appears between
// cpu_decode_type_t and instruction_plane_t).
func allEnums(pkg *model.Package) []model.EnumType {
	enums := make([]model.EnumType, len(pkg.StaticEnums)+1)
	copy(enums, pkg.StaticEnums)
	enums[len(pkg.StaticEnums)] = model.EnumType{
		Name:     "immval_t",
		Literals: pkg.ImmValLiterals,
	}
	sort.Slice(enums, func(i, j int) bool {
		return enums[i].Name < enums[j].Name
	})
	return enums
}
