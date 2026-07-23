package measure

import "fmt"

type Result struct {
	Opcode   string
	Issue    float64
	Latency  float64
	Variable bool
	Source   string
}

// Marker scheme emitted by genbench (must stay in sync):
//   cal-A 0x11->0x12 (nopsA nops), cal-B 0x13->0x14 (nopsB nops),
//   independent chain 0x33->0x44 (issue), dependent chain 0x55->0x66 (latency).

// NSPerCycle derives ns-per-cycle from the TWO calibration brackets using the
// difference method (calB - calA), which cancels the fixed per-marker overhead.
// A single bracket would be overhead-contaminated (Task 1 spike Finding): e.g.
// 100 nops + 2-cycle marker overhead reads 10.2 ns/cyc instead of the true 10.0,
// a 2% error that shifts high-latency ops (divs 33 -> 32) by a whole cycle.
func NSPerCycle(m []Marker, nopsA, nopsB int) (float64, error) {
	if nopsB <= nopsA {
		return 0, fmt.Errorf("nopsB (%d) must exceed nopsA (%d)", nopsB, nopsA)
	}
	dA, err := cyclesRaw(m, 0x11, 0x12)
	if err != nil {
		return 0, err
	}
	dB, err := cyclesRaw(m, 0x13, 0x14)
	if err != nil {
		return 0, err
	}
	return (dB - dA) / float64(nopsB-nopsA), nil
}

// cyclesRaw returns the ns delta between two markers (nsPerCycle=1).
func cyclesRaw(m []Marker, from, to uint8) (float64, error) {
	return CyclesBetween(m, from, to, 1.0)
}

// Measure returns per-op issue (independent chain 0x33->0x44) and latency
// (dependent chain 0x55->0x66), subtracting the fixed marker overhead (in
// cycles) from each bracket before dividing by the op count.
func Measure(m []Marker, nsPerCycle float64, count, overheadCycles int) (issue, latency float64, err error) {
	if count <= 0 {
		return 0, 0, fmt.Errorf("count must be > 0")
	}
	ind, err := CyclesBetween(m, 0x33, 0x44, nsPerCycle)
	if err != nil {
		return 0, 0, err
	}
	dep, err := CyclesBetween(m, 0x55, 0x66, nsPerCycle)
	if err != nil {
		return 0, 0, err
	}
	oc := float64(overheadCycles)
	return (ind - oc) / float64(count), (dep - oc) / float64(count), nil
}

// CalibrationOK checks each known op's measured value is within tolerance.
// Anchor ONLY on trustworthy values (add/nop = 1) — never on the hand table's
// multi-cycle numbers, which Task 1 proved wrong (sim mul.l ~= 4, table says 2).
func CalibrationOK(known, measured map[string]float64, tol float64) error {
	for k, want := range known {
		got, ok := measured[k]
		if !ok {
			return fmt.Errorf("calibration op %q not measured", k)
		}
		if d := got - want; d > tol || d < -tol {
			return fmt.Errorf("calibration %q: measured %.2f want %.2f (tol %.1f)", k, got, want, tol)
		}
	}
	return nil
}
