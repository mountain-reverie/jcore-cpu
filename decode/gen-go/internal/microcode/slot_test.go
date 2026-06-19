package microcode

import (
	"reflect"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestAssignSlotCLRT tests the CLRT instruction (Clear T bit).
// CLRT: opcode 0000 0000 0000 1000, format "0", sets T=0.
// Expected signals derived by reading vhdlmicrocode.clj:
//   - sr = "T=0" → sr_sel=SEL_SET_T, t_sel=SEL_CLEAR
//   - pc = "INC"  → incpc=1
//   - if_issue = "NO" → no if_issue signal (suppressed)
func TestAssignSlotCLRT(t *testing.T) {
	instr := spec.Instr{Name: "CLRT", Format: "0", Opcode: "0000 0000 0000 1000"}
	slot := spec.Slot{"sr": "T=0", "pc": "INC", "if_issue": "NO"}
	got, err := AssignSlot(instr, slot)
	if err != nil {
		t.Fatal(err)
	}
	want := AssignMap{
		SigSrSel: "SEL_SET_T",
		SigTSel:  "SEL_CLEAR",
		SigIncPC: "1",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("CLRT:\ngot  %+v\nwant %+v", got, want)
	}
}

// TestAssignSlotADDRmRn tests ADD Rm,Rn — the canonical two-register arithmetic case.
// Format "nm": Rn→RA (high nibble), Rm→RB (low nibble).
func TestAssignSlotADDRmRn(t *testing.T) {
	instr := spec.Instr{Name: "ADD Rm, Rn", Format: "nm", Opcode: "0011 nnnn mmmm 1100"}
	slot := spec.Slot{
		"xbus":     "Rn",
		"ybus":     "Rm",
		"zbus":     "Rn",
		"zbus_sel": "ARITH",
		"arith":    "ADD",
		"pc":       "INC",
		"if_issue": "NO",
		"sr":       "HOLD",
	}
	got, err := AssignSlot(instr, slot)
	if err != nil {
		t.Fatal(err)
	}
	want := AssignMap{
		SigXbusSel:   "SEL_REG",
		SigRegnumX:   "RA",
		SigYbusSel:   "SEL_REG",
		SigRegnumY:   "RB",
		SigWrregZ:    "1",
		SigRegnumZ:   "RA",
		SigZbusSel:   "SEL_ARITH",
		SigArithFunc: "ADD",
		SigIncPC:     "1",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("ADD Rm,Rn:\ngot  %+v\nwant %+v", got, want)
	}
}

// TestAssignSlotImmXBus tests that a numeric immediate in xbus sets SEL_IMM
// and records the imm_val tag.
func TestAssignSlotImmXBus(t *testing.T) {
	instr := spec.Instr{Name: "TEST", Format: "0"}
	slot := spec.Slot{"xbus": "0", "zbus_sel": "ARITH"}
	got, err := AssignSlot(instr, slot)
	if err != nil {
		t.Fatal(err)
	}
	if got[SigXbusSel] != "SEL_IMM" {
		t.Errorf("xbus=0: expected SEL_IMM, got %q", got[SigXbusSel])
	}
	if got[SigImmVal] == "" {
		t.Errorf("xbus=0: expected imm_val to be set")
	}
}

// TestAssignSlotPCXBus tests that xbus=PC sets SEL_PC.
func TestAssignSlotPCXBus(t *testing.T) {
	instr := spec.Instr{Name: "TEST", Format: "0"}
	slot := spec.Slot{"xbus": "PC"}
	got, err := AssignSlot(instr, slot)
	if err != nil {
		t.Fatal(err)
	}
	if got[SigXbusSel] != "SEL_PC" {
		t.Errorf("xbus=PC: expected SEL_PC, got %q", got[SigXbusSel])
	}
}

// TestAssignSlotZBusPC tests that zbus=PC sets wrpc_z.
func TestAssignSlotZBusPC(t *testing.T) {
	instr := spec.Instr{Name: "JMP", Format: "m"}
	slot := spec.Slot{"zbus": "PC", "zbus_sel": "ARITH"}
	got, err := AssignSlot(instr, slot)
	if err != nil {
		t.Fatal(err)
	}
	if got[SigWrpcZ] != "1" {
		t.Errorf("zbus=PC: expected wrpc_z=1, got %q", got[SigWrpcZ])
	}
	if _, hasWrregZ := got[SigWrregZ]; hasWrregZ {
		t.Errorf("zbus=PC: unexpected wrreg_z set")
	}
}

// TestAssignSlotZBusTPC tests conditional branch T(PC) → wrpc_z=T.
func TestAssignSlotZBusTPC(t *testing.T) {
	instr := spec.Instr{Name: "BT", Format: "d8"}
	slot := spec.Slot{"zbus": "T(PC)", "zbus_sel": "ARITH"}
	got, err := AssignSlot(instr, slot)
	if err != nil {
		t.Fatal(err)
	}
	if got[SigWrpcZ] != "t_bcc" {
		t.Errorf("zbus=T(PC): expected wrpc_z=t_bcc, got %q", got[SigWrpcZ])
	}
}

// TestAssignSlotSRTSet1 tests sr = "T=1".
func TestAssignSlotSRTSet1(t *testing.T) {
	instr := spec.Instr{Name: "SETT", Format: "0"}
	slot := spec.Slot{"sr": "T=1", "pc": "INC", "if_issue": "NO"}
	got, err := AssignSlot(instr, slot)
	if err != nil {
		t.Fatal(err)
	}
	if got[SigSrSel] != "SEL_SET_T" {
		t.Errorf("sr=T=1: sr_sel=%q want SEL_SET_T", got[SigSrSel])
	}
	if got[SigTSel] != "SEL_SET" {
		t.Errorf("sr=T=1: t_sel=%q want SEL_SET", got[SigTSel])
	}
}

// TestAssignSlotSRW tests sr = "W" (write SR from W-bus).
func TestAssignSlotSRW(t *testing.T) {
	instr := spec.Instr{Name: "LDC SR", Format: "m"}
	slot := spec.Slot{"sr": "W", "pc": "INC", "if_issue": "NO"}
	got, err := AssignSlot(instr, slot)
	if err != nil {
		t.Fatal(err)
	}
	if got[SigWrsrW] != "1" {
		t.Errorf("sr=W: wrsr_w=%q want 1", got[SigWrsrW])
	}
}

// TestAssignSlotWBusRn tests wbus=Rn writes to wrreg_w.
func TestAssignSlotWBusRn(t *testing.T) {
	instr := spec.Instr{Name: "MOV.W @Rm,Rn", Format: "nm"}
	slot := spec.Slot{"wbus": "Rn", "pc": "INC", "if_issue": "NO"}
	got, err := AssignSlot(instr, slot)
	if err != nil {
		t.Fatal(err)
	}
	if got[SigWrregW] != "1" {
		t.Errorf("wbus=Rn: wrreg_w=%q want 1", got[SigWrregW])
	}
	if got[SigRegnumW] != "RA" {
		t.Errorf("wbus=Rn format nm: regnum_w=%q want RA", got[SigRegnumW])
	}
}

// TestAssignSlotMARead tests memory-access read slot.
func TestAssignSlotMARead(t *testing.T) {
	instr := spec.Instr{Name: "MOV.L @Rm,Rn", Format: "nm"}
	slot := spec.Slot{
		"ma_op":    "READ",
		"ma_size":  "32",
		"ma_addy":  "ZBUS",
		"pc":       "INC",
		"if_issue": "NO",
	}
	got, err := AssignSlot(instr, slot)
	if err != nil {
		t.Fatal(err)
	}
	if got[SigMaIssue] != "1" {
		t.Errorf("ma_op=READ: ma_issue=%q want 1", got[SigMaIssue])
	}
	if got[SigMaWr] != "0" {
		t.Errorf("ma_op=READ: ma_wr=%q want 0", got[SigMaWr])
	}
	if got[SigMemSize] != "LONG" {
		t.Errorf("ma_size=32: mem_size=%q want LONG", got[SigMemSize])
	}
	if got[SigMemAddrSel] != "SEL_ZBUS" {
		t.Errorf("ma_addy=ZBUS: mem_addr_sel=%q want SEL_ZBUS", got[SigMemAddrSel])
	}
}

// TestAssignSlotDispatch tests dispatch=YES.
func TestAssignSlotDispatch(t *testing.T) {
	instr := spec.Instr{Name: "RTS", Format: "0"}
	slot := spec.Slot{"dispatch": "YES", "if_issue": "YES"}
	got, err := AssignSlot(instr, slot)
	if err != nil {
		t.Fatal(err)
	}
	if got[SigDispatch] != "1" {
		t.Errorf("dispatch=YES: dispatch=%q want 1", got[SigDispatch])
	}
	if got[SigIfIssue] != "1" {
		t.Errorf("if_issue=YES: if_issue=%q want 1", got[SigIfIssue])
	}
}

// TestAssignSlotPR tests pr="RD PC" → wrpr_pc=1, wrreg_z=1, regnum_z=PR.
func TestAssignSlotPR(t *testing.T) {
	instr := spec.Instr{Name: "JSR", Format: "m"}
	slot := spec.Slot{"pr": "RD PC", "xbus": "PC"}
	got, err := AssignSlot(instr, slot)
	if err != nil {
		t.Fatal(err)
	}
	if got[SigWrprPC] != "1" {
		t.Errorf("pr=RD PC: wrpr_pc=%q want 1", got[SigWrprPC])
	}
	if got[SigWrregZ] != "1" {
		t.Errorf("pr=RD PC: wrreg_z=%q want 1", got[SigWrregZ])
	}
	if got[SigRegnumZ] != "PR" {
		t.Errorf("pr=RD PC: regnum_z=%q want PR", got[SigRegnumZ])
	}
}

// TestAssignSlotProductionSpec exercises every non-system slot in the
// production spec and confirms AssignSlot returns no error. This catches
// "unrecognized slot value" errors across all 160 instructions × ~5 slots.
func TestAssignSlotProductionSpec(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}

	total := 0
	failed := 0
	for _, instr := range s.Instrs {
		if instr.Plane == "system" {
			continue // microcode-only; not included in main decode
		}
		for i, slot := range instr.Slots {
			if len(slot) == 0 {
				continue // empty cycle-terminator slot
			}
			total++
			if _, err := AssignSlot(instr, slot); err != nil {
				t.Errorf("%s slot %d: %v", instr.Name, i, err)
				failed++
			}
		}
	}
	if failed == 0 {
		t.Logf("All %d non-system slots passed AssignSlot", total)
	}
}

