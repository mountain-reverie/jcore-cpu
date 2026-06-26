package faultgen

import (
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestEmitCaseGeneralPostincLoad is the golden-snippet test for the General
// D-side `MOV.L @Rm+, Rn` case. Per the Task-2 range-safety review the case ->
// helper calls go through a P1-aliased absolute address with `jsr` (NOT the
// range-limited `bsr` the smoke used), so the markers checked here are the
// `jsr`/`_m8_cmp` literal rather than `bsr _m8_cmp`.
func TestEmitCaseGeneralPostincLoad(t *testing.T) {
	s, err := spec.LoadProfile("../../spec", "../../spec/sh4")
	if err != nil {
		t.Fatalf("load spec: %v", err)
	}
	c := Classify(find(t, s, "MOV.L @Rm+, Rn"))
	block, dispatch, err := EmitCase(c, 1)
	if err != nil {
		t.Fatal(err)
	}
	// The block must: name the case, load the workload VA into the base reg,
	// emit the instruction as a .word with the chosen registers substituted
	// (base->r0, dest->r8 => 0x6806), snapshot, and jsr the _m8_cmp helper.
	for _, want := range []string{
		"_m8_case_1:",
		"jsr",
		"_m8_cmp",
		"0x00100000",
		".word   0x6806",
	} {
		if !strings.Contains(block, want) {
			t.Errorf("block missing %q:\n%s", want, block)
		}
	}
	if strings.Contains(block, "bsr") {
		t.Errorf("block must not use range-limited bsr:\n%s", block)
	}
	if !strings.Contains(dispatch, "_m8_case_1") {
		t.Errorf("dispatch missing case-1 reference: %q", dispatch)
	}
}

// TestEmitImageGeneral assembles a small image and checks the scaffolding.
func TestEmitImageGeneral(t *testing.T) {
	s, err := spec.LoadProfile("../../spec", "../../spec/sh4")
	if err != nil {
		t.Fatalf("load spec: %v", err)
	}
	classes := []Class{
		Classify(find(t, s, "MOV.L @Rm+, Rn")),
		Classify(find(t, s, "MOV.L Rm,@-Rn")),
	}
	img, err := EmitImage(classes, DSide)
	if err != nil {
		t.Fatalf("EmitImage: %v", err)
	}
	for _, want := range []string{
		`#include "m8_runtime.inc"`,
		"_m8_run_all",
		"_m8_case_1:",
		"_m8_case_2:",
	} {
		if !strings.Contains(img, want) {
			t.Errorf("image missing %q", want)
		}
	}
}
