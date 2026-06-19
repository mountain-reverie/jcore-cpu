package microcode

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// AssignMap is the resolved canonical control-signal map for one slot.
// Keys are Signal constants; values are the VHDL enum literal or
// numeric constant the signal carries (as a string for unified storage).
// An absent key means the signal is unset (later treated as the nil
// encoding in CreateEncoding).
type AssignMap map[Signal]string

// AssignSlot resolves all canonical control signals for one (instr, slot)
// pair. The instr argument provides the Format string for register
// placement decisions (e.g., format "n" routes Rn to regnum_x, format
// "nm" routes Rn to regnum_x and Rm to regnum_y). Returns an error if
// a slot field carries an unrecognized value (e.g., xbus = "FROBNICATE").
//
// Port of cpugen.vhdlmicrocode/gen-assign-map (vhdlmicrocode.clj lines 288–290),
// which calls gen-assigns (lines 174–276).
func AssignSlot(instr spec.Instr, slot spec.Slot) (AssignMap, error) {
	out := AssignMap{}

	// Determine rn/rm register designators from format.
	// Per parser.clj: format "n","nd8","ni","nm","nmd" → Rn=RA; "nd4" → Rn=RB
	// format "m","md" → Rm=RA; "nm","nmd","md" → Rm=RB
	rn := rnRegister(instr.Format)
	rm := rmRegister(instr.Format)

	// Determine if alu_y is a constant (used to set aluiny_sel and imm_val).
	aluY := slot["alu_y"]
	aluYIsConst := isConstStr(aluY)

	// --- x-bus ---
	if v := slot["xbus"]; v != "" {
		if err := assignXBus(v, rn, rm, out); err != nil {
			return nil, fmt.Errorf("xbus: %w", err)
		}
	}

	// --- y-bus ---
	if v := slot["ybus"]; v != "" {
		if err := assignYBus(v, rn, rm, out); err != nil {
			return nil, fmt.Errorf("ybus: %w", err)
		}
	}

	// --- alu_x selector ---
	// Clojure: (when-let [x (:alux mc)] (ao :aluinx-sel x))
	if v := slot["alu_x"]; v != "" {
		sel, err := aluXSel(v)
		if err != nil {
			return nil, fmt.Errorf("alu_x: %w", err)
		}
		out[SigAluinxSel] = sel
	}

	// --- alu_y selector (imm path) ---
	// Clojure: (when aluy (ao :aluiny-sel aluy))
	// where aluy is :r0 or :imm (derived from whether the value is a const or "r0").
	if aluY != "" {
		if aluYIsConst {
			out[SigAluinySel] = "SEL_IMM"
		} else if strings.ToLower(aluY) == "r0" {
			out[SigAluinySel] = "SEL_R0"
		}
	}

	// --- direct field copies: arith, logic, shift, manip, zbus_sel, arith_sr, logic_sr, carryin_en ---
	if v := slot["arith"]; v != "" {
		out[SigArithFunc] = strings.ToUpper(v)
	}
	if v := slot["arith_sr"]; v != "" {
		sel, err := arithSrSel(v)
		if err != nil {
			return nil, fmt.Errorf("arith_sr: %w", err)
		}
		out[SigArithSrFn] = sel
	}
	if v := slot["logic"]; v != "" {
		sel, err := logicFuncSel(v)
		if err != nil {
			return nil, fmt.Errorf("logic: %w", err)
		}
		out[SigLogicFunc] = sel
	}
	if v := slot["logic_sr"]; v != "" {
		sel, err := logicSrSel(v)
		if err != nil {
			return nil, fmt.Errorf("logic_sr: %w", err)
		}
		out[SigLogicSrFn] = sel
	}
	if v := slot["manip"]; v != "" {
		sel, err := manipSel(v)
		if err != nil {
			return nil, fmt.Errorf("manip: %w", err)
		}
		out[SigAluManip] = sel
	}
	if v := slot["shift"]; v != "" {
		sel, err := shiftSel(v)
		if err != nil {
			return nil, fmt.Errorf("shift: %w", err)
		}
		out[SigShiftFunc] = sel
	}
	if v := slot["carryin_en"]; v != "" {
		if v == "1" {
			out[SigArithCiEn] = "1"
		} else {
			return nil, fmt.Errorf("carryin_en: unrecognized value %q", v)
		}
	}
	if v := slot["zbus_sel"]; v != "" {
		sel, err := zbusSel(v)
		if err != nil {
			return nil, fmt.Errorf("zbus_sel: %w", err)
		}
		out[SigZbusSel] = sel
	}

	// --- sr field ---
	// Clojure vhdlmicrocode.clj lines 214–219:
	//   (match [(:sr mc)]
	//     [[:t t]] (ao :sr-sel :set-t :t-sel t)
	//     [:wbus]  (ao :wrsr-w 1)
	//     [x]      (if (and x) (ao :sr-sel x)))
	if v := slot["sr"]; v != "" {
		if err := assignSR(v, out); err != nil {
			return nil, fmt.Errorf("sr: %w", err)
		}
	}

	// --- imm_val: collect from x, y, alu_y ---
	// Clojure lines 221–226: collects immediate value from x/y/aluy fields.
	// We parse the immediate using the format context (like Clojure's extract-imm)
	// to produce the canonical ImmVal literal (e.g., "IMM_U_8_0").
	immSrc := firstConstStr(slot["xbus"], slot["ybus"], aluY)
	if immSrc != "" {
		iv, ok := ParseImmToml(instr.Format, immSrc)
		if !ok {
			return nil, fmt.Errorf("imm_val: cannot parse %q with format %q", immSrc, instr.Format)
		}
		out[SigImmVal] = iv.Literal()
	}

	// --- MAC signals ---
	// Clojure lines 228–248: gen-mac
	if slot["mac_stage"] != "" {
		if err := assignMAC(slot, out); err != nil {
			return nil, fmt.Errorf("mac: %w", err)
		}
	}
	if slot["mac_stall_sense"] != "" {
		out[SigMacStallSns] = "1"
	}
	if slot["latch_s_mac"] != "" {
		out[SigMacSLatch] = "1"
	}

	// --- event ---
	// Clojure line 235–237: (when-let [event (:event mc)] (case event :ack (so :event-ack-0)))
	if v := slot["event"]; v != "" {
		if strings.ToLower(v) == "ack" {
			out[SigEventAck0] = "1"
		} else {
			return nil, fmt.Errorf("event: unrecognized value %q", v)
		}
	}

	// --- ilevel_capture ---
	// Clojure line 238–239: (when (:ilevel-capture mc) (so :ilevel-cap))
	if v := slot["ilevel_capture"]; v != "" {
		out[SigIlevelCap] = "1"
	}

	// --- mask_int ---
	// Clojure line 240–241: (when (:mask-int mc) (so :maskint-next))
	if v := slot["mask_int"]; v != "" {
		out[SigMaskInt] = "1"
	}

	// --- memory access ---
	// Clojure lines 243–246: (when-let [ma (:ma mc)] (gen-ma ma))
	if slot["ma_op"] != "" {
		if err := assignMA(slot, out); err != nil {
			return nil, fmt.Errorf("ma: %w", err)
		}
	}

	// --- ma_lock ---
	// Clojure line 245–246: (when (:ma-lock mc) (so :mem-lock))
	if slot["ma_lock"] != "" {
		out[SigMemLock] = "1"
	}

	// --- z-bus (write-back targets) ---
	if v := slot["zbus"]; v != "" {
		if err := assignZBus(v, rn, rm, out); err != nil {
			return nil, fmt.Errorf("zbus: %w", err)
		}
	}

	// --- pr field (PR = PC save) ---
	// Clojure lines 250–254:
	//   (when (= :pc (:pr mc))
	//     (concat ["PR = PC"] (ao :wrpr-pc 1 :wrreg-z 1 :regnum-z (second (register-map "pr")))))
	// register-map "pr" → (with-meta [:r 18] {:name "PR"}) → second is 18
	if v := slot["pr"]; v != "" {
		if strings.ToLower(v) == "rd pc" {
			out[SigWrprPC] = "1"
			out[SigWrregZ] = "1"
			out[SigRegnumZ] = "PR"
		} else {
			return nil, fmt.Errorf("pr: unrecognized value %q", v)
		}
	}

	// --- w-bus ---
	if v := slot["wbus"]; v != "" {
		if err := assignWBus(v, rn, rm, out); err != nil {
			return nil, fmt.Errorf("wbus: %w", err)
		}
	}

	// --- if_addy (ifadsel) ---
	// Clojure line 259: (when (= :z (:if-addr mc)) (so :ifadsel))
	if v := slot["if_addy"]; v != "" {
		if strings.ToUpper(v) == "ZBUS" {
			out[SigIfAdsel] = "1"
		} else {
			return nil, fmt.Errorf("if_addy: unrecognized value %q", v)
		}
	}

	// --- pc (incpc) ---
	// Clojure line 260: (when (:inc-pc mc) (so :incpc))
	// In the parser, :inc-pc is "inc" → true; "hold" → false.
	// In our TOML it's "INC" or "HOLD" (or absent = HOLD default).
	if v := slot["pc"]; v != "" {
		if strings.ToUpper(v) == "INC" {
			out[SigIncPC] = "1"
		}
		// "HOLD" and empty → no incpc signal set
	}

	// --- dispatch ---
	// Clojure line 263: (when-let [dispatch (:dispatch mc)] (ao :dispatch dispatch))
	// Values: yes/y→true, t, nt. In Clojure these are truthy dispatch values.
	if v := slot["dispatch"]; v != "" {
		sel, err := dispatchSel(v)
		if err != nil {
			return nil, fmt.Errorf("dispatch: %w", err)
		}
		out[SigDispatch] = sel
	}

	// --- debug ---
	// Clojure line 264: (when (:debug mc) (so :debug))
	if v := slot["debug"]; v != "" {
		out[SigDebug] = "1"
	}

	// --- if_issue ---
	// Clojure line 265: (when-let [issue (:if-issue mc)] (ao :if-issue issue))
	// Values in Clojure: yes/y→true, t, nt. In our TOML: "YES", "NO", "T", "NT".
	// "NO" is the default → no if_issue signal emitted.
	if v := slot["if_issue"]; v != "" {
		sel, err := ifIssueSel(v)
		if err != nil {
			return nil, fmt.Errorf("if_issue: %w", err)
		}
		if sel != "" {
			out[SigIfIssue] = sel
		}
	}

	// --- delay_jmp ---
	// Clojure line 268: (when (:delay-jump mc) (so :delay-jump))
	if v := slot["delay_jmp"]; v != "" {
		if strings.ToUpper(v) == "SET" {
			out[SigDelayJump] = "1"
		} else {
			return nil, fmt.Errorf("delay_jmp: unrecognized value %q", v)
		}
	}

	// --- halt ---
	// Clojure line 271: (when (:halt mc) (so :slp))
	if v := slot["halt"]; v != "" {
		if strings.ToUpper(v) == "SET" {
			out[SigSlp] = "1"
		} else {
			return nil, fmt.Errorf("halt: unrecognized value %q", v)
		}
	}

	// --- data_mux (cpu-data-mux) ---
	// Clojure line 272–273: (when-let [cd (:cpu-data-mux mc)] (ao :cpu-data-mux cd))
	if v := slot["data_mux"]; v != "" {
		sel, err := dataMuxSel(v)
		if err != nil {
			return nil, fmt.Errorf("data_mux: %w", err)
		}
		out[SigCpuDataMux] = sel
	}

	// --- coproc_cmd ---
	// Clojure line 274–275: (when-let [cmd (:coproc-cmd mc)] (ao :coproc-cmd cmd))
	if v := slot["coproc_cmd"]; v != "" {
		sel, err := coprocCmdSel(v)
		if err != nil {
			return nil, fmt.Errorf("coproc_cmd: %w", err)
		}
		out[SigCopCmd] = sel
	}

	return out, nil
}

