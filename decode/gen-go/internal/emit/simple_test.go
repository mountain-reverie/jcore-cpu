package emit

import (
	"bytes"
	"os"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestDecodeTableSimpleStructural checks that the rendered
// decode_table_simple.vhd contains all mandatory structural markers:
// the architecture declaration, the imm_enum signal and mux, and a
// std_match clause for every kept instruction.
func TestDecodeTableSimpleStructural(t *testing.T) {
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
	if err := tmpl.ExecuteTemplate(&buf, "decode_table_simple.vhd.tmpl", d); err != nil {
		t.Fatal(err)
	}
	out := buf.String()
	for _, want := range []string{
		"architecture simple_logic of decode_table is",
		"signal imm_enum : immval_t;",
		"with imm_enum select",
		"std_match(cond, ",
		"end if;",
		"end;",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("output missing %q", want)
		}
	}
	// Every kept instruction must appear in a comment line "-- Name [XXXX]".
	for _, instr := range d.Simple.Instructions {
		if !strings.Contains(out, "-- "+instr.Name+" [") {
			t.Errorf("instruction %q not found in output", instr.Name)
		}
	}
}

// TestDecodeTableSimpleL1BestEffort runs the L1 diff against the Clojure
// golden for documentation purposes. Per design §5, decode_table_simple.vhd
// is L1 best-effort — diffs are expected (instruction order, inline comments,
// etc.). The test always passes; failures are logged for human review.
func TestDecodeTableSimpleL1BestEffort(t *testing.T) {
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
	if err := tmpl.ExecuteTemplate(&buf, "decode_table_simple.vhd.tmpl", d); err != nil {
		t.Fatal(err)
	}
	tmpDir := t.TempDir()
	gotDir := tmpDir + "/got"
	wantDir := tmpDir + "/want"
	_ = os.MkdirAll(gotDir, 0o755)
	_ = os.MkdirAll(wantDir, 0o755)
	_ = os.WriteFile(gotDir+"/decode_table_simple.vhd", buf.Bytes(), 0o644)
	goldenSrc, _ := os.ReadFile("../../testdata/golden/clj/decode_table_simple.vhd")
	_ = os.WriteFile(wantDir+"/decode_table_simple.vhd", goldenSrc, 0o644)
	logBestEffortDiff(t, gotDir, wantDir, "decode_table_simple.vhd")
}
