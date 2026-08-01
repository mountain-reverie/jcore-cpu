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

// TestInsnsCheckAcceptsStringLatency: the "n+" variable-latency form must
// survive the actual path insns-check exercises — Sync writing a Cell into
// a Row, Doc.Bytes() marshaling it, and Load() reading it back — with no
// data loss and no error. There is no separate validateRow function in this
// codebase; the "check" performed by `cpugen insns --check` is a byte-diff
// of Doc.Bytes() against the on-disk insns.json (see runInsns in
// cmd/cpugen/main.go), and jsondoc.go decodes/encodes row values generically
// via `any`, so a string cell must round-trip untouched alongside int cells.
func TestInsnsCheckAcceptsStringLatency(t *testing.T) {
	d := &Doc{}
	op := spec.Instr{Name: "SHLL_LIKE", Opcode: "0000000001101000", Format: "shll.like", Slots: []spec.Slot{{}}}
	j2a := &InstrSet{ByKey: map[Key]spec.Instr{}}
	k, _ := KeyOf(op.Opcode)
	j2a.ByKey[k] = op
	j2a.Order = append(j2a.Order, op)

	tab := &Table{Overrides: map[string]Timing{
		normOpcode(op.Opcode): {Issue: II(1), Latency: ParseCell("2+")},
	}}

	if _, err := Sync(d, []VariantData{{Variant{Name: "J2A"}, j2a, tab}}); err != nil {
		t.Fatalf("string latency rejected by Sync: %v", err)
	}

	out, err := d.Bytes()
	if err != nil {
		t.Fatalf("string latency rejected by Doc.Bytes: %v", err)
	}

	reloaded, err := Load(bytesToTempFile(t, out))
	if err != nil {
		t.Fatalf("string latency rejected on reload: %v", err)
	}
	lat, ok := reloaded.Rows[0].Get("J2A.latency")
	if !ok || lat != "2+" {
		t.Fatalf("want J2A.latency = \"2+\", got %v (ok=%v)", lat, ok)
	}
}

func bytesToTempFile(t *testing.T, b []byte) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "insns.json")
	if err := os.WriteFile(p, b, 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

// TestSyncTwoWordMatch: a two-word (Opcode2) spec instruction must MATCH the
// existing two-word insns.json row (set its variant column), not append a
// duplicate. Regression for the disp12 mov J2A-column sync.
func TestSyncTwoWordMatch(t *testing.T) {
	doc := &Doc{}
	row := &Row{}
	row.Set("group", "Data Transfer Instructions")
	row.Set("format", "mov.l\t@(disp12,Rm),Rn")
	row.Set("code", "0011nnnnmmmm0001 0110dddddddddddd")
	doc.Rows = append(doc.Rows, row)

	in := spec.Instr{Name: "MOV.L @(disp12,Rm),Rn", Opcode: "0011 nnnn mmmm 0001", Opcode2: "0110 dddd dddd dddd"}
	k, ok := keyOfInstr(in)
	if !ok {
		t.Fatal("keyOfInstr failed for two-word instr")
	}
	set := &InstrSet{ByKey: map[Key]spec.Instr{k: in}, Order: []spec.Instr{in}}
	vd := VariantData{Variant: Variant{Name: "J2A"}, Set: set, Tab: &Table{}}

	rep, err := Sync(doc, []VariantData{vd})
	if err != nil {
		t.Fatal(err)
	}
	if len(rep.Appended) != 0 {
		t.Fatalf("expected no appended rows, got %v", rep.Appended)
	}
	if len(doc.Rows) != 1 {
		t.Fatalf("expected 1 row (matched in place), got %d", len(doc.Rows))
	}
	if v, _ := doc.Rows[0].Get("J2A"); v != true {
		t.Errorf("existing two-word row J2A = %v, want true", v)
	}
}

func TestOverlapKeys(t *testing.T) {
	one := func(t *testing.T, p string) Key {
		t.Helper()
		k, ok := KeyOf(p)
		if !ok {
			t.Fatalf("KeyOf(%q) failed", p)
		}
		return k
	}
	two := func(t *testing.T, w1, w2 string) Key {
		t.Helper()
		k, ok := KeyOf2(w1, w2)
		if !ok {
			t.Fatalf("KeyOf2(%q, %q) failed", w1, w2)
		}
		return k
	}

	t.Run("identical single word", func(t *testing.T) {
		a := one(t, "0110nnnnmmmm0011")
		if !overlapKeys(a, a) {
			t.Error("a key must overlap itself")
		}
	})

	t.Run("differing masks still overlap", func(t *testing.T) {
		// The second pattern's m-field spans the first's fixed 1100.
		// Equality would miss this; overlap must not.
		a := one(t, "0000nnnn11001011")
		b := one(t, "0000nnnnmmmm1011")
		if !overlapKeys(a, b) {
			t.Error("overlapping masks reported as disjoint")
		}
		if !overlapKeys(b, a) {
			t.Error("overlapKeys is not symmetric")
		}
	})

	t.Run("disjoint low nibble", func(t *testing.T) {
		a := one(t, "0110nnnnmmmm0011")
		b := one(t, "0110nnnnmmmm0100")
		if overlapKeys(a, b) {
			t.Error("keys differing in a bit both fix must not overlap")
		}
	})

	t.Run("two word sharing word1 but differing ext word", func(t *testing.T) {
		// This is the real disp12 case: same word 1, different extension
		// word high nibble. They do NOT collide.
		a := two(t, "0011nnnnmmmm0001", "0100dddddddddddd")
		b := two(t, "0011nnnnmmmm0001", "0111dddddddddddd")
		if overlapKeys(a, b) {
			t.Error("two-word keys with differing ext words must not overlap")
		}
	})

	t.Run("two word sharing word1 and ext word", func(t *testing.T) {
		a := two(t, "0011nnnnmmmm0001", "0100dddddddddddd")
		b := two(t, "0011nnnnmmmm0001", "0100dddddddddddd")
		if !overlapKeys(a, b) {
			t.Error("identical two-word keys must overlap")
		}
	})

	t.Run("single word versus two word compares word1 only", func(t *testing.T) {
		a := one(t, "0011nnnnmmmm0001")
		b := two(t, "0011nnnnmmmm0001", "0100dddddddddddd")
		if !overlapKeys(a, b) {
			t.Error("a single-word instruction claims the whole word")
		}
		if !overlapKeys(b, a) {
			t.Error("overlapKeys is not symmetric across widths")
		}
	})
}

func TestVariantColumns(t *testing.T) {
	got := VariantColumns()
	want := []string{"DSP", "J1", "J2", "J2A", "J4", "SH1", "SH2", "SH2A", "SH2E", "SH3", "SH3E", "SH4", "SH4A"}
	if len(got) != len(want) {
		t.Fatalf("VariantColumns() = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("VariantColumns() = %v, want %v", got, want)
		}
	}
	// Callers must not be able to corrupt the canonical list.
	got[0] = "MUTATED"
	if VariantColumns()[0] != "DSP" {
		t.Error("VariantColumns() returns the backing array; it must return a copy")
	}
}