// -----------------------------------------------------------------------
// Named-register helpers shared by all four bus-assignment functions.
// -----------------------------------------------------------------------

// namedRegs lists the canonical named registers handled identically by
// assignXBus, assignYBus, assignZBus, and assignWBus. Adding a new named
// register requires updating this slice, RegnumVHDL, and the VHDL enum —
// the bus functions themselves need no further edits.
var namedRegs = []string{"R0", "R15", "GBR", "VBR", "PR", "TEMP0", "TEMP1", "RBANK", "SPC", "SSR"}

// isNamedReg reports whether the (already upper-cased) value is one of
// the canonical named registers in namedRegs.
func isNamedReg(up string) bool {
	for _, r := range namedRegs {
		if r == up {
			return true
		}
	}
	return false
}

// setSelReg emits selSig=SEL_REG and regSig=name. Used by assignXBus and
// assignYBus where the bus selector is a SEL_REG mux choice.
func setSelReg(selSig, regSig Signal, name string, out AssignMap) {
	out[selSig] = "SEL_REG"
	out[regSig] = name
}

// setWriteReg emits wrSig="1" and regSig=name. Used by assignZBus and
// assignWBus where the bus selector is a write-enable flag (not SEL_REG).
func setWriteReg(wrSig, regSig Signal, name string, out AssignMap) {
	out[wrSig] = "1"
	out[regSig] = name
}

