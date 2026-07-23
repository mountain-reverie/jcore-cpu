package measure

import "testing"

func TestParseMarkersAndCycles(t *testing.T) {
	trace := `IF 0x001000 0x0009 nop
LED: WRITE 0x11 at 1000 ns
LED: WRITE 0x22 at 1200 ns
LED: WRITE 0x33 at 1300 ns
LED: WRITE 0x44 at 1900 ns
`
	m := ParseMarkers(trace)
	if len(m) != 4 { t.Fatalf("want 4 markers, got %d", len(m)) }
	// calibration: 0x11->0x22 is 100 nops over 200ns => 2 ns/cycle
	cal, err := CyclesBetween(m, 0x11, 0x22, 2.0)
	if err != nil || cal != 100 { t.Fatalf("cal cycles: %v %v", cal, err) }
	// payload 0x33->0x44 = 600ns / 2 = 300 cycles
	pay, _ := CyclesBetween(m, 0x33, 0x44, 2.0)
	if pay != 300 { t.Fatalf("payload cycles: %v", pay) }
}
