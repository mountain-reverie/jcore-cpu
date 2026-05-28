package emit

import (
	"bytes"
	"os"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestDecodeTableDirectStructural checks that the rendered
// decode_table_direct.vhd contains all mandatory structural markers:
// the architecture declaration, imp_bit_N signals, condN signals,
// the p signal, and that every output signal has an assignment.
func TestDecodeTableDirectStructural(t *testing.T) {
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
	if err := tmpl.ExecuteTemplate(&buf, "decode_table_direct.vhd.tmpl", d); err != nil {
		t.Fatal(err)
	}
	out := buf.String()

	for _, want := range []string{
		"architecture direct_logic of decode_table is",
		"signal mac_busy : mac_busy_t;",
		"signal p : std_logic_vector(0 downto 0);",
		"p <= \"0\" when op.plane = NORMAL_INSTR else \"1\";",
		"with mac_busy select",
		"not next_id_stall when EX_NOT_STALL,",
		"not next_id_stall when WB_NOT_STALL,",
		"end;",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("output missing %q", want)
		}
	}

	// Every imp_bit_N signal must appear in the declarations.
	for _, ib := range d.Direct.ImpBits {
		decl := "signal " + ib.Name + " : std_logic;"
		if !strings.Contains(out, decl) {
			t.Errorf("imp_bit signal declaration missing: %q", decl)
		}
		// And must appear in an assignment (extraction-threshold invariant: ≥2 uses).
		assign := ib.Name + " <= "
		if !strings.Contains(out, assign) {
			t.Errorf("imp_bit assignment missing: %q", assign)
		}
	}

	// Every condN signal must appear in the declarations.
	for _, cs := range d.Direct.CondSigs {
		decl := "signal " + cs.Name + " : std_logic_vector("
		if !strings.Contains(out, decl) {
			t.Errorf("condN signal declaration missing: %q", decl)
		}
		// And must appear in a with/select block.
		withSel := "with " + cs.Name + " select"
		if !strings.Contains(out, withSel) {
			t.Errorf("with/select for condN missing: %q", withSel)
		}
	}

	// Every output expression must appear somewhere in the output.
	for _, oe := range d.Direct.OutputExprs {
		lhsAssign := oe.LHS + " <="
		if !strings.Contains(out, lhsAssign) {
			t.Errorf("output expression LHS missing: %q", lhsAssign)
		}
	}

	// Structural invariant: imp_bit_N signals appear ≥2× in the output body
	// (extraction-threshold invariant). We only check a few well-known ones.
	if len(d.Direct.ImpBits) > 0 {
		ib0 := d.Direct.ImpBits[0].Name
		count := strings.Count(out, ib0)
		if count < 2 {
			t.Errorf("imp_bit %q appears only %d times in output (want ≥2)", ib0, count)
		}
	}
}

// TestDecodeTableDirectL1BestEffort runs the L1 diff against the Clojure
// golden for documentation purposes. Per design §5, decode_table_direct.vhd
// is L1 best-effort — diffs are expected. The test always passes; failures
// are logged for human review.
func TestDecodeTableDirectL1BestEffort(t *testing.T) {
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
	if err := tmpl.ExecuteTemplate(&buf, "decode_table_direct.vhd.tmpl", d); err != nil {
		t.Fatal(err)
	}
	tmpDir := t.TempDir()
	gotDir := tmpDir + "/got"
	wantDir := tmpDir + "/want"
	_ = os.MkdirAll(gotDir, 0o755)
	_ = os.MkdirAll(wantDir, 0o755)
	_ = os.WriteFile(gotDir+"/decode_table_direct.vhd", buf.Bytes(), 0o644)
	goldenSrc, _ := os.ReadFile("../../testdata/golden/clj/decode_table_direct.vhd")
	_ = os.WriteFile(wantDir+"/decode_table_direct.vhd", goldenSrc, 0o644)
	logBestEffortDiff(t, gotDir, wantDir, "decode_table_direct.vhd")
}