// -----------------------------------------------------------------------
// X-bus assignment (vhdlmicrocode.clj lines 33–46)
// -----------------------------------------------------------------------

// assignXBus ports the x-bus function:
//
//	[:r n] → SEL_REG + regnum-x = Rn constant name (R0, R15, named regs)
//	:rn    → SEL_REG + regnum-x = rn (format-dependent: RA or RB)
//	:rm    → SEL_REG + regnum-x = rm (format-dependent)
//	:pc    → SEL_PC
//	number/const → SEL_IMM
//	:w     → SEL_WBUS
func assignXBus(v, rn, rm string, out AssignMap) error {
	up := strings.ToUpper(v)
	switch {
	case up == "RN":
		out[SigXbusSel] = "SEL_REG"
		if rn != "" {
			out[SigRegnumX] = rn
		}
	case up == "RM":
		out[SigXbusSel] = "SEL_REG"
		if rm != "" {
			out[SigRegnumX] = rm
		}
	case isNamedReg(up):
		setSelReg(SigXbusSel, SigRegnumX, up, out)
	case up == "PC":
		out[SigXbusSel] = "SEL_PC"
	case up == "W":
		// :w → :wbus in Clojure x-bus
		out[SigXbusSel] = "SEL_WBUS"
	default:
		// Numeric immediate or structured immediate (e.g., "0", "4", "U*4", "S*2")
		if isConstStr(v) {
			out[SigXbusSel] = "SEL_IMM"
		} else {
			return fmt.Errorf("unrecognized value %q", v)
		}
	}
	return nil
}

// -----------------------------------------------------------------------
// Y-bus assignment (vhdlmicrocode.clj lines 48–59)
// -----------------------------------------------------------------------

// assignYBus ports the y-bus function:
//
//	[:r n] → SEL_REG + regnum-y = named reg
//	:rn    → SEL_REG + regnum-y = rn
//	:rm    → SEL_REG + regnum-y = rm
//	:pc,:mach,:macl,:sr → those named selectors
//	number/const → SEL_IMM
func assignYBus(v, rn, rm string, out AssignMap) error {
	up := strings.ToUpper(v)
	switch {
	case up == "RN":
		out[SigYbusSel] = "SEL_REG"
		if rn != "" {
			out[SigRegnumY] = rn
		}
	case up == "RM":
		out[SigYbusSel] = "SEL_REG"
		if rm != "" {
			out[SigRegnumY] = rm
		}
	case isNamedReg(up):
		setSelReg(SigYbusSel, SigRegnumY, up, out)
	case up == "PC":
		out[SigYbusSel] = "SEL_PC"
	case up == "MACH":
		out[SigYbusSel] = "SEL_MACH"
	case up == "MACL":
		out[SigYbusSel] = "SEL_MACL"
	case up == "SR":
		out[SigYbusSel] = "SEL_SR"
	case up == "EXPEVT":
		// SH-4 cause-register read (J4): STC EXPEVT/INTEVT/TRA, Rn.
		out[SigYbusSel] = "SEL_EXPEVT"
	case up == "INTEVT":
		out[SigYbusSel] = "SEL_INTEVT"
	case up == "TRA":
		out[SigYbusSel] = "SEL_TRA"
	case up == "PTEH" || up == "PTEL" || up == "ASIDR":
		// SH-4 MMU register read (J4 + MMU_ARCH): consolidated ybus source
		// SEL_MMU, sub-selected by mmu_reg_sel. STC PTEH/PTEL/ASIDR, Rn.
		out[SigYbusSel] = "SEL_MMU"
		out[SigMmuRegSel] = "SEL_" + up
	default:
		if isConstStr(v) {
			out[SigYbusSel] = "SEL_IMM"
		} else {
			return fmt.Errorf("unrecognized value %q", v)
		}
	}
	return nil
}

// -----------------------------------------------------------------------
// Z-bus write-back (vhdlmicrocode.clj lines 61–75)
// -----------------------------------------------------------------------

