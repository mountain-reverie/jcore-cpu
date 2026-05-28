package emit

import (
	"bytes"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestDecodeStructural checks that the rendered decode.vhd contains all
// mandatory structural markers:
//   - header comment block
//   - library/use clauses
//   - entity declaration with port list matching the "decode" component
//   - architecture declaration
//   - both component instantiations (core, table)
//   - the pipeline process
//   - the output assignment block
func TestDecodeStructural(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	d, err := model.Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if d.Entity == nil {
		t.Fatal("d.Entity is nil — BuildEntity did not find the decode component")
	}
	tmpl, err := newTemplates()
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	if err := tmpl.ExecuteTemplate(&buf, "decode.vhd.tmpl", d); err != nil {
		t.Fatal(err)
	}
	out := buf.String()

	for _, want := range []string{
		// Header
		"This file is generated.",
		// Library/use clauses
		"library ieee;",
		"use work.decode_pack.all;",
		"use work.cpu2j0_pack.all;",
		// Entity declaration
		"entity decode is",
		"    port (",
		"    );",
		"end;",
		// Architecture
		"architecture arch of decode is",
		// Internal signals
		"signal debug_o : std_logic;",
		"signal pipeline_r : pipeline_t;",
		// Constants
		"constant STAGE_EX_RESET : pipeline_ex_t",
		"constant PIPELINE_RESET : pipeline_t",
		// Component instantiations
		"core : decode_core",
		"table : decode_table",
		// Port map wiring markers
		"p => pipeline_r,",
		"mac_s_latch => mac.s_latch,",
		// Pipeline process
		"process(ex, ex_stall, wb, wb_stall, next_id_stall, pipeline_r, slot)",
		"pipeline_c <= pipe;",
		// Clock process
		"process(clk, rst)",
		"pipeline_r <= PIPELINE_RESET;",
		// Output assignments
		"-- assign outputs",
		"-- assign combined outputs",
		"copreg <= op.code(11 downto 4);",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("output missing %q", want)
		}
	}

	// Every port in the decode component must appear in the entity port list.
	for _, p := range d.Entity.Ports {
		portLine := p.Name + " : " + p.Direction + " " + p.Type
		if !strings.Contains(out, portLine) {
			t.Errorf("entity port missing: %q", portLine)
		}
	}
}
