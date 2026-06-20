package model

import (
	"fmt"
	"math/bits"
	"sort"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/logic"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/microcode"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/opcode"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// addrBitsForSlots returns the microcode address width for a microcode of
// numSlots used slots. We need 2^addrBits > numSlots so the all-ones address
// stays a reserved, unused slot (the predecode "unknown opcode" sentinel),
// i.e. addrBits >= bits.Len(numSlots). Floored at 8 to keep the existing
// 8-bit decoders byte-identical.
func addrBitsForSlots(numSlots int) int {
	return max(8, bits.Len(uint(numSlots)))
}

// setOperationAddrWidth rewrites the operation_t.addr field type to a
// std_logic_vector of the given microcode address width. It errors if the
// operation_t.addr field is absent, so a rename of the record or field can't
// silently leave the emitted address width wrong.
func setOperationAddrWidth(pkg *Package, addrBits int) error {
	for ri := range pkg.Records {
		if pkg.Records[ri].Name != "operation_t" {
			continue
		}
		for fi := range pkg.Records[ri].Fields {
			f := &pkg.Records[ri].Fields[fi]
			if len(f.Names) == 1 && f.Names[0] == "addr" {
				f.Type = fmt.Sprintf("std_logic_vector(%d downto 0)", addrBits-1)
				return nil
			}
		}
	}
	return fmt.Errorf("operation_t.addr field not found in package records")
}

// addrLit renders a microcode ROM address as a VHDL std_logic_vector literal
// of width addrBits. Widths divisible by 4 use a hex literal (x"..") so the
// 8-bit case reproduces the legacy x"%02x" form byte-for-byte; other widths
// use a binary literal ("..").
func addrLit(value, addrBits int) string {
	if addrBits%4 == 0 {
		return fmt.Sprintf("x\"%0*x\"", addrBits/4, value)
	}
	return fmt.Sprintf("\"%0*b\"", addrBits, value)
}

// Build transforms a loaded Spec into the emission-ready Decoder.
// width is the ROM width in bits (64 or 72; default is 72). It is
// stored for use by the ROM template in Task 9.
// Instructions with Plane=="system" are excluded from Lines (the
// disassembler) but ARE included in the ROM at high addresses.
// Format "mn" is normalized to "nm" to match the Clojure parser's
// canonicalization. Returns an error if any retained instruction has
// a malformed opcode; callers that ran spec.Validate first will not
// hit this path, but Build does not assume Validate ran.
func Build(s *spec.Spec, width int) (*Decoder, error) {
	d := &Decoder{}
	for i := range d.Lines {
		d.Lines[i].Line = i
	}

	// Build opcode-based Lines (for disassembler). Skip system-plane instructions.
	for _, si := range s.Instrs {
		if si.Plane == "system" {
			continue
		}
		match, mask, err := opcode.Parse(si.Opcode)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", si.Name, err)
		}
		format := si.Format
		if format == "mn" {
			format = "nm"
		}
		line := int(match >> 12)
		d.Lines[line].Instructions = append(d.Lines[line].Instructions, Instruction{
			Name:      si.Name,
			Format:    format,
			Match:     match,
			Mask:      mask,
			OpcodeStr: si.Opcode,
		})
	}
	for i := range d.Lines {
		sort.Slice(d.Lines[i].Instructions, func(a, b int) bool {
			return d.Lines[i].Instructions[a].Match < d.Lines[i].Instructions[b].Match
		})
	}

	// Populate Package: start with all static types/records/components/consts,
	// then fill the dynamic ImmValLiterals from the production spec.
	pkg := newStaticPackage()
	immVals := microcode.CollectImmVals(s)
	pkg.ImmValLiterals = make([]string, len(immVals))
	for i, iv := range immVals {
		pkg.ImmValLiterals[i] = iv.Literal()
	}
	d.Package = pkg

	// -----------------------------------------------------------------------
	// ROM population
	//
	// The Clojure generator reads instructions from a spreadsheet in CSV row
	// order and uses rom/reorder-microcode :nop (sequential addressing) to
	// assign ROM addresses. Normal instructions come first (in CSV row order),
	// then system-plane instructions last.
	//
	// Our TOML files are split by category and loaded alphabetically, which
	// differs from the CSV row order. We use csvInstrOrder (derived from the
	// original CSV) to produce the correct ROM layout.
	// -----------------------------------------------------------------------

	// Build a name→Instr lookup so we can iterate in CSV order.
	instrByName := make(map[string]*spec.Instr, len(s.Instrs))
	for i := range s.Instrs {
		instrByName[s.Instrs[i].Name] = &s.Instrs[i]
	}

	// Partition instructions into normal (non-system) and system, in CSV row order.
	// Normal instructions come first in the ROM; system instructions at the end.
	var normalInstrs []*spec.Instr
	var systemInstrs []*spec.Instr

	csvNames := make(map[string]bool, len(csvInstrOrder))
	for _, name := range csvInstrOrder {
		csvNames[name] = true
		si := instrByName[name]
		if si == nil {
			continue // instruction in CSV but not in our spec (shouldn't happen)
		}
		if si.Plane == "system" {
			systemInstrs = append(systemInstrs, si)
		} else {
			normalInstrs = append(normalInstrs, si)
		}
	}
	// Loudly catch the case where a TOML instruction is missing from
	// csvInstrOrder: the disassembler (Lines) would include it but the
	// ROM would silently drop it. If it happens, csvInstrOrder must be
	// extended to cover the new instruction in its correct CSV row position.
	//
	// Skip this check when no instructions matched csvInstrOrder at all
	// (synthetic-fixture tests with names like "A","B" that aren't in any
	// production CSV) — the check only makes sense for real production
	// data where partial coverage is the failure we want to catch.
	if len(normalInstrs)+len(systemInstrs) > 0 {
		for _, si := range s.Instrs {
			if !csvNames[si.Name] {
				return nil, fmt.Errorf(
					"instruction %q is in the spec but missing from csvInstrOrder; "+
						"add it to internal/model/build.go in the position that "+
						"matches its CSV row order, then re-run", si.Name)
			}
		}
	}

	// Gather all AssignMaps in ROM order (normal first, system last).
	// CreateEncoding needs ALL slots (normal + system) because system slots
	// contribute distinct signal values that affect field widths.
	type slotMeta struct {
		instrIdx  int    // index into allInstrs
		instrName string // name of the instruction
		lastSlot  bool   // true if this is the last slot of the instruction
	}

	allInstrs := append(normalInstrs, systemInstrs...)
	var allSlots []microcode.AssignMap
	var slotMetas []slotMeta
	slotAssigns := make(map[string][]microcode.AssignMap)

	// Apply the Clojure format-inheritance rule (parser.clj reduce on line
	// 482-489): if an instruction's Format is empty, inherit Format from
	// the previous CSV row's resolved Format. We track resolvedFormat
	// across csvInstrOrder iteration, then pass the resolved format to
	// AssignSlot for register placement decisions. The rule is reset to
	// "" at the start; only non-empty Format values propagate.
	resolvedFormat := make(map[string]string, len(allInstrs))
	prevFormat := ""
	for _, name := range csvInstrOrder {
		si := instrByName[name]
		if si == nil {
			continue
		}
		if si.Format != "" {
			resolvedFormat[name] = si.Format
			prevFormat = si.Format
		} else {
			resolvedFormat[name] = prevFormat
		}
	}

	for instrIdx, si := range allInstrs {
		// Collect only non-empty slots. The TOML format uses an empty
		// [[instr.slots]] entry (len==0) as an optional cycle-terminator
		// marker; it does not correspond to a microcode cycle in the Clojure
		// source and must not occupy a ROM address.
		var keptSlots []spec.Slot
		for _, slot := range si.Slots {
			if len(slot) > 0 {
				keptSlots = append(keptSlots, slot)
			}
		}
		n := len(keptSlots)
		// Use the format-inheritance-resolved Format for register placement.
		// Every instruction in allInstrs was matched from csvInstrOrder, so
		// resolvedFormat must have an entry. A missing entry is a bug in the
		// preceding csvInstrOrder validation — fail loudly rather than
		// silently using an empty format.
		instrForAssign := *si
		rf, ok := resolvedFormat[si.Name]
		if !ok {
			return nil, fmt.Errorf(
				"internal: instruction %q reached ROM build without a resolved "+
					"format (csvInstrOrder validation should have caught this)",
				si.Name)
		}
		instrForAssign.Format = rf
		for j, slot := range keptSlots {
			am, err := microcode.AssignSlot(instrForAssign, slot)
			if err != nil {
				return nil, fmt.Errorf("%s slot %d: %w", si.Name, j, err)
			}
			// Apply the Clojure last-slot default rule (rom.clj / parser.clj):
			// if the last slot of an instruction has neither if_issue nor
			// dispatch set (i.e., both are absent in the AssignMap — equivalent
			// to Clojure's nil check), inject if_issue=1 and dispatch=1.
			// This mirrors:
			//   (if (and (nil? (:if-issue slot)) (nil? (:dispatch slot)))
			//       (merge {:if-issue true :dispatch true} slot)
			//       slot)
			if j == n-1 {
				_, hasIfIssue := am[microcode.SigIfIssue]
				_, hasDispatch := am[microcode.SigDispatch]
				if !hasIfIssue && !hasDispatch {
					am[microcode.SigIfIssue] = "1"
					am[microcode.SigDispatch] = "1"
				}
			}
			allSlots = append(allSlots, am)
			slotMetas = append(slotMetas, slotMeta{
				instrIdx:  instrIdx,
				instrName: si.Name,
				lastSlot:  j == n-1,
			})
			slotAssigns[si.Name] = append(slotAssigns[si.Name], am)
		}
	}

	// CreateEncoding over ALL slots (normal + system).
	enc := microcode.CreateEncoding(allSlots, width)

	// Size the microcode address space. op.addr must address every used slot
	// (0..len-1) AND reserve the all-ones address as the predecode "unknown
	// opcode" sentinel, so we need 2^addrBits > len(allSlots), i.e.
	// addrBits >= bits.Len(len(allSlots)). Floor at 8 to keep the existing
	// 8-bit decoders byte-identical.
	addrBits := addrBitsForSlots(len(allSlots))
	romSize := 1 << addrBits
	if len(allSlots) >= romSize {
		return nil, fmt.Errorf("microcode slots (%d) leave no room for the "+
			"all-ones sentinel in %d-bit address space", len(allSlots), addrBits)
	}
	d.AddressBits = addrBits

	// Set operation_t.addr to the computed width (newStaticPackage built it at
	// the default 8-bit; for addrBits==8 this rewrites the identical string).
	if err := setOperationAddrWidth(pkg, addrBits); err != nil {
		return nil, err
	}

	// Build the 2^addrBits-entry ROM (power of two so the all-ones sentinel
	// address is addressable; unused entries are zero words).
	rom := &ROM{
		TotalBits: enc.TotalBits,
	}
	rom.Words = make([]ROMWord, romSize)
	zeroWord := strings.Repeat("0", enc.TotalBits)
	for i := range rom.Words {
		rom.Words[i].Bits = zeroWord
	}

	// Assign sequential ROM addresses (reorder-microcode :nop).
	for addr, am := range allSlots {
		bin, err := enc.Encode(am)
		if err != nil {
			return nil, fmt.Errorf("encode addr %d (%s): %w", addr, slotMetas[addr].instrName, err)
		}
		comment := ""
		if slotMetas[addr].lastSlot {
			comment = slotMetas[addr].instrName
		}
		rom.Words[addr] = ROMWord{Bits: bin, Comment: comment}
	}

	d.ROM = rom

	// Extra immediate constants (present in the spec but not hardcoded in the
	// simple/rom decoder templates) need generated imm-mux arms. Empty for the
	// production spec; non-empty for ISA overlays that introduce new constants
	// (e.g. PM3's IMM_P256). Needs both ImmValLiterals (the immval_t set) and
	// the ROM encoding (for the rom imm-field codes).
	extraImm, err := buildExtraImmConsts(pkg.ImmValLiterals, enc)
	if err != nil {
		return nil, err
	}
	d.ExtraImmConsts = extraImm

	// Build per-instruction LogicMaps for downstream consumers. Two maps:
	//   - instrLogicNormal: non-system instructions only (plane=0). Fed to
	//     BuildBody since predecode_rom_addr and check_illegal_delay_slot
	//     only consider normal instructions.
	//   - instrLogicAll: every instruction including system (plane=1 for
	//     system, plane=0 otherwise). Fed to BuildSimple and BuildDirect
	//     since the simple/direct decoder tables must dispatch on system
	//     instructions too (interrupt, reset, illegal exception paths
	//     need their if_issue/dispatch slots driven).
	instrLogicNormal := make(map[string]logic.LogicMap, len(allInstrs))
	instrLogicAll := make(map[string]logic.LogicMap, len(allInstrs))
	writesPC := make(map[string]bool)
	privileged := make(map[string]bool)
	instrAddrs := make(map[string]int)

	// Build a first-addr lookup by scanning slotMetas (already in ROM order).
	for addr, meta := range slotMetas {
		if _, seen := instrAddrs[meta.instrName]; !seen {
			instrAddrs[meta.instrName] = addr
		}
	}

	for _, si := range allInstrs {
		plane := "0"
		if si.Plane == "system" {
			plane = "1"
		}
		instrLogicAll[si.Name] = logic.OpToLogicMap(plane, si.Opcode)
		if si.Plane != "system" {
			instrLogicNormal[si.Name] = instrLogicAll[si.Name]
			if si.Privileged {
				privileged[si.Name] = true
			}
			// Detect "writes PC": walk slots looking for SigWrpcZ == "1".
			for _, slot := range si.Slots {
				if len(slot) == 0 {
					continue
				}
				am, err := microcode.AssignSlot(*si, slot)
				if err != nil {
					return nil, fmt.Errorf("%s logicmap: %w", si.Name, err)
				}
				if am[microcode.SigWrpcZ] == "1" {
					writesPC[si.Name] = true
					break
				}
			}
		}
	}
	d.Body = BuildBody(instrAddrs, instrLogicNormal, writesPC, privileged, addrBits)
	d.Simple = BuildSimple(s, instrLogicAll, slotAssigns)
	d.Direct = BuildDirect(s, instrLogicAll, slotAssigns)
	d.Entity = BuildEntity(d.Package)

	// Populate ROM-dependent Package constants now that ROM addresses are known.
	// Find the first ROM address of each system instruction by scanning
	// slotMetas, which is already in canonical ROM-address order and only
	// contains non-empty (i.e., ROM-occupying) slots.
	sysFirstAddr := make(map[string]int)
	systemNames := make(map[string]bool, len(systemInstrs))
	for _, si := range systemInstrs {
		systemNames[si.Name] = true
	}
	for addr, meta := range slotMetas {
		if !systemNames[meta.instrName] {
			continue
		}
		if _, seen := sysFirstAddr[meta.instrName]; !seen {
			sysFirstAddr[meta.instrName] = addr
		}
	}

	// Map system instruction canonical name → ROM address.
	// The Clojure system-ops name derivation (genvhdl.clj line 624-633):
	//   lower-case → split on spaces → filter empty → replace "instruction"→"instr"
	//   → upper-case → join with "_"
	// So "Reset CPU" → "RESET_CPU", "General Illegal" → "GENERAL_ILLEGAL", etc.
	toCanonical := func(name string) string {
		parts := strings.Fields(strings.ToLower(name))
		for i, p := range parts {
			if p == "instruction" {
				parts[i] = "instr"
			}
		}
		return strings.ToUpper(strings.Join(parts, "_"))
	}

	pkg.SystemInstrROMAddrs = make(map[string]string)
	for name, a := range sysFirstAddr {
		canonical := toCanonical(name)
		pkg.SystemInstrROMAddrs[canonical] = addrLit(a, addrBits)
	}

	// DEC_CORE_ROM_RESET: inc(RESET_CPU.index) per genvhdl.clj line 711-712.
	if resetAddr, ok := sysFirstAddr["Reset CPU"]; ok {
		pkg.DecCoreROMResetAddr = addrLit(resetAddr+1, addrBits)
	}

	return d, nil
}

