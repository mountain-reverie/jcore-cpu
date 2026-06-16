package emit

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestBigImmediateAllDecoders drives the constant-immediate path end-to-end
// across all three decoder backends. The testdata overlay overrides a
// system-plane instruction to use IMM_P256 (0x100) — the shape PM3's
// VBR+0x100 fixed-vector slot takes. Before the fix, this produces VHDL that
// fails to elaborate (direct emits a bare IMM_P256 enum into a
// std_logic_vector; simple references an undeclared enum literal; rom
// silently drops the value to x"00000000" via `others`).
//
// The assertions encode the required post-fix behavior:
//   - immval_t declares IMM_P256 (so simple's `imm_enum <= IMM_P256` is legal)
//   - the direct decoder emits the literal value x"00000100"
//   - the simple decoder's imm mux has an arm `x"00000100" when IMM_P256`
//   - the rom decoder's imm mux has an arm `x"00000100" when "<code>"`
//     (a concrete 5-bit code, not the `others` fallthrough)
func TestBigImmediateAllDecoders(t *testing.T) {
	s, err := spec.LoadProfile("../../spec", "testdata/bigimm")
	if err != nil {
		t.Fatalf("LoadProfile: %v", err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatalf("Validate: %v", err)
	}
	d, err := model.Build(s, 72)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	out := t.TempDir()
	if err := All(d, out); err != nil {
		t.Fatalf("emit.All: %v", err)
	}

	read := func(name string) string {
		b, err := os.ReadFile(filepath.Join(out, name))
		if err != nil {
			t.Fatalf("read %s: %v", name, err)
		}
		return string(b)
	}

	pkg := read("decode_pkg.vhd")
	if !strings.Contains(pkg, "IMM_P256") {
		t.Error("decode_pkg.vhd: immval_t does not declare IMM_P256 (simple decoder cannot name it)")
	}

	direct := read("decode_table_direct.vhd")
	if !strings.Contains(direct, `x"00000100"`) {
		t.Error(`decode_table_direct.vhd: missing literal x"00000100" for IMM_P256`)
	}
	if strings.Contains(direct, "IMM_P256") {
		t.Error("decode_table_direct.vhd: emits bare enum IMM_P256 into a std_logic_vector context (will not elaborate)")
	}

	simple := read("decode_table_simple.vhd")
	if !strings.Contains(simple, `x"00000100" when IMM_P256`) {
		t.Error(`decode_table_simple.vhd: imm mux missing arm x"00000100" when IMM_P256`)
	}

	rom := read("decode_table_rom.vhd")
	// The rom imm mux selects on a binary code, so the arm is
	// `x"00000100" when "<bits>",`. Assert the value is present as an
	// explicit `when "..."` arm — not silently mapped to `others`.
	if !strings.Contains(rom, `x"00000100" when "`) {
		t.Error(`decode_table_rom.vhd: imm mux missing explicit arm for x"00000100" (silently falls through to others => x"00000000")`)
	}
}
