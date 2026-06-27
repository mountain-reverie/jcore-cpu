package insns

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestSyncPatchesAndAppends(t *testing.T) {
	d, err := Load(filepath.Join("testdata", "in.json"))
	if err != nil {
		t.Fatal(err)
	}
	mov := spec.Instr{Name: "MOV", Opcode: "0110nnnnmmmm0011", Slots: []spec.Slot{{}}}
	ldtlbr := spec.Instr{Name: "LDTLB.RN", Opcode: "0000000001101000", Format: "ldtlb.rn", Slots: []spec.Slot{{}}}
	j2 := &InstrSet{ByKey: map[Key]spec.Instr{}}
	for _, in := range []spec.Instr{mov} {
		k, _ := KeyOf(in.Opcode)
		j2.ByKey[k] = in
		j2.Order = append(j2.Order, in)
	}
	j4 := &InstrSet{ByKey: map[Key]spec.Instr{}}
	for _, in := range []spec.Instr{mov, ldtlbr} {
		k, _ := KeyOf(in.Opcode)
		j4.ByKey[k] = in
		j4.Order = append(j4.Order, in)
	}
	tab := &Table{}
	rep, err := Sync(d, []VariantData{
		{Variant{Name: "J2"}, j2, tab},
		{Variant{Name: "J4", Group: "System Control Instructions"}, j4, tab},
	})
	if err != nil {
		t.Fatal(err)
	}
	out, _ := d.Bytes()
	want, _ := os.ReadFile(filepath.Join("testdata", "expected.json"))
	if string(out) != string(want) {
		t.Fatalf("mismatch:\n--- got ---\n%s\n--- want ---\n%s", out, want)
	}
	if len(rep.Appended) != 1 {
		t.Fatalf("expected 1 appended, got %v", rep.Appended)
	}
}

func TestSyncSurfacesEncodingCollision(t *testing.T) {
	// A lone SH-reference row (NOTT) occupies 0x0068; J4 reuses that encoding for
	// a DIFFERENT instruction (LDTLB.RN). It must be surfaced as a distinct row,
	// NOT folded into NOTT, and the two must collides-link each other.
	d := &Doc{}
	nott := &Row{}
	nott.Set("group", "Data Transfer Instructions")
	nott.Set("format", "nott")
	nott.Set("code", "0000000001101000")
	d.Rows = append(d.Rows, nott)

	ldtlb := spec.Instr{Name: "LDTLB.RN", Opcode: "0000000001101000", Format: "ldtlb.rn", Slots: []spec.Slot{{}}}
	j4 := &InstrSet{ByKey: map[Key]spec.Instr{}}
	k, _ := KeyOf(ldtlb.Opcode)
	j4.ByKey[k] = ldtlb
	j4.Order = append(j4.Order, ldtlb)

	rep, err := Sync(d, []VariantData{{Variant{Name: "J4", Group: "System Control Instructions"}, j4, &Table{}}})
	if err != nil {
		t.Fatal(err)
	}
	if len(d.Rows) != 2 {
		t.Fatalf("expected 2 rows (NOTT + appended LDTLB.RN), got %d", len(d.Rows))
	}
	if len(rep.Appended) != 1 || rep.Appended[0] != "LDTLB.RN" {
		t.Fatalf("expected LDTLB.RN appended, got %v", rep.Appended)
	}
	// NOTT must NOT be marked J4 (J4 runs LDTLB.RN there, not NOTT).
	if v, _ := nott.Get("J4"); v != false {
		t.Fatalf("NOTT row J4 must be false, got %v", v)
	}
	var ldt *Row
	for _, r := range d.Rows {
		if f, _ := r.Get("format"); f == "LDTLB.RN" {
			ldt = r
		}
	}
	if ldt == nil {
		t.Fatal("appended LDTLB.RN row not found")
	}
	if v, _ := ldt.Get("J4"); v != true {
		t.Fatalf("LDTLB.RN row J4 must be true, got %v", v)
	}
	// Bidirectional collides link.
	for _, r := range []*Row{nott, ldt} {
		c, ok := r.Get("collides")
		if !ok {
			f, _ := r.Get("format")
			t.Fatalf("row %v missing collides", f)
		}
		if arr, _ := c.([]any); len(arr) != 1 {
			f, _ := r.Get("format")
			t.Fatalf("row %v: want 1 collide, got %v", f, c)
		}
	}
}

func TestMnemonicAgreementKeepsFoldedMatches(t *testing.T) {
	// Bucket A (dataset typo via alias) and bucket B (same mnemonic, different
	// register operand) must STAY folded — they are the same op family, not a
	// collision. Each lone row stays single and gets marked, with no append.
	cases := []struct {
		rowFormat string
		specName  string
	}{
		{"ldtbl", "LDTLB"},                // A: SH dataset misspells LDTLB
		{"ldc\tRm,GBR", "LDC, Rm, GBR"},   // A: stray comma in spec name
		{"stc\tMOD,Rn", "STC EXPEVT, Rn"}, // B: MMU reg over DSP MOD reg
	}
	for _, tc := range cases {
		d := &Doc{}
		row := &Row{}
		row.Set("group", "g")
		row.Set("format", tc.rowFormat)
		row.Set("code", "0000000000111000")
		d.Rows = append(d.Rows, row)
		in := spec.Instr{Name: tc.specName, Opcode: "0000000000111000", Slots: []spec.Slot{{}}}
		s := &InstrSet{ByKey: map[Key]spec.Instr{}}
		k, _ := KeyOf(in.Opcode)
		s.ByKey[k] = in
		s.Order = append(s.Order, in)
		rep, err := Sync(d, []VariantData{{Variant{Name: "J4"}, s, &Table{}}})
		if err != nil {
			t.Fatal(err)
		}
		if len(rep.Appended) != 0 {
			t.Fatalf("%q vs %q: must fold (0 appended), got %v", tc.specName, tc.rowFormat, rep.Appended)
		}
		if v, _ := row.Get("J4"); v != true {
			t.Fatalf("%q vs %q: row should be J4=true, got %v", tc.specName, tc.rowFormat, v)
		}
	}
}

