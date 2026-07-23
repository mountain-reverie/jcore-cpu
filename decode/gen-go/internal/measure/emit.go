package measure

import (
	"bytes"
	"fmt"
	"math"
	"sort"
)

// FormatCell formats a float64 value, rounding to the nearest integer.
// If variable is true, returns a string "n+"; otherwise returns an int.
func FormatCell(v float64, variable bool) interface{} {
	rounded := int(math.Round(v))
	if variable {
		return fmt.Sprintf("%d+", rounded)
	}
	return rounded
}

// cell wraps the output of FormatCell for TOML formatting.
// Returns the value as-is if it's a string (variable latency), or formats as int if it's an int.
func cell(v interface{}) string {
	switch val := v.(type) {
	case string:
		return fmt.Sprintf("%q", val)
	case int:
		return fmt.Sprintf("%d", val)
	default:
		return fmt.Sprint(val)
	}
}

// EmitTable produces deterministic TOML output for measured results.
// Results are sorted by opcode, and each entry contains issue, latency, and source fields.
// Variable-latency ops are formatted with the "n+" suffix.
func EmitTable(results []Result) string {
	// Sort by opcode to ensure deterministic output
	sorted := make([]Result, len(results))
	copy(sorted, results)
	sort.Slice(sorted, func(i, j int) bool {
		return sorted[i].Opcode < sorted[j].Opcode
	})

	var b bytes.Buffer
	for i, r := range sorted {
		fmt.Fprintf(&b, "[entries.%q]\n", r.Opcode)
		fmt.Fprintf(&b, "issue = %s\n", cell(FormatCell(r.Issue, r.Variable)))
		fmt.Fprintf(&b, "latency = %s\n", cell(FormatCell(r.Latency, r.Variable)))
		fmt.Fprintf(&b, "source = %q", r.Source)
		if i < len(sorted)-1 {
			fmt.Fprintf(&b, "\n\n")
		} else {
			fmt.Fprintf(&b, "\n")
		}
	}
	return b.String()
}