// productionSlot0 finds the first non-empty slot of the named
// instruction in the production spec and returns its AssignMap.
// It is a test helper for the targeted regression tests below.
func productionSlot0(t *testing.T, name string) (spec.Instr, AssignMap) {
	t.Helper()
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	for _, instr := range s.Instrs {
		if instr.Name != name {
			continue
		}
		for _, slot := range instr.Slots {
			if len(slot) > 0 {
				am, err := AssignSlot(instr, slot)
				if err != nil {
					t.Fatal(err)
				}
				return instr, am
			}
		}
	}
	t.Fatalf("instruction %q not found in production spec", name)
	return spec.Instr{}, nil
}

// assertSignal checks one (Signal, expected value) pair in an AssignMap.
func assertSignal(t *testing.T, am AssignMap, sig Signal, want string) {
	t.Helper()
	got, ok := am[sig]
	if !ok {
		t.Errorf("%s: missing signal (want %q)", sig, want)
		return
	}
	if got != want {
		t.Errorf("%s: got %q, want %q", sig, got, want)
	}
}

// TestAssignSlotMAC_L pins distinctive signals for MAC.L @Rm+, @Rn+ slot 0.
// The first slot reads (Rn) and post-increments Rn by 4, kicks off the
// MAC pipeline's wb-stage path (wb_macsel1, wb_mulcom1).
func TestAssignSlotMAC_L(t *testing.T) {
	_, am := productionSlot0(t, "MAC.L @Rm+, @Rn+")
	assertSignal(t, am, SigArithFunc, "ADD")
	assertSignal(t, am, SigImmVal, "IMM_P4")
	assertSignal(t, am, SigMaIssue, "1")
	assertSignal(t, am, SigMaWr, "0")
	assertSignal(t, am, SigMemSize, "LONG")
	assertSignal(t, am, SigRegnumX, "RA")
	assertSignal(t, am, SigRegnumZ, "RA")
	assertSignal(t, am, SigWbMacsel1, "SEL_WBUS")
	assertSignal(t, am, SigWbMulcom1, "1")
	assertSignal(t, am, SigWrregZ, "1")
}

