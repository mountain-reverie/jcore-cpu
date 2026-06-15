package emit

import (
	"bytes"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestPrivilegedFunctionEmitted(t *testing.T) {
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
	want := "function privileged (code : std_logic_vector(15 downto 0)) return std_logic is"
	if !strings.Contains(out, want) {
		t.Errorf("decode_body.vhd missing privileged() body; want substring %q", want)
	}
}
