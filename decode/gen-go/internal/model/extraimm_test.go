package model

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestExtraImmConstsEmptyForProduction pins the byte-identical contract: the
// production spec uses only immediates whose mux arms are hardcoded in the
// simple/rom templates, so no extra arms are generated.
func TestExtraImmConstsEmptyForProduction(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if len(d.ExtraImmConsts) != 0 {
		t.Errorf("production spec produced %d extra imm consts, want 0: %+v",
			len(d.ExtraImmConsts), d.ExtraImmConsts)
	}
}

// TestExtraImmConstsForBigImmediate verifies that an overlay introducing a
// large numeric immediate (IMM_P256, the shape of PM3's VBR+0x100 vector
// offset) produces exactly one extra const carrying the 32-bit value and a
// 5-bit rom code — the data the simple/rom templates need to emit a mux arm.
func TestExtraImmConstsForBigImmediate(t *testing.T) {
	over := t.TempDir()
	// Override a system instruction (already in csvInstrOrder) to use a
	// big immediate. System plane keeps it out of the disassembler ordering
	// constraints while still flowing through the encoding + immval_t set.
	mustWrite(t, filepath.Join(over, "bigimm.toml"), `
[[instr]]
  name = "General Illegal"
  opcode = "---- -111 dddd dddd"
  operation = ""
  plane = "system"

  [[instr.slots]]
    pc = "HOLD"
    arith = "ADD"
    xbus = "VBR"
    ybus = "256"
    zbus = "PC"
    zbus_sel = "ARITH"
`)
	s, err := spec.LoadProfile("../../spec", over)
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if len(d.ExtraImmConsts) != 1 {
		t.Fatalf("got %d extra imm consts, want 1: %+v", len(d.ExtraImmConsts), d.ExtraImmConsts)
	}
	ec := d.ExtraImmConsts[0]
	if ec.Literal != "IMM_P256" {
		t.Errorf("Literal = %q, want IMM_P256", ec.Literal)
	}
	if ec.VHDL != `x"00000100"` {
		t.Errorf("VHDL = %q, want x\"00000100\"", ec.VHDL)
	}
	if len(ec.RomCode) != romImmFieldBits {
		t.Errorf("RomCode = %q, want a %d-bit binary string", ec.RomCode, romImmFieldBits)
	}
	for _, c := range ec.RomCode {
		if c != '0' && c != '1' {
			t.Errorf("RomCode = %q is not a binary string", ec.RomCode)
			break
		}
	}
}

func mustWrite(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