// assignZBus ports the z-bus function, which controls where Z-bus results
// are written back. It produces wrreg_z/wrpc_z/wrsr_z and regnum_z signals.
//
//	[:r n] → wrreg-z=1, regnum-z=n
//	:rn    → wrreg-z=1, regnum-z=rn
//	:rm    → wrreg-z=1, regnum-z=rm
//	:pc    → wrpc-z=1
//	:pc-t  → wrpc-z=T
//	:pc-nt → wrpc-z=NT
//	:sr    → wrsr-z=1
//	Also handles :ybus and :wbus for zbus_sel-only cases (no register write).
func assignZBus(v, rn, rm string, out AssignMap) error {
	up := strings.ToUpper(v)
	switch {
	case up == "RN":
		out[SigWrregZ] = "1"
		if rn != "" {
			out[SigRegnumZ] = rn
		}
	case up == "RM":
		out[SigWrregZ] = "1"
		if rm != "" {
			out[SigRegnumZ] = rm
		}
	case up == "PTEH" || up == "PTEL" || up == "ASIDR":
		// SH-4 MMU register write (J4 + MMU_ARCH): latch zbus into the addressed
		// MMU flop. NOT a regfile write — no wrreg_z. LDC Rm,PTEH/PTEL/ASIDR.
		out[SigMmuRegWr] = "1"
		out[SigMmuRegSel] = "SEL_" + up
	case isNamedReg(up):
		setWriteReg(SigWrregZ, SigRegnumZ, up, out)
	case up == "PC":
		out[SigWrpcZ] = "1"
	case up == "T(PC)":
		out[SigWrpcZ] = "t_bcc"
	case up == "NT(PC)":
		out[SigWrpcZ] = "not t_bcc"
	case up == "SR":
		out[SigWrsrZ] = "1"
	// Y / W: these appear as zbus values meaning "pass ybus/wbus through to
	// Z result" — handled only through zbus_sel; no register write-back.
	case up == "Y", up == "W":
		// No wrreg_z — zbus_sel handles routing; value already set by zbus_sel field.
	default:
		return fmt.Errorf("unrecognized value %q", v)
	}
	return nil
}

// -----------------------------------------------------------------------
// W-bus write-back (vhdlmicrocode.clj lines 77–88)
// -----------------------------------------------------------------------

// assignWBus ports the w-bus function:
//
//	[:r n] → wrreg-w=1, regnum-w=n
//	:rn    → wrreg-w=1, regnum-w=rn
//	:rm    → wrreg-w=1, regnum-w=rm
//	:pc    → wrpc-z=1 (note: Clojure maps :pc in w-bus to :wrpc-z)
func assignWBus(v, rn, rm string, out AssignMap) error {
	up := strings.ToUpper(v)
	switch {
	case up == "RN":
		out[SigWrregW] = "1"
		if rn != "" {
			out[SigRegnumW] = rn
		}
	case up == "RM":
		out[SigWrregW] = "1"
		if rm != "" {
			out[SigRegnumW] = rm
		}
	case isNamedReg(up):
		setWriteReg(SigWrregW, SigRegnumW, up, out)
	case up == "SR":
		out[SigWrsrW] = "1"
	case up == "PC":
		// Clojure w-bus: [:pc] → [:wrpc-z nil] → [sig 1] with no num
		out[SigWrpcZ] = "1"
	default:
		return fmt.Errorf("unrecognized value %q", v)
	}
	return nil
}

// -----------------------------------------------------------------------
// SR field (vhdlmicrocode.clj lines 214–219)
// -----------------------------------------------------------------------

// assignSR handles the sr field:
//
//	"T=0" → sr_sel=SEL_SET_T, t_sel=SEL_CLEAR
//	"T=1" → sr_sel=SEL_SET_T, t_sel=SEL_SET
//	"CARRY" → sr_sel=SEL_SET_T, t_sel=SEL_CARRY    (shift T)
//	"SHIFT" → same (from Clojure :shift SR case)
//	"W" → wrsr_w=1
//	"ARITH" → sr_sel=SEL_ARITH
//	"LOGIC" → sr_sel=SEL_LOGIC
//	"Z" → sr_sel=SEL_ZBUS
//	"DIV0U" → sr_sel=SEL_DIV0U
//	"INT_MASK" → sr_sel=SEL_INT_MASK
//	(DIV0S/DIV1 are not sr values — they live in arith_sr,
//	 producing arith_sr_func=DIV0S/DIV1.)
//	"HOLD" or "" → nothing (hold current SR)
//
// Clojure parser.clj lines 276–285:
//
//	:sr {"arith" :arith "logic" :logic "z" :zbus "w" :wbus "div0u" :div0u
//	     "int_mask" :int-mask "t=0" [:t :clear] "t=1" [:t :set]
//	     "shift" [:t :shift] "carry" [:t :carry]}
//
// vhdlmicrocode.clj lines 214–219:
//
//	(match [(:sr mc)]
//	  [[:t t]] (ao :sr-sel :set-t :t-sel t)
//	  [:wbus]  (ao :wrsr-w 1)
//	  [x]      (if (and x) (ao :sr-sel x)))
func assignSR(v string, out AssignMap) error {
	switch strings.ToUpper(v) {
	case "T=0":
		out[SigSrSel] = "SEL_SET_T"
		out[SigTSel] = "SEL_CLEAR"
	case "T=1":
		out[SigSrSel] = "SEL_SET_T"
		out[SigTSel] = "SEL_SET"
	case "CARRY":
		// Clojure: "carry" → [:t :carry] → sr-sel=set-t, t-sel=carry
		out[SigSrSel] = "SEL_SET_T"
		out[SigTSel] = "SEL_CARRY"
	case "SHIFT":
		// Clojure: "shift" → [:t :shift] → sr-sel=set-t, t-sel=shift
		out[SigSrSel] = "SEL_SET_T"
		out[SigTSel] = "SEL_SHIFT"
	case "W":
		// Clojure: :wbus → wrsr-w=1
		out[SigWrsrW] = "1"
	case "ARITH":
		out[SigSrSel] = "SEL_ARITH"
	case "LOGIC":
		out[SigSrSel] = "SEL_LOGIC"
	case "Z":
		out[SigSrSel] = "SEL_ZBUS"
	case "DIV0U":
		out[SigSrSel] = "SEL_DIV0U"
	case "INT_MASK":
		out[SigSrSel] = "SEL_INT_MASK"
	case "EXCEPTION":
		// SH-4 exception entry: set MD/RB/BL (interrupt mask handled separately
		// via INT_MASK for interrupts).
		out[SigSrSel] = "SEL_EXCEPTION"
	case "EXPEVT":
		// SH-4 cause capture: latch the slot immediate into EXPEVT (J4).
		out[SigSrSel] = "SEL_EXPEVT"
	case "INTEVT":
		out[SigSrSel] = "SEL_INTEVT"
	case "TRA":
		out[SigSrSel] = "SEL_TRA"
	case "HOLD", "":
		// HOLD means don't change SR — no signals emitted.
	default:
		return fmt.Errorf("unrecognized value %q", v)
	}
	return nil
}

