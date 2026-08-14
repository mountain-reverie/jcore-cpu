package spec

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/BurntSushi/toml"
)

func TestSlotIllegalFieldParses(t *testing.T) {
	const src = `
[[instr]]
  name = "BT label"
  opcode = "1000 1001 dddd dddd"
  slot_illegal = true

[[instr]]
  name = "ADD Rm, Rn"
  opcode = "0011 nnnn mmmm 1100"
`
	var f struct {
		Instr []Instr `toml:"instr"`
	}
	if _, err := toml.Decode(src, &f); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(f.Instr) != 2 {
		t.Fatalf("want 2 instrs, got %d", len(f.Instr))
	}
	if !f.Instr[0].SlotIllegal {
		t.Errorf("%s: want SlotIllegal=true", f.Instr[0].Name)
	}
	if f.Instr[1].SlotIllegal {
		t.Errorf("%s: want SlotIllegal=false (default)", f.Instr[1].Name)
	}
}

// TestSlotIllegalSpecCoverage pins the ISA-mandated slot-illegal instructions
// that the derived wrpc_z rule in model.BuildBody cannot see on its own, so
// dropping a `slot_illegal = true` from the spec fails here rather than only
// in the sim/tests/slotillset.S cosim guard.
//
// The list is deliberately spelled out by name: these are exactly the two
// groups documented on spec.Instr.SlotIllegal. Instructions that DO assert
// wrpc_z (BRA/JMP/RTS/TRAPA/...) are intentionally absent — they need no flag.
func TestSlotIllegalSpecCoverage(t *testing.T) {
	s, err := Load("../../spec")
	if err != nil {
		t.Fatalf("load spec: %v", err)
	}
	// NOT listed here, deliberately: MOVA and MOV.{W,L} @(disp,PC),Rn. Those
	// raise a slot illegal instruction exception only on SH-3/SH-4 ("SH4*: if
	// this instruction is executed in a delay slot..."); on SH-1/SH-2 they are
	// LEGAL in a delay slot with defined semantics, and testrom/tests/
	// testmov2.s asserts exactly that for MOVA — trapping them on the base J2
	// build hangs the test ROM. They are patched in for J4 only; see
	// TestSlotIllegalJ4OverlayPatch below.
	want := map[string]bool{
		// Conditional branches: redirect via zbus="T(PC)", not wrpc_z.
		// Slot-illegal on SH-1/SH-2 as well, so these are unconditional.
		"BT label":    true,
		"BF label":    true,
		"BT /S label": true,
		"BF /S label": true,
	}
	got := map[string]bool{}
	for _, in := range s.Instrs {
		if in.SlotIllegal {
			got[in.Name] = true
		}
	}
	for name := range want {
		if !got[name] {
			t.Errorf("%q: missing slot_illegal = true in the spec", name)
		}
	}
	for name := range got {
		if !want[name] {
			t.Errorf("%q: unexpected slot_illegal = true; update this test if intended", name)
		}
	}
}

// TestSlotIllegalJ4OverlayPatch pins the variant SPLIT: the PC-relative
// operand fetches must be slot-illegal on the J4 profile (base + sh4 overlay)
// and NOT on the base J2 profile. Getting this backwards is not a subtle
// failure -- trapping them on J2 hangs the test ROM at testrom/tests/
// testmov2.s:27 -- so it is asserted in both directions here.
func TestSlotIllegalJ4OverlayPatch(t *testing.T) {
	pcRelative := []string{
		"MOVA @(disp, PC), R0",
		"MOV.W @(disp, PC), Rn",
		"MOV.L @(disp, PC), Rn",
	}

	flags := func(s *Spec) map[string]bool {
		m := map[string]bool{}
		for _, in := range s.Instrs {
			m[in.Name] = in.SlotIllegal
		}
		return m
	}

	base, err := Load("../../spec")
	if err != nil {
		t.Fatalf("load base spec: %v", err)
	}
	j4, err := LoadProfile("../../spec", "../../spec/sh4")
	if err != nil {
		t.Fatalf("load j4 profile: %v", err)
	}
	baseFlags, j4Flags := flags(base), flags(j4)

	for _, name := range pcRelative {
		if _, ok := baseFlags[name]; !ok {
			t.Fatalf("%q: not present in the base spec (renamed?)", name)
		}
		if baseFlags[name] {
			t.Errorf("%q: slot_illegal must be FALSE on base/J2 (SH-2 allows it "+
				"in a delay slot; testmov2.s depends on it)", name)
		}
		if !j4Flags[name] {
			t.Errorf("%q: slot_illegal must be TRUE on the J4 profile "+
				"(spec/sh4/mov.toml attribute patch)", name)
		}
	}

	// The overlay must PATCH, not replace: the base microcode has to survive.
	for _, name := range pcRelative {
		var baseSlots, j4Slots int
		for _, in := range base.Instrs {
			if in.Name == name {
				baseSlots = len(in.Slots)
			}
		}
		for _, in := range j4.Instrs {
			if in.Name == name {
				j4Slots = len(in.Slots)
			}
		}
		if baseSlots == 0 || j4Slots != baseSlots {
			t.Errorf("%q: overlay changed slot count %d -> %d; the patch must "+
				"leave microcode intact", name, baseSlots, j4Slots)
		}
	}
}

// TestAttributePatchUnknownNameErrors locks the typo guard: an attribute patch
// naming an instruction that does not exist must fail loudly rather than be
// silently dropped -- silent-drop is the exact failure class the slot_illegal
// work was fixing.
func TestAttributePatchUnknownNameErrors(t *testing.T) {
	dir := t.TempDir()
	overlay := filepath.Join(dir, "overlay")
	if err := os.MkdirAll(overlay, 0o755); err != nil {
		t.Fatal(err)
	}
	src := "[[instr]]\n  name = \"NO SUCH INSTRUCTION\"\n  patch = true\n  slot_illegal = true\n"
	if err := os.WriteFile(filepath.Join(overlay, "patch.toml"), []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadProfile("../../spec", overlay)
	if err == nil {
		t.Fatal("want an error for an attribute patch naming an unknown instruction")
	}
	if !strings.Contains(err.Error(), "NO SUCH INSTRUCTION") {
		t.Errorf("error should name the offending instruction, got: %v", err)
	}
}

// TestAttributePatchWithSlotsErrors: a patch that also declares microcode is
// ambiguous. Silently dropping the slots would hide a real edit, so LoadProfile
// must refuse it rather than pick one meaning.
func TestAttributePatchWithSlotsErrors(t *testing.T) {
	overlay := filepath.Join(t.TempDir(), "overlay")
	if err := os.MkdirAll(overlay, 0o755); err != nil {
		t.Fatal(err)
	}
	src := `
[[instr]]
  name = "MOVA @(disp, PC), R0"
  patch = true
  slot_illegal = true
  [[instr.slots]]
    pc = "INC"
`
	if err := os.WriteFile(filepath.Join(overlay, "patch.toml"), []byte(src), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := LoadProfile("../../spec", overlay)
	if err == nil {
		t.Fatal("want an error for a patch that declares slots")
	}
	if !strings.Contains(err.Error(), "drop `patch`") {
		t.Errorf("error should say how to fix it, got: %v", err)
	}
}
