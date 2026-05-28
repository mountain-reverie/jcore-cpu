// Package microcode ports the Clojure decoder generator's signal
// assignment, immediate-value collection, and ROM packing algorithms.
//
// Vocabulary: a "signal" is one of the named control-bus fields that
// the decoder emits per microcode slot (e.g., xbus_sel, regnum_x,
// wrreg_z). Each Signal carries a string Value that names the VHDL
// enum literal or constant it resolves to (e.g., "SEL_REG", "RA",
// "1"). The combination of (Signal, Value) pairs across all slots
// drives ROM bit-field layout in CreateEncoding.
package microcode

// Signal is the canonical name of one decoder control-bus field.
// Names use snake_case to mirror the VHDL record field names in
// decode_pkg.vhd's pipeline_ex_t and friends. Matches the Clojure
// keyword vocabulary in vhdlmicrocode.clj (kebab → snake).
type Signal string

const (
	// Bus selectors and register numbers (from x-bus/y-bus/z-bus/w-bus)
	SigXbusSel  Signal = "xbus_sel"
	SigYbusSel  Signal = "ybus_sel"
	SigZbusSel  Signal = "zbus_sel"
	SigRegnumX  Signal = "regnum_x"
	SigRegnumY  Signal = "regnum_y"
	SigRegnumZ  Signal = "regnum_z"
	SigRegnumW  Signal = "regnum_w"
	SigWrregZ   Signal = "wrreg_z"
	SigWrregW   Signal = "wrreg_w"
	SigWrpcZ    Signal = "wrpc_z"
	SigWrprPC   Signal = "wrpr_pc"
	SigWrsrW    Signal = "wrsr_w"
	SigWrsrZ    Signal = "wrsr_z"

	// ALU
	SigAluinxSel  Signal = "aluinx_sel"
	SigAluinySel  Signal = "aluiny_sel"
	SigAluManip   Signal = "alumanip"
	SigArithFunc  Signal = "arith_func"
	SigArithSrFn  Signal = "arith_sr_func"
	SigArithCiEn  Signal = "arith_ci_en"
	SigLogicFunc  Signal = "logic_func"
	SigLogicSrFn  Signal = "logic_sr_func"
	SigShiftFunc  Signal = "shiftfunc"

	// SR/T
	SigSrSel  Signal = "sr_sel"
	SigTSel   Signal = "t_sel"

	// Memory access
	SigMaIssue     Signal = "ma_issue"
	SigMaWr        Signal = "ma_wr"
	SigMemSize     Signal = "mem_size"
	SigMemAddrSel  Signal = "mem_addr_sel"
	SigMemWdataSel Signal = "mem_wdata_sel"
	SigMemLock     Signal = "mem_lock"

	// MAC
	SigExWrmach     Signal = "ex_wrmach"
	SigWbWrmach     Signal = "wb_wrmach"
	SigExWrmacl     Signal = "ex_wrmacl"
	SigWbWrmacl     Signal = "wb_wrmacl"
	SigExMulcom1    Signal = "ex_mulcom1"
	SigWbMulcom1    Signal = "wb_mulcom1"
	SigExMulcom2    Signal = "ex_mulcom2"
	SigWbMulcom2    Signal = "wb_mulcom2"
	SigExMacsel1    Signal = "ex_macsel1"
	SigWbMacsel1    Signal = "wb_macsel1"
	SigExMacsel2    Signal = "ex_macsel2"
	SigWbMacsel2    Signal = "wb_macsel2"
	SigMacBusy      Signal = "mac_busy"
	SigMacStallSns  Signal = "mac_stall_sense"
	SigMacSLatch    Signal = "mac_s_latch"

	// PC / instruction-fetch
	SigIncPC      Signal = "incpc"
	SigIfIssue    Signal = "if_issue"
	SigIfAdsel    Signal = "ifadsel"
	SigDelayJump  Signal = "delay_jump"
	SigDispatch   Signal = "dispatch"
	SigIlevelCap  Signal = "ilevel_cap"
	SigEventAck0  Signal = "event_ack_0"
	SigMaskInt    Signal = "maskint_next"

	// Coprocessor / misc
	SigCopCmd     Signal = "coproc_cmd"
	SigCpuDataMux Signal = "cpu_data_mux"
	SigDebug      Signal = "debug"
	SigSlp        Signal = "slp"

	// Immediate value (special — its Value is an ImmVal tag like "IMM_P4")
	SigImmVal Signal = "imm_val"
)

