package measure

import "testing"

func TestMeasureAndCalibration(t *testing.T) {
	m := []Marker{
		{0x11, 0}, {0x22, 200},   // 100 nops -> 2 ns/cyc
		{0x33, 300}, {0x44, 500}, // indep: 200ns/100 = 2 cyc/2 = 1 issue
		{0x55, 600}, {0x66, 1000},// dep:   400ns/100 = 4 cyc/2 = 2 latency
	}
	ns, err := NSPerCycle(m, 100)
	if err != nil || ns != 2.0 { t.Fatalf("ns/cyc: %v %v", ns, err) }
	iss, lat, err := Measure(m, ns, 100)
	if err != nil || iss != 1 || lat != 2 {
		t.Fatalf("measure: iss=%v lat=%v err=%v", iss, lat, err)
	}
	// calibration gate: within tolerance passes; out fails
	if err := CalibrationOK(map[string]float64{"mul.l": 2}, map[string]float64{"mul.l": 2.3}, 1.0); err != nil {
		t.Fatalf("should pass within tol: %v", err)
	}
	if err := CalibrationOK(map[string]float64{"divs": 33}, map[string]float64{"divs": 20}, 1.0); err == nil {
		t.Fatal("should fail out of tol")
	}
}
