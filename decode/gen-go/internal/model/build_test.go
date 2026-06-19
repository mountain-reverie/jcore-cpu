package model

import (
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/logic"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestCsvInstrOrderNoOrphans asserts that every name in csvInstrOrder
// resolves to an actual instruction in the production spec. An entry
// that does not resolve indicates a stale name left behind after an
// instruction was removed from the spec — the ROM address layout would
// still be correct (Build skips nil lookups) but the orphan is dead
// weight that misleads future readers.
func TestCsvInstrOrderNoOrphans(t *testing.T) {
	// Load with the sh4 overlay: csvInstrOrder includes the SH-4 R*_BANK
	// instructions (used by `make generate-j4`), which live in spec/sh4.
	s, err := spec.LoadProfile("../../spec", "../../spec/sh4")
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

func TestDroppedOpcodeAddedToIllegalInstr(t *testing.T) {
	s := &spec.Spec{
		Instrs: []spec.Instr{
			{Name: "CLRT", Format: "0", Opcode: "0000 0000 0000 1000",
				Slots: []spec.Slot{{"sr": "T=0"}}},
		},
		Dropped: []spec.Instr{
			{Name: "CAS.L Rm, Rn, @R0", Opcode: "0010 nnnn mmmm 0011"},
		},
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(d.Body.IllegalInstr, `(code and x"f00f") = x"2003"`) {
		t.Fatalf("dropped CAS.L not OR-ed into IllegalInstr: %q", d.Body.IllegalInstr)
	}
	// The base illegal check must still be present.
	if !strings.Contains(d.Body.IllegalInstr, `x"ff"`) {
		t.Fatalf("base illegal check lost: %q", d.Body.IllegalInstr)
	}
}

func TestNoDropsLeavesIllegalInstrUnchanged(t *testing.T) {
	s := &spec.Spec{Instrs: []spec.Instr{
		{Name: "CLRT", Format: "0", Opcode: "0000 0000 0000 1000",
			Slots: []spec.Slot{{"sr": "T=0"}}},
	}}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(d.Body.IllegalInstr, " or ") {
		t.Fatalf("IllegalInstr gained terms without drops: %q", d.Body.IllegalInstr)
	}
}

// TestDropKeepsEncodingWidthEqualToBase asserts that dropping instructions
// (J1 profile) does not shrink ROM.TotalBits relative to the base ISA.
// The ROM template hardcodes bit-position selectors (e.g. "line(74 downto 73)")
// that must remain valid regardless of which instructions are dropped.
func TestDropKeepsEncodingWidthEqualToBase(t *testing.T) {
	sBase, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	dBase, err := Build(sBase, 72)
	if err != nil {
		t.Fatal(err)
	}

	// Load again for the J1 variant (ApplyDrops mutates the Spec).
	sJ1, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	prof, err := spec.ReadProfile("../../spec/profiles/j1.toml")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.ApplyDrops(sJ1, prof.Drop); err != nil {
		t.Fatal(err)
	}
	dJ1, err := Build(sJ1, 72)
	if err != nil {
		t.Fatal(err)
	}

	if dJ1.ROM.TotalBits != dBase.ROM.TotalBits {
		t.Errorf("J1 ROM.TotalBits = %d, want %d (same as base); dropping instructions must not shrink the encoding",
			dJ1.ROM.TotalBits, dBase.ROM.TotalBits)
	}

	// Verify dropped instructions are absent from Lines (disassembler).
	dropped := make(map[string]bool, len(sJ1.Dropped))
	for _, di := range sJ1.Dropped {
		dropped[di.Name] = true
	}
	for _, lg := range dJ1.Lines {
		for _, in := range lg.Instructions {
			if dropped[in.Name] {
				t.Errorf("dropped instruction %q still present in Lines", in.Name)
			}
		}
	}

	// Verify at least one dropped opcode is OR-ed into IllegalInstr.
	if !strings.Contains(dJ1.Body.IllegalInstr, `x"2003"`) {
		t.Errorf("CAS.L dropped opcode term not found in IllegalInstr: %q", dJ1.Body.IllegalInstr)
	}
}

// TestDropKeepsKeptMicrocodeIdentical guards the encoding-order invariant:
// dropping instructions must not change the microcode bits of any KEPT
// instruction. The encoding assigns field-value codes in first-encountered
// (csvInstrOrder) order, so the dropped slots must participate in that order,
// not be appended — otherwise a value first introduced by a dropped
// instruction gets a different code and corrupts kept instructions that use it.
func TestDropKeepsKeptMicrocodeIdentical(t *testing.T) {
	base, err := spec.Load(filepath.Join("..", "..", "spec"))
	if err != nil {
		t.Fatal(err)
	}
	db, err := Build(base, 72)
	if err != nil {
		t.Fatal(err)
	}
	j, err := spec.Load(filepath.Join("..", "..", "spec"))
	if err != nil {
		t.Fatal(err)
	}
	prof, err := spec.ReadProfile(filepath.Join("..", "..", "spec", "profiles", "j1.toml"))
	if err != nil {
		t.Skip("j1 profile not present")
	}
	if err := spec.ApplyDrops(j, prof.Drop); err != nil {
		t.Fatal(err)
	}
	dj, err := Build(j, 72)
	if err != nil {
		t.Fatal(err)
	}
	// Map instruction name -> microcode bits of its last slot (ROM Word.Comment).
	bitsByName := func(d *Decoder) map[string]string {
		m := map[string]string{}
		for _, w := range d.ROM.Words {
			if w.Comment != "" {
				m[w.Comment] = w.Bits
			}
		}
		return m
	}
	bb := bitsByName(db)
	jb := bitsByName(dj)
	bad := 0
	for name, jbits := range jb {
		if bbits, ok := bb[name]; ok && bbits != jbits {
			if bad < 8 {
				t.Errorf("kept instr %q microcode differs base vs j1", name)
			}
			bad++
		}
	}
	if bad > 0 {
		t.Errorf("total kept instructions with differing microcode: %d", bad)
	}
}

// TestDroppedOpcodeRoutedToIllegalPredecode guards the Stage-2 read-ahead
// safety fix: a dropped opcode's predecode must point at the General Illegal
// microcode, NOT at some populated kept-instruction entry (which the read-ahead
// would execute one cycle early, before the illegal squash, causing a bus
// error instead of a clean trap).
func TestDroppedOpcodeRoutedToIllegalPredecode(t *testing.T) {
	j, err := spec.Load(filepath.Join("..", "..", "spec"))
	if err != nil {
		t.Fatal(err)
	}
	prof, err := spec.ReadProfile(filepath.Join("..", "..", "spec", "profiles", "j1.toml"))
	if err != nil {
		t.Skip("j1 profile not present")
	}
	if err := spec.ApplyDrops(j, prof.Drop); err != nil {
		t.Fatal(err)
	}
	d, err := Build(j, 72)
	if err != nil {
		t.Fatal(err)
	}
	// General Illegal first-slot ROM address = the predecode target for any
	// dropped opcode. Evaluate predecode for CAS.L (0x2983) and confirm it lands
	// on a ROM entry that is NOT a normal kept instruction.
	pa := func(op int) int {
		arm := &d.Body.Predecode.Arms[(op>>12)&0xf]
		if arm.LiteralAddr != "" {
			h := strings.TrimSuffix(strings.TrimPrefix(arm.LiteralAddr, `x"`), `"`)
			v, _ := strconv.ParseInt(h, 16, 0)
			return int(v)
		}
		r := logic.SigValue(func(s string, b int) int { return (op >> b) & 1 })
		a := 0
		for _, x := range arm.BitAssigns {
			if v, _ := logic.EvalBoolExpr(x.Expr, r); v {
				a |= 1 << x.Bit
			}
		}
		return a
	}
	for _, op := range []int{0x2983, 0x4088, 0x4288} {
		comment := d.ROM.Words[pa(op)].Comment
		// Must NOT land on a normal data-moving instruction like XTRACT/MOV.
		if comment != "" && comment != "General Illegal" {
			t.Errorf("dropped opcode %#x predecodes to %q ROM entry (addr %d); expected the General Illegal microcode", op, comment, pa(op))
		}
	}
}
