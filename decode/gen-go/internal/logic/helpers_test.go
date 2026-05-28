package logic

import (
	"reflect"
	"testing"
)

// Note: OpToLogicMap, LogicMapToStdMatch, LogicMapToBoolExpr tests added at end.

func TestStrToLogicMap(t *testing.T) {
	// "01-" with sig="i" — LSB is rightmost. Bit 0 = '-' (skipped),
	// Bit 1 = '1' (set to 1), Bit 2 = '0' (set to 0).
	got := StrToLogicMap("i", "01-")
	want := LogicMap{
		SigBit{Sig: "i", Bit: 1}: 1,
		SigBit{Sig: "i", Bit: 2}: 0,
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v\nwant %v", got, want)
	}
}

func TestStrToLogicMapAllSet(t *testing.T) {
	got := StrToLogicMap("p", "1")
	want := LogicMap{SigBit{Sig: "p", Bit: 0}: 1}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v\nwant %v", got, want)
	}
}

func TestStrToLogicMapEmpty(t *testing.T) {
	got := StrToLogicMap("i", "----")
	if len(got) != 0 {
		t.Errorf("all-don't-care string should produce empty map, got %v", got)
	}
}

func TestOpToLogicMap(t *testing.T) {
	// Plane=0 (1 bit), opcode "0000 0000 0010 1011" (RTE).
	got := OpToLogicMap("0", "0000 0000 0010 1011")
	// p(0)=0, i(0)=1, i(1)=1, i(2)=0, i(3)=1, i(4)=0, i(5)=1, i(6..15)=0
	want := LogicMap{
		SigBit{"p", 0}: 0,
		SigBit{"i", 0}: 1,
		SigBit{"i", 1}: 1,
		SigBit{"i", 2}: 0,
		SigBit{"i", 3}: 1,
		SigBit{"i", 4}: 0,
		SigBit{"i", 5}: 1,
		SigBit{"i", 6}: 0, SigBit{"i", 7}: 0, SigBit{"i", 8}: 0,
		SigBit{"i", 9}: 0, SigBit{"i", 10}: 0, SigBit{"i", 11}: 0,
		SigBit{"i", 12}: 0, SigBit{"i", 13}: 0, SigBit{"i", 14}: 0,
		SigBit{"i", 15}: 0,
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("OpToLogicMap mismatch:\ngot  %v\nwant %v", got, want)
	}
}

func TestLogicMapToStdMatch(t *testing.T) {
	m := LogicMap{
		SigBit{"i", 0}: 0, SigBit{"i", 1}: 0,
		SigBit{"i", 4}: 1, SigBit{"i", 5}: 1,
	}
	// width 8, sig "i": bits 7,6,3,2 are unset (don't care), bits 5,4 are '1','1', bits 1,0 are '0','0'
	got := LogicMapToStdMatch(m, "i", 8)
	want := "--11--00"
	if got != want {
		t.Errorf("LogicMapToStdMatch: got %q, want %q", got, want)
	}
}

func TestLogicMapToBoolExpr(t *testing.T) {
	m := LogicMap{
		SigBit{"i", 5}: 1,
		SigBit{"i", 4}: 0,
		SigBit{"p", 0}: 0,
	}
	sigs := map[string]string{"i": "op.code", "p": "p"}
	got := LogicMapToBoolExpr(m, sigs)
	// The output ordering must be deterministic: sort by Sig then by Bit.
	want := `(not op.code(4) and op.code(5) and not p(0))`
	if got != want {
		t.Errorf("LogicMapToBoolExpr:\n  got  %q\n  want %q", got, want)
	}
}