// -----------------------------------------------------------------------
// Memory access (vhdlmicrocode.clj lines 150–172, gen-ma)
// -----------------------------------------------------------------------

// assignMA ports gen-ma:
//
//	ma_op:   "READ" → ma_issue=true, ma_wr=0; "WRITE" → ma_issue=true, ma_wr=1
//	ma_addy: "XBUS"→mem_addr_sel=SEL_XBUS, "ZBUS"→SEL_ZBUS, "YBUS"→SEL_YBUS
//	ma_data: "YBUS"→mem_wdata_sel=SEL_YBUS, "ZBUS"→SEL_ZBUS (only for writes)
//	ma_size: "8"→BYTE, "16"→WORD, "32"→LONG
//	ma_mask: "T"→ma_issue=T, "NT"→ma_issue=NT (conditional memory access)
func assignMA(slot spec.Slot, out AssignMap) error {
	op := strings.ToUpper(slot["ma_op"])
	switch op {
	case "READ":
		// ma_issue is set below (may be masked), ma_wr=0
		out[SigMaWr] = "0"
	case "WRITE":
		out[SigMaWr] = "1"
	default:
		return fmt.Errorf("ma_op: unrecognized value %q", slot["ma_op"])
	}

	// ma_mask controls conditionality of ma_issue
	// Clojure: (ao :ma-issue (or (:mask ma) true))
	// :t → "T", :nt → "NT", nil/absent → true → "1"
	mask := strings.ToUpper(slot["ma_mask"])
	switch mask {
	case "T":
		out[SigMaIssue] = "t_bcc"
	case "NT":
		out[SigMaIssue] = "not t_bcc"
	default:
		out[SigMaIssue] = "1"
	}

	// ma_addy → mem_addr_sel
	addy := strings.ToUpper(slot["ma_addy"])
	switch addy {
	case "XBUS":
		out[SigMemAddrSel] = "SEL_XBUS"
	case "ZBUS":
		out[SigMemAddrSel] = "SEL_ZBUS"
	case "YBUS":
		out[SigMemAddrSel] = "SEL_YBUS"
	default:
		if addy != "" {
			return fmt.Errorf("ma_addy: unrecognized value %q", slot["ma_addy"])
		}
	}

	// ma_data → mem_wdata_sel (only for writes, but we don't enforce that here)
	data := strings.ToUpper(slot["ma_data"])
	switch data {
	case "YBUS":
		out[SigMemWdataSel] = "SEL_YBUS"
	case "ZBUS":
		out[SigMemWdataSel] = "SEL_ZBUS"
	case "":
		// no data selector
	default:
		return fmt.Errorf("ma_data: unrecognized value %q", slot["ma_data"])
	}

	// ma_size → mem_size
	size := slot["ma_size"]
	switch size {
	case "8":
		out[SigMemSize] = "BYTE"
	case "16":
		out[SigMemSize] = "WORD"
	case "32":
		out[SigMemSize] = "LONG"
	default:
		if size != "" {
			return fmt.Errorf("ma_size: unrecognized value %q", size)
		}
	}

	return nil
}

// -----------------------------------------------------------------------
// MAC signals (vhdlmicrocode.clj lines 118–148, gen-mac)
// -----------------------------------------------------------------------

