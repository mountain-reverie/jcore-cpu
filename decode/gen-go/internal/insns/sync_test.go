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
	ldtlbr := spec.Instr{Name: "LDTLB.R", Opcode: "0000000001101000", Format: "ldtlb.r", Slots: []spec.Slot{{}}}
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

func TestSyncIdempotent(t *testing.T) {
	d, _ := Load(filepath.Join("testdata", "expected.json"))
	before, _ := d.Bytes()
	mov := spec.Instr{Name: "MOV", Opcode: "0110nnnnmmmm0011", Slots: []spec.Slot{{}}}
	ldtlbr := spec.Instr{Name: "LDTLB.R", Opcode: "0000000001101000", Format: "ldtlb.r", Slots: []spec.Slot{{}}}
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