// csvInstrOrder is the canonical instruction order from the Clojure generator's
// SH-2 Instruction Set.csv spreadsheet. This list drives ROM address assignment
// (reorder-microcode :nop = sequential in CSV row order). Normal instructions
// precede system-plane instructions in the ROM.
//
// Derived from: decode/gen/SH-2 Instruction Set.csv (latin-1 encoded),
// column "Instruction", distinct values in first-seen row order.
var csvInstrOrder = []string{
	"CLRT",
	"CLRMAC",
	"DIV0U",
	"NOP",
	"RTE",
	"RTS",
	"SETT",
	"SLEEP",
	"BGND",
	"CMP/PL Rn",
	"CMP/PZ Rn",
	"DT Rn",
	"MOVT Rn",
	"ROTL Rn",
	"ROTR Rn",
	"ROTCL Rn",
	"ROTCR Rn",
	"SHAL Rn",
	"SHAR Rn",
	"SHLL Rn",
	"SHLR Rn",
	"SHLL2 Rn",
	"SHLR2 Rn",
	"SHLL8 Rn",
	"SHLR8 Rn",
	"SHLL16 Rn",
	"SHLR16 Rn",
	"STC SR, Rn",
	"STC GBR, Rn",
	"STC VBR, Rn",
	"STS MACH, Rn",
	"STS MACL, Rn",
	"STS PR, Rn",
	"TAS.B @Rn",
	"STC.L SR, @-Rn",
	"STC.L GBR, @-Rn",
	"STC.L VBR, @-Rn",
	"STS.L MACH, @-Rn",
	"STS.L MACL, @-Rn",
	"STS.L PR, @-Rn",
	"STS CP0_COM, Rn",
	"CSTS CP0_COM, CP0_Rn",
	"STS CPI_COM, Rn",
	"CSTS CPI_COM, CPI_Rn",
	"LDC Rm, SR",
	"LDC, Rm, GBR",
	"LDC Rm, VBR",
	"LDS Rm, MACH",
	"LDS Rm, MACL",
	"LDS Rm, PR",
	"JMP @Rm",
	"JSR @Rm",
	"LDC.L @Rm+, SR",
	"LDC.L @Rm+, GBR",
	"LDC.L @Rm+, VBR",
	"LDS.L @Rm+, MACH",
	"LDS.L @Rm+, MACL",
	"LDS.L @Rm+, PR",
	"LDS Rm, CP0_COM",
	"CLDS CP0_Rm, CP0_COM",
	"LDS Rm, CPI_COM",
	"CLDS CPI_Rm, CPI_COM",
	"BRAF Rm",
	"BSRF Rm",
	"ADD Rm, Rn",
	"ADDC Rm, Rn",
	"ADDV Rm, Rn",
	"AND Rm, Rn",
	"CMP /EQ Rm, Rn",
	"CMP /HS Rm, Rn",
	"CMP /GE Rm, Rn",
	"CMP /HI Rm, Rn",
	"CMP /GT Rm, Rn",
	"CMP /STR Rm, Rn",
	"CAS.L Rm, Rn, @R0",
	"DIV1 Rm, Rn",
	"DIV0S Rm, Rn",
	"DMULS.L Rm, Rn",
	"DMULU.L Rm, Rn",
	"EXTS.B Rm, Rn",
	"EXTS.W Rm, Rn",
	"EXTU.B Rm, Rn",
	"EXTU.W Rm, Rn",
	"MOV Rm, Rn",
	"MUL.L Rm, Rn",
	"MULS.W Rm, Rn",
	"MULU.W Rm, Rn",
	"NEG Rm, Rn",
	"NEGC Rm, Rn",
	"NOT Rm, Rn",
	"OR Rm, Rn",
	"SUB Rm, Rn",
	"SUBC Rm, Rn",
	"SUBV Rm, Rn",
	"SWAP.B Rm, Rn",
	"SWAP.W Rm, Rn",
	"TST Rm, Rn",
	"XOR Rm, Rn",
	"XTRACT Rm, Rn",
	"SHAD Rm, Rn",
	"SHLD Rm, Rn",
	"MOV.B Rm, @Rn",
	"MOV.W Rm, @Rn",
	"MOV.L Rm, @Rn",
	"MOV.B @Rm, Rn",
	"MOV.W @Rm, Rn",
	"MOV.L @Rm, Rn",
	"MAC.L @Rm+, @Rn+",
	"MAC.W @Rm+, @Rn+",
	"MOV.B @Rm+, Rn",
	"MOV.W @Rm+, Rn",
	"MOV.L @Rm+, Rn",
	"MOV.B Rm,@-Rn",
	"MOV.W Rm,@-Rn",
	"MOV.L Rm,@-Rn",
	"MOV.B Rm, @(R0, Rn)",
	"MOV.W Rm, @(R0, Rn)",
	"MOV.L Rm, @(R0, Rn)",
	"MOV.B @(R0, Rm), Rn",
	"MOV.W @(R0, Rm), Rn",
	"MOV.L @(R0, Rm), Rn",
	"MOV.B @(disp, Rm), R0",
	"MOV.W @(disp, Rm), R0",
	"MOV.B R0, @(disp, Rn)",
	"MOV.W R0, @(disp, Rn)",
	"MOV.L Rm, @(disp, Rn)",
	"MOV.L @(disp, Rm), Rn",
	"MOV.B R0, @(disp, GBR)",
	"MOV.W R0, @(disp, GBR)",
	"MOV.L R0, @(disp, GBR)",
	"MOV.B @(disp, GBR), R0",
	"MOV.W @(disp, GBR), R0",
	"MOV.L @(disp, GBR), R0",
	"MOVA @(disp, PC), R0",
	"BF label",
	"BF /S label",
	"BT label",
	"BT /S label",
	"BRA label",
	"BSR label",
	"MOV.W @(disp, PC), Rn",
	"MOV.L @(disp, PC), Rn",
	"AND.B #imm, @(R0, GBR)",
	"OR.B #imm, @(R0, GBR)",
	"TST.B #imm, @(R0, GBR)",
	"XOR.B #imm, @(R0, GBR)",
	"AND #imm, R0",
	"CMP /EQ #imm, R0",
	"OR #imm, R0",
	"TST #imm, R0",
	"XOR #imm, R0",
	"TRAPA #imm",
	"ADD #imm, Rn",
	"MOV #imm, Rn",
	// SH-4 privileged-architecture overlay (spec/sh4, generate-j4 only). These
	// are ignored by the base J2 generation (not in the base spec) and ordered
	// here for the J4 ROM layout.
	"LDC Rm, Rn_BANK",
	"STC Rm_BANK, Rn",
	"STC SSR, Rn",
	"STC SPC, Rn",
	"LDC Rm, SSR",
	"LDC Rm, SPC",
	"STC EXPEVT, Rn",
	"STC INTEVT, Rn",
	"STC TRA, Rn",
	// MMU control-register instructions (J4 overlay):
	"LDC Rm, PTEH",
	"STC PTEH, Rn",
	"LDC Rm, PTEL",
	"STC PTEL, Rn",
	"LDC Rm, ASIDR",
	"STC ASIDR, Rn",
	// System-plane instructions (at end, in CSV row order):
	"General Illegal",
	"Slot Illegal",
	"Reset CPU",
	"Interrupt",
	"Error",
	"Break",
}