// assignMAC ports gen-mac. The MAC stage prefix ("ex" or "wb") selects
// which set of mac control signals to emit.
//
// Clojure gen-mac:
//   - mac_stage → stage prefix (ex/wb)
//   - mac_op    → determines mulcom2 value + macsel1/macsel2
//   - macin_1   → macsel1 value (xbus/zbus/wbus)
//   - macin_2   → macsel2 value (ybus/zbus/wbus)
//   - mach/macl → wrmach/wrmacl (LOAD or CLEAR both write)
//   - mac_busy  → mac_busy signal
func assignMAC(slot spec.Slot, out AssignMap) error {
	stage := strings.ToLower(slot["mac_stage"])
	var (
		sigMacsel1 Signal
		sigMacsel2 Signal
		sigMulcom1 Signal
		sigMulcom2 Signal
		sigWrmacl  Signal
		sigWrmach  Signal
		sigMacBusy Signal
	)
	switch stage {
	case "ex":
		sigMacsel1 = SigExMacsel1
		sigMacsel2 = SigExMacsel2
		sigMulcom1 = SigExMulcom1
		sigMulcom2 = SigExMulcom2
		sigWrmacl = SigExWrmacl
		sigWrmach = SigExWrmach
		sigMacBusy = SigMacBusy
	case "wb":
		sigMacsel1 = SigWbMacsel1
		sigMacsel2 = SigWbMacsel2
		sigMulcom1 = SigWbMulcom1
		sigMulcom2 = SigWbMulcom2
		sigWrmacl = SigWbWrmacl
		sigWrmach = SigWbWrmach
		sigMacBusy = SigMacBusy
	default:
		return fmt.Errorf("mac_stage: unrecognized value %q", slot["mac_stage"])
	}

	// mac_op → mulcom2 value + (determines whether mulcom1 is set)
	// Clojure gen-mac:
	//   (when-let [macin1 (:in1 mac)]
	//     (concat (ao macsel1 ...) (when-not (#{:clear :load} (:h mac)) (ao mulcom1 1))))
	//   (when-let [macin2 (:in2 mac)]
	//     (concat (ao macsel2 ...) (when-let [op (:op mac)] (ao mulcom2 op))))
	//
	// mac_op maps to :op in the mac struct:
	//   :macl → MAC.L (word), :macw → MAC.W, :dmulsl/:dmulul → double mul,
	//   :mull/:mulsw/:muluw → single mul

	macOp := strings.ToUpper(slot["mac_op"])
	var mulcom2Val string
	switch macOp {
	case "MACL":
		mulcom2Val = "MACL"
	case "MACW":
		mulcom2Val = "MACW"
	case "DMULSL":
		mulcom2Val = "DMULSL"
	case "DMULUL":
		mulcom2Val = "DMULUL"
	case "MULL":
		mulcom2Val = "MULL"
	case "MULSW":
		mulcom2Val = "MULSW"
	case "MULUW":
		mulcom2Val = "MULUW"
	case "":
		// No mac_op → no mulcom2
	default:
		return fmt.Errorf("mac_op: unrecognized value %q", slot["mac_op"])
	}

	// macin_1 (in1): sets macsel1 and mulcom1
	// Clojure: macin1 "xbus"→:x→:xbus, "wbus"→:w→:wbus, "zbus"→:z→:zbus
	// "when-not (#{:clear :load} (:h mac)) (ao mulcom1 1)" → mulcom1=1 unless mach is clear/load
	if macin1 := strings.ToUpper(slot["macin_1"]); macin1 != "" {
		var sel string
		switch macin1 {
		case "XBUS":
			sel = "SEL_XBUS"
		case "WBUS":
			sel = "SEL_WBUS"
		case "ZBUS":
			sel = "SEL_ZBUS"
		default:
			return fmt.Errorf("macin_1: unrecognized value %q", slot["macin_1"])
		}
		out[sigMacsel1] = sel
		// mulcom1=1 unless mach is "CLEAR" or "LOAD"
		mach := strings.ToUpper(slot["mach"])
		if mach != "CLEAR" && mach != "LOAD" {
			out[sigMulcom1] = "1"
		}
	}

	// macin_2 (in2): sets macsel2 and mulcom2
	if macin2 := strings.ToUpper(slot["macin_2"]); macin2 != "" {
		var sel string
		switch macin2 {
		case "YBUS":
			sel = "SEL_YBUS"
		case "WBUS":
			sel = "SEL_WBUS"
		case "ZBUS":
			sel = "SEL_ZBUS"
		default:
			return fmt.Errorf("macin_2: unrecognized value %q", slot["macin_2"])
		}
		out[sigMacsel2] = sel
		if mulcom2Val != "" {
			out[sigMulcom2] = mulcom2Val
		}
	}

	// mach/macl → wrmach/wrmacl
	// Clojure: (when (#{:clear :load} (:l mac)) (so wrmacl))
	//          (when (#{:clear :load} (:h mac)) (so wrmach))
	mach := strings.ToUpper(slot["mach"])
	if mach == "CLEAR" || mach == "LOAD" {
		out[sigWrmach] = "1"
	}
	macl := strings.ToUpper(slot["macl"])
	if macl == "CLEAR" || macl == "LOAD" {
		out[sigWrmacl] = "1"
	}

	// mac_busy
	// Clojure: (when-let [busy (:busy mac)] (ao :mac-busy [stage busy]))
	// The value is stage-qualified: e.g. EX_NOT_STALL, WB_BUSY.
	// mac_busy "busy" → :busy → "BUSY", "not stall" → :not-stall → "NOT_STALL"
	if busy := strings.ToLower(slot["mac_busy"]); busy != "" {
		var busySuffix string
		switch busy {
		case "busy":
			busySuffix = "BUSY"
		case "not stall":
			busySuffix = "NOT_STALL"
		default:
			return fmt.Errorf("mac_busy: unrecognized value %q", slot["mac_busy"])
		}
		out[sigMacBusy] = strings.ToUpper(stage) + "_" + busySuffix
	}

	return nil
}

// -----------------------------------------------------------------------
// Direct-value translators for ALU and dispatch fields
// -----------------------------------------------------------------------

// aluXSel translates alu_x field values.
// Clojure parser.clj: :alux {"fc" :fc, "rotcl" :rotcl, "zero" :zero}
// vhdlmicrocode.clj: (when-let [x (:alux mc)] (ao :aluinx-sel x))
func aluXSel(v string) (string, error) {
	switch strings.ToUpper(v) {
	case "FC":
		return "SEL_FC", nil
	case "ROTCL":
		return "SEL_ROTCL", nil
	case "ZERO":
		return "SEL_ZERO", nil
	default:
		return "", fmt.Errorf("unrecognized value %q", v)
	}
}

// arithSrSel translates arith_sr field values.
// Clojure: :arith-sr → :arith-sr-func signal
// Values: "ugrter_eq"/">="→u>=, "sgrter_eq"/"s>="→s>=, "ugrter"/">"→u>,
//
//	"sgrter"/"s>"→s>, "zero"→zero, "overunderflow"→overunderflow,
//	"div0s"→div0s, "div1"→div1
func arithSrSel(v string) (string, error) {
	// Return values must be valid VHDL enum literals of arith_sr_func_t
	// (declared in core/components_pkg.vhd): ZERO, OVERUNDERFLOW,
	// UGRTER_EQ, SGRTER_EQ, UGRTER, SGRTER, DIV0S, DIV1.
	switch strings.ToUpper(v) {
	case "UGRTER_EQ", ">=":
		return "UGRTER_EQ", nil
	case "SGRTER_EQ", "S>=":
		return "SGRTER_EQ", nil
	case "UGRTER", ">":
		return "UGRTER", nil
	case "SGRTER", "S>":
		return "SGRTER", nil
	case "ZERO":
		return "ZERO", nil
	case "OVERUNDERFLOW":
		return "OVERUNDERFLOW", nil
	case "DIV0S":
		return "DIV0S", nil
	case "DIV1":
		return "DIV1", nil
	default:
		return "", fmt.Errorf("unrecognized value %q", v)
	}
}

