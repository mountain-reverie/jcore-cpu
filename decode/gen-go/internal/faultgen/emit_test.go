package faultgen

import (
	"fmt"
	"sort"
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

// TestEmitCaseMacDualBase asserts MAC.L @Rm+,@Rn+ is emitted (not skipped) and
// seeds + snapshots BOTH base registers (r0,r8) plus MACH/MACL across two
// distinct mapped pages, so fault-on-the-second-operand is observable.
func TestEmitCaseMacDualBase(t *testing.T) {
	s, err := spec.LoadProfile("../../spec", "../../spec/sh4")
	if err != nil {
		t.Fatalf("load spec: %v", err)
	}
	c := Classify(find(t, s, "MAC.L @Rm+, @Rn+"))
	block, dispatch, err := EmitCase(c, 5)
	if err != nil {
		t.Fatalf("MAC must be emitted, got: %v\n%s", err, block)
	}
	for _, want := range []string{
		"_m8_case_5:",
		".word   0x080F", // MAC.L with m->r0,n->r8
		"c5_seedva: .long 0x00100000",
		"c5_seedvb: .long 0x00101000", // second mapped page (distinct fault)
		"lds     r9, mach",            // deterministic accumulator clear (not clrmac: TEMP1-xor sim-X)
		"lds     r9, macl",
		"sts     mach, r1",
		"sts     macl, r1",
		"mov     #16, r4", // 16-byte snapshot = r0,r8,MACH,MACL
		// Per-operand-position coverage: fault on op1 only, op2 only, both cold.
		"fault on operand 1 only",
		"fault on operand 2 only",
		"both operands cold",
		"pre-warm page B (Rn): only operand 1 (Rm) faults",
		"pre-warm page A (Rm): only operand 2 (Rn) faults",
		// Per-position reported IDs (1000*pos + case ID) so a CI Result=<ID>
		// localises which operand position faulted.
		"c5_id1: .long 1005",
		"c5_id2: .long 2005",
		"c5_id3: .long 3005",
	} {
		if !strings.Contains(block, want) {
			t.Errorf("MAC block missing %q:\n%s", want, block)
		}
	}
	// Three positions x two legs each => r8 snapshotted six times.
	if strings.Count(block, "mov.l   r8, @(4,r2)") != 6 {
		t.Errorf("MAC must snapshot the second base r8 in both legs of all 3 positions:\n%s", block)
	}
	if !strings.Contains(dispatch, "_m8_case_5") {
		t.Errorf("dispatch missing case-5 reference: %q", dispatch)
	}
}

// TestEmitCaseCtrlLoad asserts a control-register post-increment load is emitted
// (not the old 'U'-hang skip) and that it benign-INITs the dest ctrl reg and
// RESTOREs it -- i.e. the oracle is not vacuous and machine state is preserved.
func TestEmitCaseCtrlLoad(t *testing.T) {
	s, err := spec.LoadProfile("../../spec", "../../spec/sh4")
	if err != nil {
		t.Fatalf("load spec: %v", err)
	}

	// LDC.L @Rm+, GBR -> emitted, benign-init + read-back + restore via gbr.
	c := Classify(find(t, s, "LDC.L @Rm+, GBR"))
	block, _, err := EmitCase(c, 6)
	if err != nil {
		t.Fatalf("LDC.L @Rm+,GBR must be emitted, got: %v\n%s", err, block)
	}
	for _, want := range []string{
		"_m8_case_6:",
		"ldc     r1, gbr", // benign-init AND restore use ldc r1,gbr
		"stc     gbr, r1", // read-back for snapshot/baseline
		"c6_ctlsv:",       // baseline save slot (restore target)
	} {
		if !strings.Contains(block, want) {
			t.Errorf("ctrl-load block missing %q:\n%s", want, block)
		}
	}
	// init+restore: ldc r1,gbr must appear at least twice (baseline-init + per
	// leg) and the baseline must be reloaded for restore.
	if strings.Count(block, "ldc     r1, gbr") < 3 {
		t.Errorf("ctrl-load not init+restore (expected >=3 ldc r1,gbr):\n%s", block)
	}

	// LDS.L @Rm+, MACH -> emitted (classifier marks it General, but the emitter
	// routes control-loads by name so the ctrl reg is still snapshotted).
	cm := Classify(find(t, s, "LDS.L @Rm+, MACH"))
	mblock, _, merr := EmitCase(cm, 7)
	if merr != nil {
		t.Fatalf("LDS.L @Rm+,MACH must be emitted, got: %v\n%s", merr, mblock)
	}
	if !strings.Contains(mblock, "lds     r1, mach") || !strings.Contains(mblock, "sts     mach, r1") {
		t.Errorf("MACH ctrl-load missing benign-init/read-back:\n%s", mblock)
	}

	// LDC.L @Rm+, SR -> now EMITTED with a mode-preserving payload: the @Rm+ word
	// is seeded to the current SR (via stc sr,r1), so the load is a no-op while the
	// base auto-modify is exercised + snapshotted. No benign-init/restore needed.
	cs := Classify(find(t, s, "LDC.L @Rm+, SR"))
	sblock, sdisp, serr := EmitCase(cs, 8)
	if serr != nil {
		t.Fatalf("LDC.L @Rm+,SR must now be emitted, got err=%v\n%s", serr, sblock)
	}
	for _, want := range []string{
		"_m8_case_8:",
		"mode-preserving",
		"stc     sr, r1",  // seed payload = current SR (and snapshot read-back)
		".word   0x4007",  // LDC.L @Rm+,SR with m->r0
		"mov.l   r1, @r0", // seed the payload word
	} {
		if !strings.Contains(sblock, want) {
			t.Errorf("SR mode-preserving block missing %q:\n%s", want, sblock)
		}
	}
	// Must NOT clobber SR via an arbitrary load (no ldc r1,sr in the body).
	if strings.Contains(sblock, "ldc     r1, sr") {
		t.Errorf("SR mode-preserving block must not reload SR from an arbitrary value:\n%s", sblock)
	}
	if sdisp == "" {
		t.Errorf("emitted SR load must produce a dispatch entry")
	}

	// LDC.L @Rm+, VBR -> likewise emitted with a current-VBR payload.
	cv := Classify(find(t, s, "LDC.L @Rm+, VBR"))
	vblock, vdisp, verr := EmitCase(cv, 9)
	if verr != nil {
		t.Fatalf("LDC.L @Rm+,VBR must now be emitted, got err=%v\n%s", verr, vblock)
	}
	for _, want := range []string{"_m8_case_9:", "mode-preserving", "stc     vbr, r1", ".word   0x4027"} {
		if !strings.Contains(vblock, want) {
			t.Errorf("VBR mode-preserving block missing %q:\n%s", want, vblock)
		}
	}
	if vdisp == "" {
		t.Errorf("emitted VBR load must produce a dispatch entry")
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

// TestEmitIFetchGeneral covers the instruction-FETCH axis: a General non-memory
// instruction plants [instr ; jmp @r12 ; nop] into the translated code page and
// snapshots {r0,r8,T,MACH,MACL}. It also asserts the emitter never produces the
// invalid displacement-store form `mov.w Rm,@(disp,Rn)` (the old template bug --
// only `mov.w R0,@(disp,Rn)` is legal), and that out-of-scope instructions are
// skipped with a manifest reason (memory, PrivMem, coprocessor, system plane).
func TestEmitIFetchGeneral(t *testing.T) {
	s, err := spec.LoadProfile("../../spec", "../../spec/sh4")
	if err != nil {
		t.Fatalf("load spec: %v", err)
	}

	// ADD Rm,Rn: General non-memory -> emitted, snapshot 24 bytes (incl SR), jmp stub.
	c := Classify(find(t, s, "ADD Rm, Rn"))
	block, _, err := emitCase(c, 1, IFetch)
	if err != nil {
		t.Fatalf("ADD Rm,Rn should emit on I-fetch: %v", err)
	}
	for _, want := range []string{"_m8_case_1:", "jmp     @r5", "0x4C2B", "mov     #24, r4", "0x00100000", "stc     sr, r1", "c1_srmsk"} {
		if !strings.Contains(block, want) {
			t.Errorf("I-fetch ADD block missing %q:\n%s", want, block)
		}
	}
	// No invalid mov.w displacement store of a general register.
	for _, lineBad := range strings.Split(block, "\n") {
		l := strings.TrimSpace(lineBad)
		if strings.HasPrefix(l, "mov.w") && strings.Contains(l, "@(") && !strings.Contains(l, "r0,") && !strings.Contains(l, "R0,") {
			// allow `mov.w c..._instrw, r6` (a load); reject a STORE `mov.w rN,@(disp,...)`.
			if strings.Contains(l, ",@(") {
				t.Errorf("invalid mov.w displacement store of a non-R0 register: %q", l)
			}
		}
	}

	// Out-of-scope instructions are skipped (errSkip) with a reason.
	for _, name := range []string{"MOV.L @Rm+, Rn", "LDC Rm, SR", "BGND"} {
		c := Classify(find(t, s, name))
		if _, _, err := emitCase(c, 2, IFetch); !IsSkip(err) {
			t.Errorf("%s should be skipped on I-fetch axis, got err=%v", name, err)
		}
	}
}

// TestEmitIFetchImagesPartition checks the I-fetch axis is split into sub-images
// of at most IFetchPerImage cases, that every emitted case appears exactly once
// across the set with GLOBAL contiguous IDs, and that each sub-image has its own
// _m8_run_all whose m8_count equals that sub-image's case count.
func TestEmitIFetchImagesPartition(t *testing.T) {
	s, err := spec.LoadProfile("../../spec", "../../spec/sh4")
	if err != nil {
		t.Fatalf("load spec: %v", err)
	}
	instrs := make([]spec.Instr, len(s.Instrs))
	copy(instrs, s.Instrs)
	sort.SliceStable(instrs, func(i, j int) bool { return instrs[i].Name < instrs[j].Name })
	classes := make([]Class, len(instrs))
	for i, in := range instrs {
		classes[i] = Classify(in)
	}

	imgs, err := EmitIFetchImages(classes)
	if err != nil {
		t.Fatalf("EmitIFetchImages: %v", err)
	}
	total := 0
	seen := map[int]bool{}
	for k, img := range imgs {
		n := strings.Count(img, "_m8_case_")
		// crude case-label count: each routine label "_m8_case_N:" appears once
		// in its block plus once in the dispatch ".long ... + _m8_case_N".
		labels := 0
		for _, line := range strings.Split(img, "\n") {
			l := strings.TrimSpace(line)
			if strings.HasPrefix(l, "_m8_case_") && strings.Contains(l, ":") {
				labels++
				var id int
				fmt.Sscanf(l, "_m8_case_%d:", &id)
				if seen[id] {
					t.Errorf("case %d appears in more than one sub-image", id)
				}
				seen[id] = true
			}
		}
		if labels > IFetchPerImage {
			t.Errorf("sub-image %d has %d cases > IFetchPerImage=%d", k, labels, IFetchPerImage)
		}
		if !strings.Contains(img, fmt.Sprintf("m8_count:  .long %d", labels)) {
			t.Errorf("sub-image %d m8_count != case count %d", k, labels)
		}
		total += labels
		_ = n
	}
	if total != len(seen) {
		t.Errorf("duplicate cases across sub-images: total=%d unique=%d", total, len(seen))
	}
	// Global IDs must be contiguous 1..total.
	for id := 1; id <= total; id++ {
		if !seen[id] {
			t.Errorf("missing global case ID %d", id)
		}
	}
}