// TestAssignSlotDIV1 pins distinctive signals for DIV1 Rm, Rn. The
// instruction uses the ROTCL aluinx path with the DIV1 arith_sr update.
func TestAssignSlotDIV1(t *testing.T) {
	_, am := productionSlot0(t, "DIV1 Rm, Rn")
	assertSignal(t, am, SigAluinxSel, "SEL_ROTCL")
	assertSignal(t, am, SigArithFunc, "ADD")
	assertSignal(t, am, SigArithSrFn, "DIV1")
	assertSignal(t, am, SigSrSel, "SEL_ARITH")
	assertSignal(t, am, SigXbusSel, "SEL_REG")
	assertSignal(t, am, SigYbusSel, "SEL_REG")
	assertSignal(t, am, SigRegnumX, "RA")
	assertSignal(t, am, SigRegnumY, "RB")
	assertSignal(t, am, SigZbusSel, "SEL_ARITH")
	assertSignal(t, am, SigWrregZ, "1")
}

// TestAssignSlotRTE pins distinctive signals for RTE slot 0. RTE pops
// PC and SR from the stack across multiple slots; slot 0 reads (R15).
func TestAssignSlotRTE(t *testing.T) {
	_, am := productionSlot0(t, "RTE")
	assertSignal(t, am, SigArithFunc, "ADD")
	assertSignal(t, am, SigImmVal, "IMM_P4")
	assertSignal(t, am, SigMaIssue, "1")
	assertSignal(t, am, SigMaWr, "0")
	assertSignal(t, am, SigMemSize, "LONG")
	assertSignal(t, am, SigRegnumX, "R15")
	assertSignal(t, am, SigRegnumZ, "R15")
	assertSignal(t, am, SigWrregZ, "1")
	assertSignal(t, am, SigIncPC, "1")
}

