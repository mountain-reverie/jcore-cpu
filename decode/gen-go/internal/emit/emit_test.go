package emit

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

var updateGolden = flag.Bool("update", false, "rewrite golden files from current generator output")

// renderTemplateForFixture loads a TOML fixture (anchored to its own
// temp dir so spec.Load reads only it), builds the model, and renders
// the named template into a byte buffer.
func renderTemplateForFixture(t *testing.T, fixturePath, tmplName string) []byte {
	t.Helper()
	fixDir := t.TempDir()
	src, err := os.ReadFile(fixturePath)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(fixDir, filepath.Base(fixturePath)), src, 0o644); err != nil {
		t.Fatal(err)
	}
	s, err := spec.Load(fixDir)
	if err != nil {
		t.Fatal(err)
	}
	d, err := model.Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	tmpl, err := newTemplates()
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	if err := tmpl.ExecuteTemplate(&buf, tmplName, d); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func goldenCheck(t *testing.T, goldenPath string, got []byte) {
	t.Helper()
	if *updateGolden {
		if err := os.WriteFile(goldenPath, got, 0o644); err != nil {
			t.Fatal(err)
		}
		t.Logf("updated golden: %s", goldenPath)
		return
	}
	want, err := os.ReadFile(goldenPath)
	if err != nil {
		t.Fatalf("read golden %s: %v (run with -update to create)", goldenPath, err)
	}
	if !bytes.Equal(want, got) {
		t.Errorf("output does not match %s\n--- want ---\n%s\n--- got ---\n%s",
			goldenPath, want, got)
	}
}

func TestSh2instrTemplateMinimalFixture(t *testing.T) {
	got := renderTemplateForFixture(t,
		"../../testdata/fixtures/sh2instr/sh2instr_minimal.toml",
		"sh2instr.c.tmpl")
	goldenCheck(t, "../../testdata/fixtures/sh2instr/sh2instr_minimal.sh2instr.c.golden", got)
}
