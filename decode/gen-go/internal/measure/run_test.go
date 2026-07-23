package measure

import (
	"os"
	"testing"
)

// TestPipelineOnFixtureTrace exercises ParseMarkers -> NSPerCycle -> Measure on
// a recorded 8-marker trace (2 calibration brackets + issue + latency
// brackets) standing in for a real cosim run, so the parse/compute glue can
// be verified without shelling out to cpu_ctb.
func TestPipelineOnFixtureTrace(t *testing.T) {
	b, err := os.ReadFile("testdata/add_trace_fixture.txt")
	if err != nil {
		t.Fatal(err)
	}
	trace := string(b)

	m := ParseMarkers(trace)
	if len(m) != 8 {
		t.Fatalf("want 8 markers, got %d", len(m))
	}

	ns, err := NSPerCycle(m, 100, 200)
	if err != nil {
		t.Fatal(err)
	}
	if ns != 10.0 {
		t.Fatalf("ns/cyc: got %v want 10", ns)
	}

	iss, lat, err := Measure(m, ns, 100, 2)
	if err != nil {
		t.Fatal(err)
	}
	if int(iss) != 1 || int(lat) != 1 {
		t.Fatalf("add from fixture: iss=%v lat=%v", iss, lat)
	}
}
