package main

import "testing"

func TestColumnHistogram(t *testing.T) {
	groups := []InstructionGroup{
		{Name: "A", Rows: []Row{{"XBUS": "Rn", "YBUS": ""}}},
		{Name: "B", Rows: []Row{{"XBUS": "Rm", "YBUS": ""}, {"XBUS": "", "YBUS": ""}}},
	}
	h := columnHistogram(groups, []string{"XBUS", "YBUS"})
	if h["XBUS"] != 2 {
		t.Errorf("XBUS: want 2, got %d", h["XBUS"])
	}
	if h["YBUS"] != 0 {
		t.Errorf("YBUS: want 0, got %d", h["YBUS"])
	}
}
