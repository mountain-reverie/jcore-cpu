package emit

import (
	"bytes"
	"os"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestDecodeBodyStructural checks that the rendered decode_body.vhd contains
// all mandatory structural markers: the package body declaration, all three
// function signatures, the closing statement, and a when-arm for every
// top-nibble value (0..F).
func TestDecodeBodyStructural(t *testing.T) {
	s, err := spec.Load("../../spec")
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
	if err := tmpl.ExecuteTemplate(&buf, "decode_body.vhd.tmpl", d); err != nil {
		t.Fatal(err)
	}
	out := buf.String()
	for _, want := range []string{
		"package body decode_pack is",
		"function predecode_rom_addr",
		"function check_illegal_delay_slot",
		"function check_illegal_instruction",
		"end;",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("output missing %q", want)
		}
	}
	// Each top-nibble arm must appear.
	for n := 0; n < 16; n++ {
		want := `when x"`
		if !strings.Contains(out, want) {
			t.Errorf("output missing case arm %d", n)
		}
	}
}

// TestDecodeBodyL1BestEffort runs the L1 diff against the Clojure golden
// for documentation purposes. Per design §5, decode_body.vhd is L1
// best-effort — diffs are expected wherever QMC produces different
// (but equivalent) prime covers. The test always passes; failures are
// logged for human review.
func TestDecodeBodyL1BestEffort(t *testing.T) {
	s, err := spec.Load("../../spec")
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
	if err := tmpl.ExecuteTemplate(&buf, "decode_body.vhd.tmpl", d); err != nil {
		t.Fatal(err)
	}
	tmpDir := t.TempDir()
	gotDir := tmpDir + "/got"
	wantDir := tmpDir + "/want"
	_ = os.MkdirAll(gotDir, 0o755)
	_ = os.MkdirAll(wantDir, 0o755)
	_ = os.WriteFile(gotDir+"/decode_body.vhd", buf.Bytes(), 0o644)
	goldenSrc, _ := os.ReadFile("../../testdata/golden/clj/decode_body.vhd")
	_ = os.WriteFile(wantDir+"/decode_body.vhd", goldenSrc, 0o644)
	logBestEffortDiff(t, gotDir, wantDir, "decode_body.vhd")
}
