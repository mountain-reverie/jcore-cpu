package model

// ROM holds the 256-entry microcode ROM that backs decode_table_rom.vhd.
// Each entry is one TotalBits-wide binary string (e.g., 75-char string for
// width 72). Addresses not covered by any instruction slot are zero strings.
//
// Populated by Build once CreateEncoding runs over all slots (normal + system).
type ROM struct {
	// TotalBits is the ROM word width (e.g., 75 for -w 72).
	TotalBits int

	// Words is the 256-entry array. Each entry is a TotalBits-wide binary
	// string ("0101..."). Comment is the instruction name that ends at this
	// address (i.e., the last slot of some instruction), or "" if none.
	Words [256]ROMWord

	// Selectors holds the per-field decoder blocks for the `with line(...)
	// select` statements. Populated alongside Words.
	Selectors []ROMSelector
}

// ROMWord is one microcode ROM entry.
type ROMWord struct {
	Bits    string // TotalBits-wide binary string, all '0' if unused
	Comment string // instruction name if this is the last slot, else ""
}

// ROMSelector is one `with line(Hi downto Lo) select <Signal> <= ...` block.
// The template emits these in order.
type ROMSelector struct {
	Signal   string        // VHDL signal name (e.g., "ex.aluinx_sel", "ex_stall.wrpc_z")
	Hi, Lo   int           // bit-field indices in the ROM word
	Cases    []ROMCase     // sorted by Code for deterministic output
	Default  string        // VHDL default expression (e.g., "'0'", "SEL_ARITH")
	SingleBit bool         // true if Hi==Lo (1-bit field → direct line(N) assignment)
}

// ROMCase is one `<value> when "<code>"` arm.
type ROMCase struct {
	Value string // VHDL expression (e.g., "'1'", "SEL_LOGIC")
	Codes []string // binary strings that produce this value
}
