package emit

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestDecodePkgAgainstClojureGolden(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}
	d, err := model.Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	// No stubs: Build computes DecCoreROMResetAddr and SystemInstrROMAddrs
	// from real ROM layout. This test is the gate for both decode_pkg.vhd
	// template rendering AND the build-side ROM-address computation.

	tmpl, err := newTemplates()
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	if err := tmpl.ExecuteTemplate(&buf, "decode_pkg.vhd.tmpl", d); err != nil {
		t.Fatal(err)
	}

	// L1 required-exact, post-normalization.
	tmpDir := t.TempDir()
	outDir := filepath.Join(tmpDir, "out")
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(outDir, "decode_pkg.vhd"), buf.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	goldDir := filepath.Join(tmpDir, "gold")
	if err := os.MkdirAll(goldDir, 0o755); err != nil {
		t.Fatal(err)
	}
	src, err := os.ReadFile("../../testdata/golden/clj/decode_pkg.vhd")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(goldDir, "decode_pkg.vhd"), src, 0o644); err != nil {
		t.Fatal(err)
	}

	// Reuse the normalize script and diff exactly (L1 required-exact).
	runNormalizeAndDiff(t, outDir, goldDir, "decode_pkg.vhd")
}