// TestAssignSlotValuesAreValidVHDLIdentifiers walks every production
// slot and verifies that every signal value produced by AssignSlot is
// a valid VHDL identifier (or a single-digit '0'/'1'). Catches the
// regression where slot.go returned Clojure-keyword-style abbreviations
// like "B=", "U>=", "EXT_UB" that flowed straight into the generated
// VHDL and broke GHDL compilation. Valid identifiers contain only
// [A-Za-z0-9_].
func TestAssignSlotValuesAreValidVHDLIdentifiers(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}
	// Values that aren't bare VHDL identifiers but ARE valid VHDL
	// expressions emitted by AssignSlot for specific signals
	// (dispatch/if_issue → t_bcc / not t_bcc). The simple/direct emitters
	// route these through signalRHS / directValue which knows how to
	// render them. RegnumVHDL handles regnum tags downstream too.
	allowedExprs := map[string]bool{
		"t_bcc":     true,
		"not t_bcc": true,
	}
	isValid := func(v string) bool {
		if v == "" {
			return true // empty = absent
		}
		if allowedExprs[v] {
			return true
		}
		for _, c := range v {
			ok := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
				(c >= '0' && c <= '9') || c == '_'
			if !ok {
				return false
			}
		}
		return true
	}
	for _, instr := range s.Instrs {
		for i, slot := range instr.Slots {
			if len(slot) == 0 {
				continue
			}
			am, err := AssignSlot(instr, slot)
			if err != nil {
				continue // covered by TestAssignSlotProductionSpec
			}
			for sig, val := range am {
				if !isValid(val) {
					t.Errorf("%s slot %d: %s = %q is not a valid VHDL identifier",
						instr.Name, i, sig, val)
				}
			}
		}
	}
}