func TestSyncDisambiguatesCollidingCodes(t *testing.T) {
	d, err := Load(filepath.Join("testdata", "collide_in.json"))
	if err != nil {
		t.Fatal(err)
	}
	lds := spec.Instr{Name: "LDS Rm, CPI_COM", Opcode: "0100mmmm01011010", Slots: []spec.Slot{{}}}
	j2 := &InstrSet{ByKey: map[Key]spec.Instr{}}
	k, _ := KeyOf(lds.Opcode)
	j2.ByKey[k] = lds
	j2.Order = append(j2.Order, lds)
	if _, err := Sync(d, []VariantData{{Variant{Name: "J2"}, j2, &Table{}}}); err != nil {
		t.Fatal(err)
	}
	var cpi, fpul *Row
	for _, r := range d.Rows {
		f, _ := r.Get("format")
		switch f {
		case "lds Rm,CPI_COM":
			cpi = r
		case "lds Rm,FPUL":
			fpul = r
		}
	}
	if v, _ := cpi.Get("J2"); v != true {
		t.Fatalf("CPI_COM row should be J2=true, got %v", v)
	}
	if v, _ := fpul.Get("J2"); v != false {
		t.Fatalf("FPUL row must NOT be marked, got %v", v)
	}
}

func TestSyncIdempotent(t *testing.T) {
	d, _ := Load(filepath.Join("testdata", "expected.json"))
	before, _ := d.Bytes()
	mov := spec.Instr{Name: "MOV", Opcode: "0110nnnnmmmm0011", Slots: []spec.Slot{{}}}
	ldtlbr := spec.Instr{Name: "LDTLB.RN", Opcode: "0000000001101000", Format: "ldtlb.rn", Slots: []spec.Slot{{}}}
	mk := func(list ...spec.Instr) *InstrSet {
		s := &InstrSet{ByKey: map[Key]spec.Instr{}}
		for _, in := range list {
			k, _ := KeyOf(in.Opcode)
			s.ByKey[k] = in
			s.Order = append(s.Order, in)
		}
		return s
	}
	_, err := Sync(d, []VariantData{
		{Variant{Name: "J2"}, mk(mov), &Table{}},
		{Variant{Name: "J4", Group: "System Control Instructions"}, mk(mov, ldtlbr), &Table{}},
	})
	if err != nil {
		t.Fatal(err)
	}
	after, _ := d.Bytes()
	if string(before) != string(after) {
		t.Fatalf("not idempotent:\n%s\n!=\n%s", before, after)
	}
}

func TestSyncAnnotatesCollides(t *testing.T) {
	d, _ := Load(filepath.Join("testdata", "collide_in.json"))
	_, err := Sync(d, nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range d.Rows {
		f, _ := r.Get("format")
		c, ok := r.Get("collides")
		if !ok {
			t.Fatalf("row %v missing collides", f)
		}
		arr, _ := c.([]any)
		if len(arr) != 1 {
			t.Fatalf("row %v: want 1 collide, got %v", f, c)
		}
	}
}

func TestSyncAppendedRowMarksAllVariants(t *testing.T) {
	// Create an empty doc (no rows)
	d := &Doc{Rows: []*Row{}}

	// Create an opcode that neither variant has seen in the doc
	op := spec.Instr{Name: "SHARED_OP", Opcode: "0000000001101000", Format: "shared.op", Slots: []spec.Slot{{}}}

	// Create J2 and J4 variants, both with the same opcode
	mk := func(list ...spec.Instr) *InstrSet {
		s := &InstrSet{ByKey: map[Key]spec.Instr{}}
		for _, in := range list {
			k, _ := KeyOf(in.Opcode)
			s.ByKey[k] = in
			s.Order = append(s.Order, in)
		}
		return s
	}

	j2 := mk(op)
	j4 := mk(op)

	// Sync with both variants
	rep, err := Sync(d, []VariantData{
		{Variant{Name: "J2", Group: "Test"}, j2, &Table{}},
		{Variant{Name: "J4", Group: "Test"}, j4, &Table{}},
	})
	if err != nil {
		t.Fatal(err)
	}

	// Verify 1 row was appended
	if len(d.Rows) != 1 {
		t.Fatalf("expected 1 row appended, got %d", len(d.Rows))
	}
	if len(rep.Appended) != 1 {
		t.Fatalf("expected 1 appended, got %v", rep.Appended)
	}

	// Verify both variants are marked true on the appended row
	r := d.Rows[0]
	j2v, _ := r.Get("J2")
	if j2v != true {
		t.Fatalf("J2 should be true on appended row, got %v", j2v)
	}
	j4v, _ := r.Get("J4")
	if j4v != true {
		t.Fatalf("J4 should be true on appended row, got %v", j4v)
	}

	// Verify timing fields are present for both
	j2issue, _ := r.Get("J2.issue")
	if j2issue == nil {
		t.Fatal("J2.issue should be present")
	}
	j4issue, _ := r.Get("J4.issue")
	if j4issue == nil {
		t.Fatal("J4.issue should be present")
	}
}
