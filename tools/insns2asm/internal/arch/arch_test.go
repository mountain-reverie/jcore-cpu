package arch

import (
	"reflect"
	"testing"
)

func TestIsJCoreOnly(t *testing.T) {
	if !(Set{J2: true}).IsJCoreOnly() {
		t.Error("J2-only should be jcore-only")
	}
	if (Set{SH1: true, J2: true}).IsJCoreOnly() {
		t.Error("SH1+J2 is not jcore-only")
	}
}

func TestGASMask(t *testing.T) {
	if got := (Set{SH1: true, SH2: true}).GASMask(); got != "arch_sh1_up" {
		t.Errorf("GASMask = %q", got)
	}
	if got := (Set{J2: true}).GASMask(); got != "arch_j_core" {
		t.Errorf("jcore GASMask = %q", got)
	}
}

func TestLLVMPredicates(t *testing.T) {
	got := (Set{J2: true}).LLVMPredicates()
	if !reflect.DeepEqual(got, []string{"HasJ2"}) {
		t.Errorf("preds = %#v", got)
	}
}