// TestNamedRegsRegnumVHDLCoverage asserts that every register in namedRegs
// has a non-empty entry in namedRegVHDL. This is the compile-time guard that
// prevents a new named register from being added to the bus-dispatch helpers
// without a matching VHDL encoding.
func TestNamedRegsRegnumVHDLCoverage(t *testing.T) {
	for _, name := range namedRegs {
		got := RegnumVHDL(name)
		if got == "" {
			t.Errorf("namedRegs entry %q has no RegnumVHDL mapping", name)
		}
		// RegnumVHDL must not fall through to the identity return (tag == result)
		// for named registers; that would mean namedRegVHDL is missing the entry.
		if got == name {
			t.Errorf("namedRegs entry %q: RegnumVHDL returned the tag unchanged (missing namedRegVHDL entry?)", name)
		}
	}
}

// TestAssignSlotTRAPA pins distinctive signals for TRAPA #imm slot 0:
// pushes SR onto the stack with a pre-decrement.
func TestAssignSlotTRAPA(t *testing.T) {
	_, am := productionSlot0(t, "TRAPA #imm")
	assertSignal(t, am, SigArithFunc, "SUB")
	assertSignal(t, am, SigImmVal, "IMM_P4")
	assertSignal(t, am, SigMaIssue, "1")
	assertSignal(t, am, SigMaWr, "1")
	assertSignal(t, am, SigMemSize, "LONG")
	assertSignal(t, am, SigMemAddrSel, "SEL_ZBUS")
	assertSignal(t, am, SigMemWdataSel, "SEL_YBUS")
	assertSignal(t, am, SigRegnumX, "R15")
	assertSignal(t, am, SigYbusSel, "SEL_SR")
	assertSignal(t, am, SigRegnumZ, "R15")
	assertSignal(t, am, SigWrregZ, "1")
}

// TestAssignSR_CaptureSelectors covers the PM3 SH-4 cause-capture selectors:
// sr = "EXPEVT"/"INTEVT"/"TRA" latches the slot immediate into the dedicated
// control register via sr_sel.
func TestAssignSR_CaptureSelectors(t *testing.T) {
	for _, c := range []struct{ in, want string }{
		{"EXPEVT", "SEL_EXPEVT"}, {"INTEVT", "SEL_INTEVT"}, {"TRA", "SEL_TRA"},
	} {
		out := AssignMap{}
		if err := assignSR(c.in, out); err != nil {
			t.Fatalf("assignSR(%q): %v", c.in, err)
		}
		if out[SigSrSel] != c.want {
			t.Errorf("sr=%q -> sr_sel=%q, want %q", c.in, out[SigSrSel], c.want)
		}
	}
}

// TestAssignYBus_CauseRegs covers the PM3 STC read path: ybus = "EXPEVT"/
// "INTEVT"/"TRA" selects the dedicated control register onto the y-bus.
func TestAssignYBus_CauseRegs(t *testing.T) {
	for _, c := range []struct{ in, want string }{
		{"EXPEVT", "SEL_EXPEVT"}, {"INTEVT", "SEL_INTEVT"}, {"TRA", "SEL_TRA"},
	} {
		out := AssignMap{}
		if err := assignYBus(c.in, "", "", out); err != nil {
			t.Fatalf("assignYBus(%q): %v", c.in, err)
		}
		if out[SigYbusSel] != c.want {
			t.Errorf("ybus=%q -> ybus_sel=%q, want %q", c.in, out[SigYbusSel], c.want)
		}
	}
}

func TestAssignYBus_MMU(t *testing.T) {
	for _, reg := range []string{"PTEH", "PTEL", "ASIDR"} {
		out := AssignMap{}
		if err := assignYBus(reg, "", "", out); err != nil {
			t.Fatalf("assignYBus(%q): %v", reg, err)
		}
		assertSignal(t, out, SigYbusSel, "SEL_MMU")
		assertSignal(t, out, SigMmuRegSel, "SEL_"+reg)
	}
}

func TestAssignZBus_MMU(t *testing.T) {
	for _, reg := range []string{"PTEH", "PTEL", "ASIDR"} {
		out := AssignMap{}
		if err := assignZBus(reg, "", "", out); err != nil {
			t.Fatalf("assignZBus(%q): %v", reg, err)
		}
		assertSignal(t, out, SigMmuRegWr, "1")
		assertSignal(t, out, SigMmuRegSel, "SEL_"+reg)
		if _, ok := out[SigWrregZ]; ok {
			t.Fatalf("zbus=%q must NOT write the regfile (SigWrregZ set)", reg)
		}
	}
}
