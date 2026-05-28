package spec

import (
	"strings"
	"testing"
)

func TestValidateRejectsUnknownField(t *testing.T) {
	s := &Spec{
		Instrs: []Instr{
			{Name: "X", Opcode: "0000 0000 0000 0000",
				Slots: []Slot{{"banana": "yes"}}},
		},
	}
	err := Validate(s)
	if err == nil || !strings.Contains(err.Error(), "banana") {
		t.Errorf("want error mentioning 'banana', got: %v", err)
	}
}

func TestValidateRejectsBadOpcode(t *testing.T) {
	s := &Spec{
		Instrs: []Instr{
			{Name: "X", Opcode: "totally not 16 bits", Slots: []Slot{{}}},
		},
	}
	if err := Validate(s); err == nil {
		t.Error("want error on bad opcode")
	}
}

func TestValidateRejectsMaOpWithoutSize(t *testing.T) {
	s := &Spec{
		Instrs: []Instr{
			{Name: "X", Opcode: "0000 0000 0000 0000",
				Slots: []Slot{{"ma_op": "READ"}}},
		},
	}
	err := Validate(s)
	if err == nil || !strings.Contains(err.Error(), "ma_size") {
		t.Errorf("want error mentioning ma_size, got: %v", err)
	}
}

func TestValidateRejectsDuplicateOpcode(t *testing.T) {
	s := &Spec{
		Instrs: []Instr{
			{Name: "X", Opcode: "0000 0000 0000 0001", Slots: []Slot{{}}},
			{Name: "Y", Opcode: "0000 0000 0000 0001", Slots: []Slot{{}}},
		},
	}
	err := Validate(s)
	if err == nil || !strings.Contains(err.Error(), "duplicate opcode") {
		t.Errorf("want duplicate-opcode error, got: %v", err)
	}
}

func TestValidateRejectsEmptySlotMidInstruction(t *testing.T) {
	s := &Spec{
		Instrs: []Instr{
			{Name: "X", Opcode: "0000 0000 0000 0010",
				Slots: []Slot{
					{"xbus": "Rn"},
					{}, // empty in the middle — must be rejected
					{"xbus": "Rm"},
				}},
		},
	}
	err := Validate(s)
	if err == nil || !strings.Contains(err.Error(), "empty slot not at end") {
		t.Errorf("want empty-slot-mid-instruction error, got: %v", err)
	}
}

func TestValidateAllowsTrailingEmptySlot(t *testing.T) {
	s := &Spec{
		Instrs: []Instr{
			{Name: "X", Opcode: "0000 0000 0000 0011",
				Slots: []Slot{
					{"xbus": "Rn"},
					{}, // trailing empty — implicit cycle terminator, allowed
				}},
		},
	}
	if err := Validate(s); err != nil {
		t.Errorf("trailing empty slot must be allowed, got: %v", err)
	}
}

func TestValidateAcceptsProductionSpec(t *testing.T) {
	s, err := Load("../../spec")
	if err != nil {
		t.Skipf("spec/ not present: %v", err)
	}
	if err := Validate(s); err != nil {
		t.Errorf("production spec failed validation: %v", err)
	}
}
