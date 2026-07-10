package model

import (
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestCsvInstrOrderNoOrphans asserts that every name in csvInstrOrder
// resolves to an actual instruction in the production spec. An entry
// that does not resolve indicates a stale name left behind after an
// instruction was removed from the spec — the ROM address layout would
// still be correct (Build skips nil lookups) but the orphan is dead
// weight that misleads future readers.
func TestCsvInstrOrderNoOrphans(t *testing.T) {
	// Load with every overlay: csvInstrOrder includes both the SH-4
	// R*_BANK instructions (used by `make generate-j4`, in spec/sh4) and
	// the SH-2A two-word instructions (used by `make generate-j2a`, in
	// spec/sh2a).
	s, err := spec.LoadProfile("../../spec", "../../spec/sh4", "../../spec/sh2a")
	if err != nil {
		t.Fatal(err)
	}
	instrByName := make(map[string]bool, len(s.Instrs))
	for _, si := range s.Instrs {
		instrByName[si.Name] = true
	}
	for _, name := range csvInstrOrder {
		if !instrByName[name] {
			t.Errorf("csvInstrOrder entry %q has no matching instruction in the spec (orphaned name)", name)
		}
	}
}

func TestBuildFiltersSystemPlane(t *testing.T) {
	s := &spec.Spec{Instrs: []spec.Instr{
		{Name: "CLRT", Format: "0", Opcode: "0000 0000 0000 1000"},
		{Name: "Interrupt", Format: "d8", Opcode: "---- -000 dddd dddd", Plane: "system"},
	}}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, lg := range d.Lines {
		for _, in := range lg.Instructions {
			got = append(got, in.Name)
		}
	}
	if len(got) != 1 || got[0] != "CLRT" {
		t.Errorf("want [CLRT], got %v", got)
	}
}

func TestBuildNormalizesFormatMNToNM(t *testing.T) {
	s := &spec.Spec{Instrs: []spec.Instr{
		{Name: "ADD Rm, Rn", Format: "mn", Opcode: "0011 nnnn mmmm 1100"},
	}}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	got := d.Lines[3].Instructions[0].Format
	if got != "nm" {
		t.Errorf("format=%q, want %q", got, "nm")
	}
}

func TestBuildGroupsByTopNibbleAndSorts(t *testing.T) {
	s := &spec.Spec{Instrs: []spec.Instr{
		{Name: "A", Format: "n", Opcode: "0011 0000 0000 0010"},
		{Name: "B", Format: "n", Opcode: "0011 0000 0000 0001"},
		{Name: "C", Format: "n", Opcode: "0001 0000 0000 0000"},
	}}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if len(d.Lines[3].Instructions) != 2 {
		t.Fatalf("line 3: want 2 instrs, got %d", len(d.Lines[3].Instructions))
	}
	if d.Lines[3].Instructions[0].Name != "B" {
		t.Errorf("sorted order wrong: %v", d.Lines[3].Instructions)
	}
	if len(d.Lines[1].Instructions) != 1 {
		t.Fatalf("line 1: want 1 instr, got %d", len(d.Lines[1].Instructions))
	}
}

func TestBuildReturnsErrorOnBadOpcode(t *testing.T) {
	s := &spec.Spec{Instrs: []spec.Instr{
		{Name: "BAD", Format: "0", Opcode: "totally not 16 bits"},
	}}
	if _, err := Build(s, 72); err == nil {
		t.Error("want error on malformed opcode")
	}
}

func TestBuildProductionSpec(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	total := 0
	for _, lg := range d.Lines {
		total += len(lg.Instructions)
	}
	// Production spec has 160 instructions; 6 carry Plane="system".
	// Build keeps 154.
	if total != 154 {
		t.Errorf("Build emitted %d instructions, want 154", total)
	}
}

func TestBuildProductionImmVals(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if d.Package == nil {
		t.Fatal("Build returned nil Package")
	}
	// Golden file decode_pkg.vhd line 21 has exactly 19 immval_t literals.
	const wantCount = 19
	got := d.Package.ImmValLiterals
	if len(got) != wantCount {
		t.Errorf("ImmValLiterals: got %d literals, want %d: %v", len(got), wantCount, got)
	}
	// Verify the exact order matches the golden file:
	// IMM_ZERO IMM_P1 IMM_P2 IMM_P4 IMM_P8 IMM_P16
	// IMM_N16 IMM_N8 IMM_N2 IMM_N1
	// IMM_U_4_0 IMM_U_4_1 IMM_U_4_2 IMM_U_8_0 IMM_U_8_1 IMM_U_8_2
	// IMM_S_8_1 IMM_S_12_1 IMM_S_8_0
	want := []string{
		"IMM_ZERO", "IMM_P1", "IMM_P2", "IMM_P4", "IMM_P8", "IMM_P16",
		"IMM_N16", "IMM_N8", "IMM_N2", "IMM_N1",
		"IMM_U_4_0", "IMM_U_4_1", "IMM_U_4_2",
		"IMM_U_8_0", "IMM_U_8_1", "IMM_U_8_2",
		"IMM_S_8_1", "IMM_S_12_1", "IMM_S_8_0",
	}
	for i := range want {
		if i >= len(got) {
			break
		}
		if got[i] != want[i] {
			t.Errorf("ImmValLiterals[%d]: got %q, want %q", i, got[i], want[i])
		}
	}
}

// idFieldNames returns the flattened field names of pipeline_id_t in
// pkg.Records, or nil if the record isn't present.
func idFieldNames(pkg *Package) []string {
	for _, r := range pkg.Records {
		if r.Name != "pipeline_id_t" {
			continue
		}
		var names []string
		for _, f := range r.Fields {
			names = append(names, f.Names...)
		}
		return names
	}
	return nil
}

func hasName(names []string, want string) bool {
	for _, n := range names {
		if n == want {
			return true
		}
	}
	return false
}

// TestBaseBuildHasNoLatchExtFields proves latch_ext/imm_from_ext are
// variant-additive: the base (no-overlay) build's pipeline_id_t must
// NOT gain these fields, even though the microcode.Signal machinery
// (IsStdLogic/SignalVHDLPath) knows about them — nothing in the base
// spec's AssignMaps sets them, so internal/model/build.go's
// usesLatchExt/usesImmFromExt scan must find nothing and leave
// pipeline_id_t at its historical 3 fields.
func TestBaseBuildHasNoLatchExtFields(t *testing.T) {
	s, err := spec.LoadProfile("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	names := idFieldNames(d.Package)
	if hasName(names, "latch_ext") || hasName(names, "imm_from_ext") {
		t.Errorf("base build's pipeline_id_t unexpectedly has latch_ext/imm_from_ext: %v", names)
	}
}

// TestJ2AOverlayAddsLatchExtFieldsAndSeedSlot0 proves the other half of
// the variant-additive contract: loading the sh2a overlay (which
// contributes the two-word "MOV.L @(disp12,Rm),Rn" seed instruction,
// whose slot0 sets latch_ext="1") must (a) widen pipeline_id_t with
// both new fields and (b) actually emit slot0's id.latch_ext <= '1'
// assignment for that instruction in the Simple decoder view.
func TestJ2AOverlayAddsLatchExtFieldsAndSeedSlot0(t *testing.T) {
	s, err := spec.LoadProfile("../../spec", "../../spec/sh2a")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	names := idFieldNames(d.Package)
	if !hasName(names, "latch_ext") || !hasName(names, "imm_from_ext") {
		t.Fatalf("J2A build's pipeline_id_t missing latch_ext/imm_from_ext: %v", names)
	}
	var seed *SimpleInstr
	for i := range d.Simple.Instructions {
		instr := &d.Simple.Instructions[i]
		// This word1 ("0011 nnnn mmmm 0001") also carries the SH-2A store
		// counterpart "MOV.L Rm,@(disp12,Rn)", so BuildSimple merges the
		// two into one arm (see mergeSimpleGroup); the load's name shows
		// up in GroupNames rather than Name once merged.
		if instr.Name == "MOV.L @(disp12,Rm),Rn" || hasName(instr.GroupNames, "MOV.L @(disp12,Rm),Rn") {
			seed = instr
		}
	}
	if seed == nil {
		t.Fatal("seed instruction MOV.L @(disp12,Rm),Rn not found in J2A Simple.Instructions")
	}
	if len(seed.Slots) == 0 {
		t.Fatal("seed instruction has no slots")
	}
	slot0 := seed.Slots[0]
	found := false
	for _, a := range slot0.Assignments {
		if a.LHS == "id.latch_ext" && a.RHS == "'1'" {
			found = true
		}
	}
	if !found {
		t.Errorf("seed slot0 assignments do not set id.latch_ext <= '1': %+v", slot0.Assignments)
	}
}

// componentHasPort reports whether the named component in pkg has a port
// with the given name.
func componentHasPort(pkg *Package, component, port string) bool {
	for _, c := range pkg.Components {
		if c.Name != component {
			continue
		}
		for _, p := range c.Ports {
			if p.Name == port {
				return true
			}
		}
	}
	return false
}

// TestBaseBuildHasNoExtWordPorts proves the ext_word_o/ext_word component
// ports wired between decode_core and decode_table (Task 1.3 increment B)
// are variant-additive: the base (no-overlay) build must NOT gain them, and
// Decoder.HasTwoWord (which gates the decode.vhd.tmpl signal/port-map
// wiring) must be false.
func TestBaseBuildHasNoExtWordPorts(t *testing.T) {
	s, err := spec.LoadProfile("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if d.HasTwoWord {
		t.Error("base build unexpectedly has HasTwoWord=true")
	}
	if componentHasPort(d.Package, "decode_core", "ext_word_o") {
		t.Error("base build's decode_core component unexpectedly has ext_word_o port")
	}
	if componentHasPort(d.Package, "decode_table", "ext_word") {
		t.Error("base build's decode_table component unexpectedly has ext_word port")
	}
}

// TestJ2AOverlayAddsExtWordPorts proves the other half: loading the sh2a
// overlay must (a) set Decoder.HasTwoWord and (b) add ext_word_o to
// decode_core and ext_word to decode_table's component port lists, so
// decode.vhd.tmpl's {{ if .HasTwoWord }}-guarded port maps resolve.
func TestJ2AOverlayAddsExtWordPorts(t *testing.T) {
	s, err := spec.LoadProfile("../../spec", "../../spec/sh2a")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if !d.HasTwoWord {
		t.Error("J2A build's Decoder.HasTwoWord is false, want true")
	}
	if !componentHasPort(d.Package, "decode_core", "ext_word_o") {
		t.Error("J2A build's decode_core component missing ext_word_o port")
	}
	if !componentHasPort(d.Package, "decode_table", "ext_word") {
		t.Error("J2A build's decode_table component missing ext_word port")
	}
}
