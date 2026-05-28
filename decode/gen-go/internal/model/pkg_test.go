package model

import "testing"

// TestRecordsInvariantDecodeCoreRegLast guards the invariant documented
// on newStaticPackage: the decode_pkg.vhd.tmpl renderer emits
// Records[:last] before the components and Records[last] after, and
// expects that last record to be decode_core_reg_t.
func TestRecordsInvariantDecodeCoreRegLast(t *testing.T) {
	pkg := newStaticPackage()
	if len(pkg.Records) == 0 {
		t.Fatal("Package has no Records")
	}
	last := pkg.Records[len(pkg.Records)-1]
	if last.Name != "decode_core_reg_t" {
		t.Errorf("last record is %q, want %q (the decode_pkg.vhd.tmpl "+
			"renderer assumes decode_core_reg_t is last)", last.Name, "decode_core_reg_t")
	}
}
