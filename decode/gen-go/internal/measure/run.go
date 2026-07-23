package measure

import (
	"fmt"
	"os/exec"
	"path/filepath"
)

// RunOne runs cosimBin (a J2/J2A/J4 cpu_ctb build) against the given .img,
// with LED write logging enabled, and returns the captured stdout trace text
// for ParseMarkers to consume. cosimBin is expected to be invoked from the
// sim/ directory (or with an equivalent working directory already set by the
// caller via exec.Cmd.Dir if needed) so relative paths like the .img resolve.
func RunOne(benchPath, cosimBin string) (string, error) {
	abs, err := filepath.Abs(cosimBin)
	if err != nil {
		return "", err
	}
	cmd := exec.Command(abs, "--stop-time=500us", "--log-ops", "-i", benchPath)
	// cpu_ctb reads its GHDL work library relative to its own directory
	// (e.g. sim/work-obj*.cf), so it must be invoked with cwd == the
	// directory the binary lives in, not the caller's cwd.
	cmd.Dir = filepath.Dir(abs)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("run %s -i %s: %w\n%s", cosimBin, benchPath, err, out)
	}
	return string(out), nil
}