// IsStdLogic reports whether a Signal represents a single-bit std_logic
// output (as opposed to an enum or vector). The set is canonical and
// must stay synchronized with decode_pkg.vhd's pipeline records: any
// signal whose VHDL declaration is std_logic belongs here. Used by
// both the simple-decoder RHS formatter (to quote values as '0'/'1')
// and the direct-decoder output-expression generator (to emit a flat
// "lhs <= '1' when ... else '0';").
func (s Signal) IsStdLogic() bool {
	switch s {
	case SigWrregZ, SigWrregW, SigWrpcZ, SigWrprPC, SigWrsrW, SigWrsrZ,
		SigArithCiEn, SigMaIssue, SigMaWr, SigMemLock,
		SigExWrmach, SigWbWrmach, SigExWrmacl, SigWbWrmacl,
		SigExMulcom1, SigWbMulcom1,
		SigMacStallSns, SigMacSLatch,
		SigIncPC, SigIfIssue, SigIfAdsel, SigDelayJump, SigDispatch,
		SigIlevelCap, SigEventAck0, SigMaskInt,
		SigDebug, SigSlp:
		return true
	}
	return false
}

// SignalDefault returns the default value to assign for a signal when
// no slot assignment names it. The direct decoder must explicitly
// drive every signal in every slot (it has no process-level default
// block like the simple decoder), so unset signals fold into a
// "default value" group during QMC reduction.
//
// Mirrors the Clojure generator's enum-default-value table + nillable
// outputs set (interface.clj lines 219–232, 405–416):
//   - std_logic signals default to "0".
//   - Enum signals default to the first literal in their enum.
//   - "Nillable" outputs (shiftfunc, imm_val, ma_wr, arith_func, etc.)
//     intentionally have NO default — leaving them undriven lets the
//     downstream logic ignore them when not relevant. SignalDefault
//     returns ("", false) for these.
func SignalDefault(s Signal) (string, bool) {
	// Nillable: skip — these outputs must NOT be force-defaulted, or
	// they would change behavior (e.g. xbus_sel=SEL_REG would create
	// false register-conflict stalls). Matches Clojure's
	// nillable-outputs set.
	switch s {
	case SigShiftFunc, SigImmVal, SigMaWr,
		SigArithFunc, SigArithSrFn,
		SigLogicFunc, SigLogicSrFn,
		SigZbusSel,
		SigMemAddrSel, SigMemSize, SigMemWdataSel,
		SigRegnumW, SigRegnumX, SigRegnumY, SigRegnumZ:
		return "", false
	}
	// std_logic signals default to '0'.
	if s.IsStdLogic() {
		return "0", true
	}
	// Enum first-literal defaults. Keep in sync with pkg.go enum
	// declarations.
	switch s {
	case SigXbusSel:
		return "SEL_IMM", true
	case SigYbusSel:
		return "SEL_IMM", true
	case SigAluinxSel:
		return "SEL_XBUS", true
	case SigAluinySel:
		return "SEL_YBUS", true
	case SigAluManip:
		return "SWAP_BYTE", true
	case SigSrSel:
		return "SEL_PREV", true
	case SigTSel:
		return "SEL_CLEAR", true
	case SigCopCmd:
		return "NOP", true
	case SigCpuDataMux:
		return "DBUS", true
	case SigExMulcom2, SigWbMulcom2:
		// mac_op_t — first literal is "NOP" (see pkg.go).
		return "NOP", true
	case SigExMacsel1, SigWbMacsel1:
		return "SEL_XBUS", true
	case SigExMacsel2, SigWbMacsel2:
		return "SEL_YBUS", true
	case SigMacBusy:
		// mac_busy_t first literal is NOT_BUSY (see Clojure
		// interface.clj line 189: [:mac-busy "mac_busy_t"
		// [:nop "NOT_BUSY"] ...]). Without this default, the QMC
		// grouping never sees a NOT_BUSY arm for non-MAC slots and
		// the direct decoder emits the wrong "when others" arm.
		return "NOT_BUSY", true
	}
	// Unknown enum: no default (would need explicit handling).
	return "", false
}