// logicSrSel translates logic_sr field values.
// Clojure: :logic-sr {"byte_eq" :b=, "byte =" :b=, "byte=" :b=, "zero" :zero}
// logicFuncSel translates `logic` field values to VHDL logic_func_t
// enum literals (core/components_pkg.vhd): LOGIC_NOT, LOGIC_AND,
// LOGIC_OR, LOGIC_XOR. Raw upper-cased values like "AND" would clash
// with VHDL reserved keywords; the LOGIC_ prefix avoids that.
func logicFuncSel(v string) (string, error) {
	switch strings.ToUpper(v) {
	case "AND":
		return "LOGIC_AND", nil
	case "OR":
		return "LOGIC_OR", nil
	case "XOR":
		return "LOGIC_XOR", nil
	case "NOT":
		return "LOGIC_NOT", nil
	default:
		return "", fmt.Errorf("unrecognized value %q", v)
	}
}

func logicSrSel(v string) (string, error) {
	// Return values must be valid VHDL enum literals of logic_sr_func_t
	// (core/components_pkg.vhd): ZERO, BYTE_EQ.
	switch strings.ToUpper(v) {
	case "BYTE_EQ", "BYTE =", "BYTE=":
		return "BYTE_EQ", nil
	case "ZERO":
		return "ZERO", nil
	default:
		return "", fmt.Errorf("unrecognized value %q", v)
	}
}

// manipSel translates manip field values.
// Clojure parser.clj lines 313–322:
//
//	"xtract" → :xtract, "set b7" → :bit7
//	"ext sb" → [:ext :sb], "ext sw" → [:ext :sw]
//	"ext ub" → [:ext :ub], "ext uw" → [:ext :uw]
//	"swap b" → [:swap :b], "swap w" → [:swap :w]
//	etc. (regex match: "(ext|swap) *([a-z]+[0-9]*)?")
func manipSel(v string) (string, error) {
	// Return values must be valid VHDL enum literals of alumanip_t
	// (core/components_pkg.vhd): SWAP_BYTE, SWAP_WORD, EXTEND_UBYTE,
	// EXTEND_UWORD, EXTEND_SBYTE, EXTEND_SWORD, EXTRACT, SET_BIT_7.
	switch strings.ToLower(v) {
	case "xtract":
		return "EXTRACT", nil
	case "set b7":
		return "SET_BIT_7", nil
	case "ext sb":
		return "EXTEND_SBYTE", nil
	case "ext sw":
		return "EXTEND_SWORD", nil
	case "ext ub":
		return "EXTEND_UBYTE", nil
	case "ext uw":
		return "EXTEND_UWORD", nil
	case "swapb":
		return "SWAP_BYTE", nil
	case "swapw":
		return "SWAP_WORD", nil
	default:
		return "", fmt.Errorf("unrecognized value %q", v)
	}
}

// shiftSel translates shift field values.
// Clojure: :shift {"rotate" :rotate, "rotatec" :rotatec, "shiftl" :logic, "shifta" :arith}
func shiftSel(v string) (string, error) {
	// Return values must be valid VHDL enum literals of shiftfunc_t
	// (core/components_pkg.vhd): LOGIC, ARITH, ROTATE, ROTC.
	switch strings.ToLower(v) {
	case "rotate":
		return "ROTATE", nil
	case "rotatec":
		return "ROTC", nil
	case "shiftl":
		return "LOGIC", nil
	case "shifta":
		return "ARITH", nil
	default:
		return "", fmt.Errorf("unrecognized value %q", v)
	}
}

// zbusSel translates zbus_sel field values (TOML "ZBUS SEL" column).
// Clojure parser.clj lines 270–275:
//
//	"arith" → :arith, "logic" → :logic, "shift" → :shift,
//	"manip" → :manip, "y" → :ybus, "w" → :wbus
//
// vhdlmicrocode.clj: (ao v :zbus-sel)
func zbusSel(v string) (string, error) {
	switch strings.ToUpper(v) {
	case "ARITH":
		return "SEL_ARITH", nil
	case "LOGIC":
		return "SEL_LOGIC", nil
	case "SHIFT":
		return "SEL_SHIFT", nil
	case "MANIP":
		return "SEL_MANIP", nil
	case "Y":
		return "SEL_YBUS", nil
	case "W":
		return "SEL_WBUS", nil
	default:
		return "", fmt.Errorf("unrecognized value %q", v)
	}
}

// dispatchSel translates dispatch field values to VHDL expression text
// for the RHS of `dispatch <= ...`. "YES" → "1" (signalRHS quotes it
// as '1'); "T" → "t_bcc" (a bare VHDL expression); "NT" → "not t_bcc".
func dispatchSel(v string) (string, error) {
	switch strings.ToUpper(v) {
	case "YES", "Y":
		return "1", nil
	case "T":
		return "t_bcc", nil
	case "NT":
		return "not t_bcc", nil
	default:
		return "", fmt.Errorf("unrecognized value %q", v)
	}
}

// ifIssueSel translates if_issue field values. Same value space as
// dispatch ("YES", "T", "NT"); plus "NO" → empty (no signal emitted).
func ifIssueSel(v string) (string, error) {
	switch strings.ToUpper(v) {
	case "YES", "Y":
		return "1", nil
	case "T":
		return "t_bcc", nil
	case "NT":
		return "not t_bcc", nil
	case "NO":
		return "", nil // suppress
	default:
		return "", fmt.Errorf("unrecognized value %q", v)
	}
}

