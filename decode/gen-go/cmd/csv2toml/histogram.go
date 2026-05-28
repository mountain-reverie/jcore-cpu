package main

// columnHistogram counts, for each named column, the number of rows
// (across all groups) whose value is non-empty.
func columnHistogram(groups []InstructionGroup, columns []string) map[string]int {
	h := make(map[string]int, len(columns))
	for _, c := range columns {
		h[c] = 0
	}
	for _, g := range groups {
		for _, r := range g.Rows {
			for _, c := range columns {
				if r[c] != "" {
					h[c]++
				}
			}
		}
	}
	return h
}
