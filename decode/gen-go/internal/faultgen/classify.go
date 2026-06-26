package faultgen

import (
	"regexp"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// Bucket classifies the fault-test strategy for an instruction.
type Bucket int

const (
	General Bucket = iota // standard GPR-only; general fault test
	PrivMem               // privileged or writes a control register; needs state restore
	Bespoke               // control-flow/system — excluded, handled by dedicated guards
)

// MemKind describes whether any slot performs a memory access.
type MemKind int

const (
	NoMem MemKind = iota
	Read
	Write
)

// AddrMode is the addressing mode of the memory-accessing slot.
type AddrMode int

const (
	NoAddr  AddrMode = iota
	PostInc          // @Rm+ or @Rn+
	PreDec           // @-Rn or @-Rm
	Disp             // displacement-relative
	Plain            // @Rn, @Rm
)

// Class is the classification of one instruction for fault testing.
type Class struct {
	Instr    spec.Instr
	Bucket   Bucket
	Mem      MemKind  // does any slot access memory, and read or write
	Addr     AddrMode // addressing mode of the memory slot (NoAddr if NoMem)
	BaseReg  string   // base register modified by PostInc/PreDec (e.g. "Rm","Rn"), "" otherwise
	DestCtrl string   // non-GPR control reg written, "" if writes only GPRs/mem
	DFaults  bool     // in scope for the D-side fault axis (Mem != NoMem)
	IFaults  bool     // in scope for the I-fetch axis (always true unless Bespoke-excluded)
}

var (
	gprRe = regexp.MustCompile(`^R(\d+|m|n)$`)

	// control registers recognised as DestCtrl when seen in wbus/zbus
	ctrlRegs = map[string]bool{
		"PR": true, "MACH": true, "MACL": true, "SR": true,
		"SSR": true, "SPC": true, "GBR": true, "VBR": true,
		"PC": true, "T": true,
	}

	// branch name prefixes (BRA BSR BT BF JMP JSR RTS)
	branchPrefixes = []string{"BRA", "BSR", "BT", "BF", "JMP", "JSR", "RTS"}

	// displacement formats
	dispFormats = map[string]bool{
		"nmd": true, "md": true, "nd4": true, "nd8": true, "d": true, "d8": true,
	}
)

func isBespoke(in spec.Instr) bool {
	switch in.Name {
	case "RTE", "LDTLB", "LDTLB.R", "SLEEP", "TRAPA":
		return true
	}
	for _, pfx := range branchPrefixes {
		if strings.HasPrefix(in.Name, pfx) {
			return true
		}
	}
	return false
}

func isGPR(s string) bool {
	return gprRe.MatchString(s)
}

// memSlot returns (kind, found) for the first slot with an ma_op field.
// Write dominates Read if both appear across slots.
func memSlot(slots []spec.Slot) MemKind {
	result := NoMem
	for _, sl := range slots {
		switch sl["ma_op"] {
		case "READ":
			if result == NoMem {
				result = Read
			}
		case "WRITE":
			result = Write // Write dominates
		}
	}
	return result
}

// addrMode inspects the instruction name and format to determine addressing mode.
func addrMode(in spec.Instr) AddrMode {
	name := in.Name
	if strings.Contains(name, "@Rm+") || strings.Contains(name, "@Rn+") {
		return PostInc
	}
	if strings.Contains(name, "@-Rn") || strings.Contains(name, "@-Rm") {
		return PreDec
	}
	if dispFormats[in.Format] || strings.Contains(name, "@(") {
		return Disp
	}
	return Plain
}

// baseReg extracts the register modified by PostInc or PreDec from the Name.
// Returns "Rm" or "Rn" (first occurrence for dual-postinc like MAC.L).
func baseReg(in spec.Instr, mode AddrMode) string {
	switch mode {
	case PostInc:
		if strings.Contains(in.Name, "@Rm+") {
			return "Rm"
		}
		if strings.Contains(in.Name, "@Rn+") {
			return "Rn"
		}
	case PreDec:
		if strings.Contains(in.Name, "@-Rm") {
			return "Rm"
		}
		if strings.Contains(in.Name, "@-Rn") {
			return "Rn"
		}
	}
	return ""
}

// destCtrl returns the first non-GPR control register written in any slot's
// wbus or zbus field. Returns "" if all write targets are GPRs or memory.
func destCtrl(slots []spec.Slot) string {
	for _, sl := range slots {
		for _, field := range []string{"wbus", "zbus"} {
			v := sl[field]
			if v == "" || isGPR(v) {
				continue
			}
			if ctrlRegs[v] {
				return v
			}
		}
	}
	return ""
}

// Classify returns the Class for an instruction.
func Classify(in spec.Instr) Class {
	if isBespoke(in) {
		return Class{
			Instr:   in,
			Bucket:  Bespoke,
			DFaults: false,
			IFaults: false,
		}
	}

	mem := memSlot(in.Slots)
	var addr AddrMode
	var base string
	if mem != NoMem {
		addr = addrMode(in)
		base = baseReg(in, addr)
	}

	dc := destCtrl(in.Slots)

	bucket := General
	if in.Privileged || dc != "" {
		bucket = PrivMem
	}

	return Class{
		Instr:    in,
		Bucket:   bucket,
		Mem:      mem,
		Addr:     addr,
		BaseReg:  base,
		DestCtrl: dc,
		DFaults:  mem != NoMem,
		IFaults:  true,
	}
}