// SignalVHDLPath maps each Signal to the VHDL record-field path on
// the LHS of decoder assignments. Most signals map to ex.X or
// ex_stall.X depending on whether they're in the ex pipeline or
// the ex_stall variant; some go to id.X, wb.X, or wb_stall.X, or
// are scalar.
//
// This mapping is derived from decode_pkg.vhd record field placements
// (pipeline_ex_t, pipeline_ex_stall_t, pipeline_wb_t, pipeline_wb_stall_t,
// pipeline_id_t) and the genvhdl.clj name-alias table (~line 439-475).
//
// Keep this aligned with AllSignals:
// TestSignalVHDLPathCoversAllSignals enforces exhaustiveness.
var SignalVHDLPath = map[Signal]string{
	SigXbusSel:     "ex.xbus_sel",
	SigYbusSel:     "ex.ybus_sel",
	SigZbusSel:     "ex_stall.zbus_sel",
	SigRegnumX:     "ex.regnum_x",
	SigRegnumY:     "ex.regnum_y",
	SigRegnumZ:     "ex.regnum_z",
	SigRegnumW:     "wb.regnum_w",
	SigWrregZ:      "ex_stall.wrreg_z",
	SigWrregW:      "wb_stall.wrreg_w",
	SigWrpcZ:       "ex_stall.wrpc_z",
	SigWrprPC:      "ex_stall.wrpr_pc",
	SigWrsrW:       "wb_stall.wrsr_w",
	SigWrsrZ:       "ex_stall.wrsr_z",
	SigAluinxSel:   "ex.aluinx_sel",
	SigAluinySel:   "ex.aluiny_sel",
	SigAluManip:    "ex.alumanip",
	SigArithFunc:   "ex.arith_func",
	SigArithSrFn:   "ex.arith_sr_func",
	SigArithCiEn:   "ex.arith_ci_en",
	SigLogicFunc:   "ex.logic_func",
	SigLogicSrFn:   "ex.logic_sr_func",
	SigShiftFunc:   "ex_stall.shiftfunc",
	SigSrSel:       "ex_stall.sr_sel",
	SigTSel:        "ex_stall.t_sel",
	SigMaIssue:     "ex_stall.ma_issue",
	SigMaWr:        "ex.ma_wr",
	SigMemSize:     "ex.mem_size",
	SigMemAddrSel:  "ex_stall.mem_addr_sel",
	SigMemWdataSel: "ex_stall.mem_wdata_sel",
	SigMemLock:     "ex.mem_lock",
	SigExWrmach:    "ex_stall.wrmach",
	SigWbWrmach:    "wb_stall.wrmach",
	SigExWrmacl:    "ex_stall.wrmacl",
	SigWbWrmacl:    "wb_stall.wrmacl",
	SigExMulcom1:   "ex_stall.mulcom1",
	SigWbMulcom1:   "wb_stall.mulcom1",
	SigExMulcom2:   "ex_stall.mulcom2",
	SigWbMulcom2:   "wb_stall.mulcom2",
	SigExMacsel1:   "ex_stall.macsel1",
	SigWbMacsel1:   "wb_stall.macsel1",
	SigExMacsel2:   "ex_stall.macsel2",
	SigWbMacsel2:   "wb_stall.macsel2",
	SigMacBusy:     "mac_busy",      // top-level signal in arch, not record
	SigMacStallSns: "mac_stall_sense",
	SigMacSLatch:   "mac_s_latch",
	SigIncPC:       "id.incpc",
	SigIfIssue:     "id.if_issue",
	SigIfAdsel:     "id.ifadsel",
	SigDelayJump:   "delay_jump",
	SigDispatch:    "dispatch",
	SigIlevelCap:   "ilevel_cap",
	SigEventAck0:   "event_ack_0",
	SigMaskInt:     "maskint_next",
	SigCopCmd:      "ex.coproc_cmd",
	SigCpuDataMux:  "wb_stall.cpu_data_mux",
	SigDebug:       "debug",
	SigSlp:         "slp",
	SigImmVal:      "imm_enum", // local signal, set via with-select to ex.imm_val
}

// AllSignals lists every signal in a stable order. Tests use this
// for exhaustiveness checks. Order here is NOT the ROM bit-field
// order — that is dictated by CombinableSignals + alphabetical
// sort of standalone signals in CreateEncoding.
var AllSignals = []Signal{
	SigXbusSel, SigYbusSel, SigZbusSel,
	SigRegnumX, SigRegnumY, SigRegnumZ, SigRegnumW,
	SigWrregZ, SigWrregW, SigWrpcZ, SigWrprPC, SigWrsrW, SigWrsrZ,
	SigAluinxSel, SigAluinySel, SigAluManip,
	SigArithFunc, SigArithSrFn, SigArithCiEn,
	SigLogicFunc, SigLogicSrFn, SigShiftFunc,
	SigSrSel, SigTSel,
	SigMaIssue, SigMaWr, SigMemSize, SigMemAddrSel, SigMemWdataSel, SigMemLock,
	SigExWrmach, SigWbWrmach, SigExWrmacl, SigWbWrmacl,
	SigExMulcom1, SigWbMulcom1, SigExMulcom2, SigWbMulcom2,
	SigExMacsel1, SigWbMacsel1, SigExMacsel2, SigWbMacsel2,
	SigMacBusy, SigMacStallSns, SigMacSLatch,
	SigIncPC, SigIfIssue, SigIfAdsel, SigDelayJump, SigDispatch,
	SigIlevelCap, SigEventAck0, SigMaskInt,
	SigCopCmd, SigCpuDataMux, SigDebug, SigSlp,
	SigImmVal,
}
