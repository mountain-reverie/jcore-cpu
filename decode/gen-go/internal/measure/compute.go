package measure

import "fmt"

type Result struct {
	Opcode   string
	Issue    float64
	Latency  float64
	Variable bool
	Source   string
}

func NSPerCycle(m []Marker, nops int) (float64, error) {
	c, err := cyclesRaw(m, 0x11, 0x22)
	if err != nil {
		return 0, err
	}
	if nops <= 0 {
		return 0, fmt.Errorf("nops must be > 0")
	}
	return c / float64(nops), nil
}

// cyclesRaw returns the ns delta between two markers (nsPerCycle=1).
func cyclesRaw(m []Marker, from, to uint8) (float64, error) {
	return CyclesBetween(m, from, to, 1.0)
}

func Measure(m []Marker, nsPerCycle float64, count int) (issue, latency float64, err error) {
	ind, err := CyclesBetween(m, 0x33, 0x44, nsPerCycle)
	if err != nil {
		return 0, 0, err
	}
	dep, err := CyclesBetween(m, 0x55, 0x66, nsPerCycle)
	if err != nil {
		return 0, 0, err
	}
	return ind / float64(count), dep / float64(count), nil
}

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
