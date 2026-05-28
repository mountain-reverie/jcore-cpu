package main

import (
	"os"
	"strings"
	"testing"
)

func TestReadGroupsConsecutiveSlots(t *testing.T) {
	input := `TABLE, Format,State,Instruction,Plane,Op Code,Operation,XBUS,YBUS,ALU X,ALU Y,ZBUS SEL,SR,ARITH,ARITH SR,CARRYIN EN,LOGIC,LOGIC SR,SHIFT,MANIP,ZBUS,WBUS,PC,IF ADDY,Latch S_MAC,PR,IF ISSUE,DISPATCH,DEBUG,MAC STAGE,MAC BUSY,MAC OP,MAC STALL SENSE,MACIN_1,MACIN_2,MACH,MACL,EVENT,HALT,DELAY JMP,ILEVEL CAPTURE,MA OP,MA MASK,MA SIZE,MA DATA,MA ADDY,MA LOCK,MASK INT,COPROC CMD,DATA MUX
A.23,0,1,CLRT,,0000 0000 0000 1000,0 -> T,,,,,,T=0,,,,,,,,,,INC,,,,,,,,,,,,,,,,,,,,,,,,,,,
A.23,0,4,RTE,,0000 0000 0010 1011,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
,,,RTE,,0000 0000 0010 1011,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
,,,RTE,,0000 0000 0010 1011,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
,,,RTE,,0000 0000 0010 1011,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,
`
	groups, err := readInstructionGroups(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(groups) != 2 {
		t.Fatalf("want 2 groups, got %d", len(groups))
	}
	if groups[0].Name != "CLRT" || len(groups[0].Rows) != 1 {
		t.Errorf("CLRT: name=%q rows=%d", groups[0].Name, len(groups[0].Rows))
	}
	if groups[1].Name != "RTE" || len(groups[1].Rows) != 4 {
		t.Errorf("RTE: name=%q rows=%d", groups[1].Name, len(groups[1].Rows))
	}
	if got := groups[1].Rows[0]["Op Code"]; got != "0000 0000 0010 1011" {
		t.Errorf("opcode=%q", got)
	}
}

// TestReadGroupsMergesSameOpcodeContinuation covers the LDS.L PR shape:
// two consecutive CSV rows for the same instruction, both with populated
// TABLE/State columns. The original grouping rule (blank-header → continuation)
// would have produced two separate groups with the same opcode.
func TestReadGroupsMergesSameOpcodeContinuation(t *testing.T) {
	input := `TABLE, Format,State,Instruction,Plane,Op Code,Operation,XBUS,YBUS
A.30,m,1,"LDS.L @Rm+, PR",,0100 mmmm 0010 0110,(Rm)?PR,Rm,
A.30,m,1,"LDS.L @Rm+, PR",,0100 mmmm 0010 0110,,Rm,
A.30,m,1,"LDS.L @Rm+, MACH",,0100 mmmm 0000 0110,,Rm,
`
	groups, err := readInstructionGroups(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if len(groups) != 2 {
		t.Fatalf("want 2 groups (LDS.L PR + LDS.L MACH), got %d", len(groups))
	}
	if groups[0].Name != "LDS.L @Rm+, PR" || len(groups[0].Rows) != 2 {
		t.Errorf("LDS.L PR: name=%q rows=%d (want 2)", groups[0].Name, len(groups[0].Rows))
	}
	if groups[1].Name != "LDS.L @Rm+, MACH" || len(groups[1].Rows) != 1 {
		t.Errorf("LDS.L MACH: name=%q rows=%d (want 1)", groups[1].Name, len(groups[1].Rows))
	}
}

func TestReadGroupsRealCSV(t *testing.T) {
	f, err := os.Open("../../../gen/SH-2 Instruction Set.csv")
	if err != nil {
		t.Skipf("CSV not available: %v", err)
	}
	defer f.Close()
	groups, err := readInstructionGroups(f)
	if err != nil {
		t.Fatal(err)
	}
	if len(groups) < 100 || len(groups) > 200 {
		t.Errorf("group count out of expected range [100,200]: %d", len(groups))
	}
}
