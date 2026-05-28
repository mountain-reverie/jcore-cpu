package emit

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// runNormalizeAndDiff normalizes outDir and goldDir via NormalizeForDiff,
// then diffs the named file. If they differ, t.Errorf is called with the
// diff output. The normalized outputs land in <dir>.normalized/.
func runNormalizeAndDiff(t *testing.T, outDir, goldDir, filename string) {
	t.Helper()
	for _, dir := range []string{outDir, goldDir} {
		if err := NormalizeForDiff(dir, dir+".normalized"); err != nil {
			t.Fatalf("NormalizeForDiff %s: %v", dir, err)
		}
	}
	gotPath := outDir + ".normalized/" + filename
	wantPath := goldDir + ".normalized/" + filename

	got, err := os.ReadFile(gotPath)
	if err != nil {
		t.Fatalf("read normalized output %s: %v", gotPath, err)
	}
	want, err := os.ReadFile(wantPath)
	if err != nil {
		t.Fatalf("read normalized golden %s: %v", wantPath, err)
	}
	if string(got) == string(want) {
		return
	}
	// Write canonical copies for manual inspection.
	root := filepath.Dir(outDir)
	gotCanon := filepath.Join(root, "got_"+filename)
	wantCanon := filepath.Join(root, "want_"+filename)
	_ = os.WriteFile(gotCanon, got, 0o644)
	_ = os.WriteFile(wantCanon, want, 0o644)
	cmd := exec.Command("diff", "-u", wantCanon, gotCanon)
	out, _ := cmd.CombinedOutput()
	t.Errorf("normalized %s does not match golden:\n%s", filename, out)
}

// logBestEffortDiff normalizes outDir and goldDir via NormalizeForDiff,
// computes the diff line count for filename, and reports the size via
// t.Logf. Always passes — used by L1 best-effort gates where some drift
// is expected (per design §5). A growing diff count between runs signals a
// generator regression worth investigating, even when the gate itself never
// blocks the build.
func logBestEffortDiff(t *testing.T, outDir, goldDir, filename string) {
	t.Helper()
	for _, dir := range []string{outDir, goldDir} {
		if err := NormalizeForDiff(dir, dir+".normalized"); err != nil {
			t.Logf("NormalizeForDiff %s failed: %v (L1 diff measurement skipped)", dir, err)
			return
		}
	}
	gotPath := outDir + ".normalized/" + filename
	wantPath := goldDir + ".normalized/" + filename
	got, _ := os.ReadFile(gotPath)
	want, _ := os.ReadFile(wantPath)
	if len(got) == 0 || len(want) == 0 {
		t.Logf("%s: one of the normalized files is empty; skipping diff size", filename)
		return
	}
	if string(got) == string(want) {
		t.Logf("%s: L1 diff is empty — byte-identical to golden", filename)
		return
	}
	out, _ := exec.Command("diff", "-u", wantPath, gotPath).CombinedOutput()
	// Count lines starting with '+' or '-' but not the file header lines.
	added, removed := 0, 0
	for _, line := range strings.Split(string(out), "\n") {
		if strings.HasPrefix(line, "+++") || strings.HasPrefix(line, "---") {
			continue
		}
		if strings.HasPrefix(line, "+") {
			added++
		} else if strings.HasPrefix(line, "-") {
			removed++
		}
	}
	t.Logf("%s: L1 best-effort diff = %d added / %d removed (golden=%d lines, ours=%d lines)",
		filename, added, removed,
		strings.Count(string(want), "\n"), strings.Count(string(got), "\n"))
}