// dataMuxSel translates data_mux field values.
// Clojure: :cpu-data-mux {"dbus" :dbus, "coproc" :coproc}
func dataMuxSel(v string) (string, error) {
	switch strings.ToUpper(v) {
	case "DBUS":
		return "DBUS", nil
	case "COPROC":
		return "COPROC", nil
	default:
		return "", fmt.Errorf("unrecognized value %q", v)
	}
}

// coprocCmdSel translates coproc_cmd field values.
// Clojure: :coproc-cmd {"nop" :nop, "lds" :lds, "sts" :sts, "clds" :clds, "csts" :sts}
func coprocCmdSel(v string) (string, error) {
	switch strings.ToUpper(v) {
	case "NOP":
		return "NOP", nil
	case "LDS":
		return "LDS", nil
	case "STS":
		return "STS", nil
	case "CLDS":
		return "CLDS", nil
	case "CSTS":
		// Note: Clojure maps "csts" → :sts (not :csts!)
		return "STS", nil
	default:
		return "", fmt.Errorf("unrecognized value %q", v)
	}
}

// -----------------------------------------------------------------------
// Register placement helpers
// -----------------------------------------------------------------------

// rnRegister returns the regnum designator for Rn under the given format.
// Per parser.clj:
//
//	format "n", "nd8", "ni", "nm", "nmd" (and "mn" alias) → high nibble = RA
//	format "nd4" → Rn is in the low nibble = RB
//	format "" or formats without Rn (e.g., "m", "md", "d8", "d12", "i8", "0") → "" (absent)
//
// namedRegVHDL maps each named register to its VHDL std_logic_vector(4 downto 0)
// literal. This is the single source of truth shared by RegnumVHDL and the
// namedRegs slice; tests validate that every entry in namedRegs has an entry here.
// Per parser.clj's register-map:
//
//	R0   → "00000" (decimal 0)
//	R15  → "01111" (decimal 15)
//	GBR  → "10000" (decimal 16)
//	VBR  → "10001" (decimal 17)
//	PR   → "10010" (decimal 18)
//	TEMP0→ "10011" (decimal 19)
//	TEMP1→ "10100" (decimal 20)
var namedRegVHDL = map[string]string{
	"R0":    `"00000"`,
	"R15":   `"01111"`,
	"GBR":   `"10000"`,
	"VBR":   `"10001"`,
	"PR":    `"10010"`,
	"TEMP0": `"10011"`,
	"TEMP1": `"10100"`,
	"SPC":   `"10101"`, // 21 — saved PC (J4 exception model; unbanked "10xxx")
	"SSR":   `"10110"`, // 22 — saved SR
}

// RegnumVHDL translates a regnum tag to the VHDL std_logic_vector(4 downto 0)
// expression naming that register.
//
// RA and RB are opcode-slice extractions: RA = high nibble (Rn in
// most formats), RB = low nibble (Rm in nm/md/nmd, Rn in nd4).
// rnRegister/rmRegister already collapsed format → nibble before
// tagging with RA/RB, so this helper is format-independent.
func RegnumVHDL(tag string) string {
	switch tag {
	case "":
		return ""
	case "RA":
		return "'0' & op.code(11 downto 8)"
	case "RB":
		return "'0' & op.code(7 downto 4)"
	case "RBANK":
		// R*_BANK: inactive-bank GPR, number in opcode[6:4]; bank-1 region = 24-31
		return `"11" & op.code(6 downto 4)`
	}
	if v, ok := namedRegVHDL[tag]; ok {
		return v
	}
	return tag // unrecognized — leave as-is so caller-side errors surface
}

func rnRegister(format string) string {
	switch format {
	case "n", "nd8", "ni", "nm", "nmd", "mn":
		return "RA"
	case "nd4":
		return "RB"
	default:
		// "m", "md", "d8", "d12", "i8", "0", "" and any other → no Rn
		return ""
	}
}

// rmRegister returns the regnum designator for Rm under the given format.
// Per parser.clj:
//
//	format "nm", "md", "nmd" → Rm is in the low nibble = RB
//	format "m" → Rm is in high nibble = RA
//	format "" or formats without Rm (e.g., "n", "nd8", etc.) → "" (absent)
func rmRegister(format string) string {
	switch format {
	case "m":
		return "RA"
	case "md", "nm", "nmd", "mn":
		return "RB"
	default:
		// "n", "nd8", "ni", "nd4", "d8", "d12", "i8", "0", "" and any other → no Rm
		return ""
	}
}

// -----------------------------------------------------------------------
// Immediate-value helpers
// -----------------------------------------------------------------------

// isConstStr reports whether the TOML string v encodes a numeric constant
// or a structured immediate (like "U*4", "S*2", "U", "S", "0", "4", "-8").
// Mirrors Clojure's parse-const function from parser.clj lines 146–156.
func isConstStr(v string) bool {
	if v == "" {
		return false
	}
	// Numeric literal: optional sign, optional "0x"/"0b" prefix, digits.
	if _, err := strconv.ParseInt(v, 10, 64); err == nil {
		return true
	}
	// Structured: "U", "S", "U*N", "S*N", "N*U", "N*S"
	up := strings.ToUpper(v)
	if up == "U" || up == "S" {
		return true
	}
	// "U*N" or "S*N"
	for _, prefix := range []string{"U*", "S*"} {
		if strings.HasPrefix(up, prefix) {
			_, err := strconv.Atoi(up[len(prefix):])
			if err == nil {
				return true
			}
		}
	}
	return false
}

// firstConstStr returns the first non-empty const-valued string from the
// given candidates (x, y, aluy fields). Mirrors the Clojure logic in
// gen-assigns lines 221–226: (some #(match...) ((juxt :x :y :aluy) mc)).
func firstConstStr(candidates ...string) string {
	for _, c := range candidates {
		if isConstStr(c) {
			return c
		}
	}
	return ""
}
