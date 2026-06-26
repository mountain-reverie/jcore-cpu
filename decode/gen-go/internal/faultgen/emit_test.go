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

// TestEmitCaseStoreProbe asserts the store snapshot probes the address the
// store actually writes (not a vacuous base probe):
//
//	(a) a displacement store `MOV.L Rm, @(disp, Rn)` either seeds & probes the
//	    correct effective address (VA+disp) or is skipped with a manifest reason;
//	(b) an indexed store `MOV.L Rm, @(R0, Rn)` is skipped (not emitted with a
//	    base=VA probe), because the implicit R0 operand is not modelled.
func TestEmitCaseStoreProbe(t *testing.T) {
	s, err := spec.LoadProfile("../../spec", "../../spec/sh4")
	if err != nil {
		t.Fatalf("load spec: %v", err)
	}

	// (a) displacement store.
	dc := Classify(find(t, s, "MOV.L Rm, @(disp, Rn)"))
	block, _, err := EmitCase(dc, 7)
	if IsSkip(err) {
		if !strings.Contains(block, "not probeable") {
			t.Errorf("disp store skip lacks manifest reason: %q", block)
		}
	} else if err != nil {
		t.Fatalf("disp store: %v", err)
	} else {
		// Encoded disp nibble is 0 -> effective address == VA. The probe and
		// the seed window must reference that effective address.
		if !strings.Contains(block, "c7_probe:  .long 0x00100000") {
			t.Errorf("disp store probe is not the effective address:\n%s", block)
		}
		if !strings.Contains(block, "c7_seedva: .long 0x00100000") {
			t.Errorf("disp store does not seed the effective address window:\n%s", block)
		}
	}

	// (b) indexed store must be skipped, never emitted with a base probe.
	ic := Classify(find(t, s, "MOV.L Rm, @(R0, Rn)"))
	iblock, idisp, ierr := EmitCase(ic, 8)
	if !IsSkip(ierr) {
		t.Fatalf("indexed @(R0,Rn) store must be skipped, got err=%v block=%q", ierr, iblock)
	}
	if !strings.Contains(iblock, "not modelled") || !strings.Contains(iblock, "R0") {
		t.Errorf("indexed store skip lacks a clear manifest reason: %q", iblock)
	}
	if idisp != "" {
		t.Errorf("skipped indexed store must not emit a dispatch entry: %q", idisp)
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
