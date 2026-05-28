package microcode

// CombinableGroup is one set of signals that share a bit-field in the
// ROM word. The signals in a group are packed together because their
// value-tuples across all slots are highly correlated. Groups in
// CombinableSignals are emitted in the order listed here; changing the
// order changes ROM bit-field positions and therefore ROM binary content.
type CombinableGroup []Signal

// CombinableSignals returns the combinable-group table for the given
// ROM width. Ported verbatim from cpugen.rom/combinable-signals
// (rom.clj lines 44-71). Panics on unsupported width.
//
// Bit layout: create-encoding emits standalone signals FIRST (getting
// the highest bit indices), then combinable groups in order (groups[0]
// gets the highest bits among the combinable region, groups[last] gets
// the lowest bits of the ROM word). This matches the golden
// decode_table_rom.vhd where line(2 downto 0) is the last group
// {wrpc_z,...} and standalone signals occupy the upper bits.
func CombinableSignals(width int) []CombinableGroup {
	switch width {
	case 64:
		return cs64
	case 72:
		return cs72
	}
	panic("microcode: unsupported ROM width")
}

// cs64 is the width-64 combinable-signals table.
// Ported from rom.clj lines 44-63.
// Clojure keywords map to Signal constants: kebab-case → snake_case.
var cs64 = []CombinableGroup{
	// #{:wrreg-w :wrreg-z :regnum-w :regnum-z}
	{SigWrregW, SigWrregZ, SigRegnumW, SigRegnumZ},
	// #{:alumanip :shiftfunc :arith-func :logic-func}
	{SigAluManip, SigShiftFunc, SigArithFunc, SigLogicFunc},
	// #{:sr-sel :t-sel :arith-sr-func :logic-sr-func}
	{SigSrSel, SigTSel, SigArithSrFn, SigLogicSrFn},
	// #{:regnum-x :xbus-sel :aluinx-sel}
	{SigRegnumX, SigXbusSel, SigAluinxSel},
	// #{:regnum-y :ybus-sel}
	{SigRegnumY, SigYbusSel},
	// #{:ma-issue :ma-wr :mem-size :mem-addr-sel :mem-wdata-sel}
	{SigMaIssue, SigMaWr, SigMemSize, SigMemAddrSel, SigMemWdataSel},
	// #{:ex-macsel1 :wb-macsel1 :ex-mulcom1 :wb-mulcom1 :ex-wrmacl :wb-wrmacl}
	{SigExMacsel1, SigWbMacsel1, SigExMulcom1, SigWbMulcom1, SigExWrmacl, SigWbWrmacl},
	// #{:ex-macsel2 :wb-macsel2 :ex-mulcom2 :wb-mulcom2 :ex-wrmach :wb-wrmach}
	{SigExMacsel2, SigWbMacsel2, SigExMulcom2, SigWbMulcom2, SigExWrmach, SigWbWrmach},
	// #{:if-issue :dispatch}
	{SigIfIssue, SigDispatch},
	// #{:wrpc-z :wrpr-pc :wrsr-w :wrsr-z}
	{SigWrpcZ, SigWrprPC, SigWrsrW, SigWrsrZ},
}

// cs72 is the width-72 combinable-signals table.
// Ported from rom.clj lines 65-71.
var cs72 = []CombinableGroup{
	// #{:alumanip :shiftfunc :arith-func :logic-func}
	{SigAluManip, SigShiftFunc, SigArithFunc, SigLogicFunc},
	// #{:sr-sel :t-sel :arith-sr-func :logic-sr-func}
	{SigSrSel, SigTSel, SigArithSrFn, SigLogicSrFn},
	// #{:regnum-y :ybus-sel :aluiny-sel}
	{SigRegnumY, SigYbusSel, SigAluinySel},
	// #{:ma-issue :ma-wr :mem-size} — note: :mem-addr-sel is commented out in Clojure
	{SigMaIssue, SigMaWr, SigMemSize},
	// #{:ex-macsel1 :wb-macsel1 :ex-mulcom1 :wb-mulcom1 :ex-wrmacl :wb-wrmacl}
	{SigExMacsel1, SigWbMacsel1, SigExMulcom1, SigWbMulcom1, SigExWrmacl, SigWbWrmacl},
	// #{:ex-macsel2 :wb-macsel2 :ex-mulcom2 :wb-mulcom2 :ex-wrmach :wb-wrmach}
	{SigExMacsel2, SigWbMacsel2, SigExMulcom2, SigWbMulcom2, SigExWrmach, SigWbWrmach},
	// #{:wrpc-z :wrpr-pc :wrsr-w :wrsr-z}
	{SigWrpcZ, SigWrprPC, SigWrsrW, SigWrsrZ},
}
