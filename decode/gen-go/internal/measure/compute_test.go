package measure

import "testing"

func TestMeasureAndCalibration(t *testing.T) {
	// ns/cycle = 10. Marker overhead = 2 cycles (20ns) per bracket.
	// cal-A: 100 nops -> 100*10 + 20 = 1020ns delta.
	// cal-B: 200 nops -> 200*10 + 20 = 2020ns delta.
	// difference: (2020-1020)/100 = 10 ns/cyc (overhead cancels).
	// indep add issue=1: 100 ops -> 100*1*10 + 20 = 1020ns; (102-2)/100 = 1.
	// dep add latency=2: 100 ops -> 100*2*10 + 20 = 2020ns; (202-2)/100 = 2.
	m := []Marker{
		{0x11, 0}, {0x12, 1020}, // cal-A 100 nops
		{0x13, 2000}, {0x14, 4020}, // cal-B 200 nops
		{0x33, 5000}, {0x44, 6020}, // indep chain (issue)
		{0x55, 7000}, {0x66, 9020}, // dep chain (latency)
	}
	ns, err := NSPerCycle(m, 100, 200)
	if err != nil || ns != 10.0 {
		t.Fatalf("ns/cyc: got %v err %v (want 10)", ns, err)
	}
	iss, lat, err := Measure(m, ns, 100, 2)
	if err != nil || iss != 1 || lat != 2 {
		t.Fatalf("measure: iss=%v lat=%v err=%v (want 1,2)", iss, lat, err)
	}
	// NSPerCycle rejects a non-increasing nop pair.
	if _, err := NSPerCycle(m, 200, 100); err == nil {
		t.Fatal("NSPerCycle should reject nopsB <= nopsA")
	}
	// Measure rejects count <= 0.
	if _, _, err := Measure(m, ns, 0, 2); err == nil {
		t.Fatal("Measure should reject count <= 0")
	}
	// calibration gate: within tolerance passes; out fails.
	if err := CalibrationOK(map[string]float64{"add": 1}, map[string]float64{"add": 1.02}, 0.2); err != nil {
		t.Fatalf("should pass within tol: %v", err)
	}
	if err := CalibrationOK(map[string]float64{"add": 1}, map[string]float64{"add": 2.0}, 0.2); err == nil {
		t.Fatal("should fail out of tol")
	}
}
