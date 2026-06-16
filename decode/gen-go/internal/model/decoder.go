package model

// Instruction is the per-opcode view used by sh2instr.c emission.
type Instruction struct {
	Name      string // e.g. "ADD Rm, Rn", "BSRF Rm"
	Format    string // canonical normalized format: "n", "m", "nm", "md", "nd4", "nd8", "nmd", "ni", "d8", "d12", "i8", "0", ""
	Match     uint16 // bit pattern from opcode (e.g. 0x300C for "0011 nnnn mmmm 1100")
	Mask      uint16 // 1-bits where opcode is fixed (e.g. 0xF00F for the same)
	OpcodeStr string // raw opcode string (e.g. "0011 nnnn mmmm 1100"); used by registerArgs for format=="" instructions
}

// LineGroup gathers instructions whose top 4 opcode bits equal Line.
// Each lineN function in sh2instr.c corresponds to one LineGroup.
type LineGroup struct {
	Line         int           // 0..15
	Instructions []Instruction // sorted by Match for diff stability
}

// Decoder is the root passed to templates.
type Decoder struct {
	// Lines is always length 16; entries may have empty Instructions.
	Lines [16]LineGroup

	// AddressBits is the width of op.addr (the microcode ROM address),
	// computed by Build as max(8, bits.Len(numSlots)) so the all-ones
	// address stays a reserved, unused slot (the predecode "unknown
	// opcode" sentinel). 8 while the microcode fits 256 slots, 9 once it
	// exceeds 256. Threaded to the templates that declare address widths.
	AddressBits int

	// Package carries the structured representation of decode_pkg.vhd:
	// enum types, record types, component declarations, and constants.
	// Populated by Build; used by the decode_pkg.vhd template.
	Package *Package

	// ROM carries the 256-entry microcode ROM and the per-field selector
	// blocks needed to render decode_table_rom.vhd. Populated by Build
	// (Task 9); nil if Build was called without ROM population.
	ROM *ROM

	// Body carries the emission-ready view of decode_body.vhd: the predecode
	// ROM address function, illegal delay slot check, and illegal instruction
	// check. Populated by Build after the ROM/Package population.
	Body *Body

	// Simple carries the emission-ready view of decode_table_simple.vhd:
	// the list of instructions sorted by std_match pattern, each with its
	// per-slot signal assignments. Populated by Build after the Body.
	Simple *SimpleDecoder

	// Direct carries the emission-ready view of decode_table_direct.vhd:
	// named imp_bit_N intermediate signals, optional condN mux signals,
	// and per-output boolean or mux expressions. Populated by Build after
	// the Simple decoder.
	Direct *DirectDecoder

	// Entity carries the emission-ready view of the decode entity declaration:
	// the port list taken from the "decode" component in Package.Components.
	// Populated by Build after the Package.
	Entity *DecodeEntity
}
