package main

import (
	"reflect"
	"testing"
)

func TestConvertCLRT(t *testing.T) {
	g := InstructionGroup{
		Name: "CLRT",
		Rows: []Row{{
			"TABLE": "A.23", "Format": "0", "State": "1",
			"Instruction": "CLRT",
			"Op Code":     "0000 0000 0000 1000",
			"Operation":   "0 -> T",
			"SR":          "T=0",
			"PC":          "INC",
		}},
	}
	got, err := convertGroup(g, map[string]bool{})
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "CLRT" || got.Format != "0" || got.Opcode != "0000 0000 0000 1000" {
		t.Errorf("header fields wrong: %+v", got)
	}
	if len(got.Slots) != 1 {
		t.Fatalf("want 1 slot, got %d", len(got.Slots))
	}
	wantSlot := map[string]string{"sr": "T=0", "pc": "INC"}
	if !reflect.DeepEqual(map[string]string(got.Slots[0]), wantSlot) {
		t.Errorf("slot=%v want=%v", got.Slots[0], wantSlot)
	}
}

func TestConvertMultiSlot(t *testing.T) {
	g := InstructionGroup{
		Name: "RTE",
		Rows: []Row{
			{"TABLE": "A.23", "Format": "0", "State": "4", "Instruction": "RTE",
				"Op Code": "0000 0000 0010 1011", "XBUS": "R15", "MA OP": "READ"},
			{"Instruction": "RTE", "Op Code": "0000 0000 0010 1011", "ZBUS": "PC"},
			{"Instruction": "RTE", "Op Code": "0000 0000 0010 1011", "ZBUS": "SR"},
			{"Instruction": "RTE", "Op Code": "0000 0000 0010 1011"},
		},
	}
	got, err := convertGroup(g, map[string]bool{})
	if err != nil {
		t.Fatal(err)
	}
	if len(got.Slots) != 4 {
		t.Fatalf("want 4 slots, got %d", len(got.Slots))
	}
	if got.Slots[0]["xbus"] != "R15" || got.Slots[0]["ma_op"] != "READ" {
		t.Errorf("slot 0 wrong: %v", got.Slots[0])
	}
	if got.Slots[3] == nil || len(got.Slots[3]) != 0 {
		t.Errorf("slot 3 should be empty map: %v", got.Slots[3])
	}
}

func TestConvertReadsPlane(t *testing.T) {
	g := InstructionGroup{
		Name: "Interrupt",
		Rows: []Row{{
			"Instruction": "Interrupt",
			"Plane":       "system",
			"Op Code":     "---- -000 dddd dddd",
			"Format":      "d8",
		}},
	}
	got, err := convertGroup(g, map[string]bool{})
	if err != nil {
		t.Fatal(err)
	}
	if got.Plane != "system" {
		t.Errorf("plane=%q, want %q", got.Plane, "system")
	}
}
