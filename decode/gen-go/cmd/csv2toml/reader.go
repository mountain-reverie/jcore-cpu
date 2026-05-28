package main

import (
	"encoding/csv"
	"fmt"
	"io"
	"strings"
)

// Row is one CSV data row, keyed by trimmed header name.
type Row map[string]string

// InstructionGroup is one logical instruction: a contiguous run of CSV rows
// sharing the same Instruction name. The first row carries TABLE, Format,
// State (slot count), and Op Code; subsequent rows in the same group may
// leave those columns blank.
type InstructionGroup struct {
	Name string // value of Instruction column on the first row
	Rows []Row
}

// readInstructionGroups parses the SH-2 instruction CSV and returns one
// group per instruction. Returns an error on malformed CSV or empty input.
func readInstructionGroups(r io.Reader) ([]InstructionGroup, error) {
	cr := csv.NewReader(r)
	cr.FieldsPerRecord = -1 // tolerate trailing-empty-cell variance
	records, err := cr.ReadAll()
	if err != nil {
		return nil, fmt.Errorf("read csv: %w", err)
	}
	if len(records) < 2 {
		return nil, fmt.Errorf("csv has no data rows")
	}
	header := make([]string, len(records[0]))
	for i, h := range records[0] {
		header[i] = strings.TrimSpace(h)
	}

	var groups []InstructionGroup
	for _, rec := range records[1:] {
		row := make(Row, len(header))
		for i, h := range header {
			if i < len(rec) {
				row[h] = strings.TrimSpace(rec[i])
			}
		}
		name := row["Instruction"]
		if name == "" {
			// continuation of the previous group, or a wholly empty row to skip
			if len(groups) == 0 {
				continue // skip leading empty rows
			}
			last := &groups[len(groups)-1]
			last.Rows = append(last.Rows, row)
			continue
		}
		// continuation if the previous group shares this name AND either
		// TABLE+State are blank (canonical multi-slot shape) or Op Code
		// matches (defensive: some spreadsheet rows redundantly re-state
		// TABLE/State on the second slot — same name + same opcode
		// unambiguously identifies the same instruction).
		if len(groups) > 0 && groups[len(groups)-1].Name == name {
			prev := groups[len(groups)-1].Rows[0]
			sameOpcode := prev["Op Code"] != "" && prev["Op Code"] == row["Op Code"]
			blankHeader := row["TABLE"] == "" && row["State"] == ""
			if blankHeader || sameOpcode {
				groups[len(groups)-1].Rows = append(groups[len(groups)-1].Rows, row)
				continue
			}
		}
		groups = append(groups, InstructionGroup{Name: name, Rows: []Row{row}})
	}
	return groups, nil
}

// readHeader returns the trimmed column names from the first CSV row.
func readHeader(r io.Reader) []string {
	cr := csv.NewReader(r)
	cr.FieldsPerRecord = -1
	rec, err := cr.Read()
	if err != nil {
		return nil
	}
	out := make([]string, len(rec))
	for i, h := range rec {
		out[i] = strings.TrimSpace(h)
	}
	return out
}
