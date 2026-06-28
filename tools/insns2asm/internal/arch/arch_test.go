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
	if got := (Set{SH2E: true}).GASMask(); got != "arch_sh2e_up" {
		t.Errorf("SH2E GASMask = %q", got)
	}
	if got := (Set{SH3: true}).GASMask(); got != "arch_sh3_up" {
		t.Errorf("SH3 GASMask = %q", got)
	}
	if got := (Set{SH4: true}).GASMask(); got != "arch_sh4_up" {
		t.Errorf("SH4 GASMask = %q", got)
	}
}

func TestLLVMPredicates(t *testing.T) {
	got := (Set{J2: true}).LLVMPredicates()
	if !reflect.DeepEqual(got, []string{"HasJ2"}) {
		t.Errorf("preds = %#v", got)
	}
	got = (Set{SH3: true}).LLVMPredicates()
	if !reflect.DeepEqual(got, []string{"HasSH3"}) {
		t.Errorf("SH3 preds = %#v", got)
	}
	got = (Set{SH4A: true}).LLVMPredicates()
	if !reflect.DeepEqual(got, []string{"HasSH4A"}) {
		t.Errorf("SH4A preds = %#v", got)
	}
}
