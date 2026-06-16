package model

import (
	"fmt"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/microcode"
)

// ExtraImmConst is one immediate constant whose decoder mux arm is NOT
// hardcoded in the simple/rom templates and must therefore be generated.
// The simple decoder selects on the immval_t enum (uses Literal), the rom
// decoder selects on the packed bit-field code (uses RomCode); both emit the
// same 32-bit value (VHDL).
type ExtraImmConst struct {
	Literal string // immval_t enum literal, e.g. "IMM_P256"
	VHDL    string // 32-bit value expression, e.g. x"00000100"
	RomCode string // rom imm-field code as a binary string, e.g. "10011"
}

// predefinedImmLiterals is the set of immval_t literals whose imm-mux arms are
// hardcoded in decode_table_simple.vhd.tmpl and decode_table_rom.vhd.tmpl.
// Any collected immval_t literal NOT in this set is an "extra" constant for
// which buildExtraImmConsts generates an additional mux arm. This set must
// stay in sync with the hardcoded arms in those two templates; the production
// spec produces exactly this set (so ExtraImmConsts is empty for it, keeping
// the templates byte-identical), which TestCollectImmValsProduction pins down.
var predefinedImmLiterals = map[string]bool{
	"IMM_ZERO": true,
	"IMM_P1":   true, "IMM_P2": true, "IMM_P4": true, "IMM_P8": true, "IMM_P16": true,
	"IMM_N1": true, "IMM_N2": true, "IMM_N8": true, "IMM_N16": true,
	"IMM_U_4_0": true, "IMM_U_4_1": true, "IMM_U_4_2": true,
	"IMM_U_8_0": true, "IMM_U_8_1": true, "IMM_U_8_2": true,
	"IMM_S_8_0": true, "IMM_S_8_1": true, "IMM_S_12_1": true,
}

// romImmFieldBits is the width (in bits) of the imm-value field selector that
// the rom template hardcodes as `with line(59 downto 55) select`. Generated
// extra rom arms must use codes of exactly this width to match that selector.
// If the encoding ever widens this field (more than 2^romImmFieldBits distinct
// immediates), the hardcoded arms and selector are wrong and the rom template
// body must be regenerated — buildExtraImmConsts fails loudly rather than emit
// silently-inconsistent VHDL.
const romImmFieldBits = 5

// buildExtraImmConsts returns the immval_t literals that are NOT hardcoded in
// the decoder templates, each with its 32-bit VHDL value and (for the rom
// decoder) its packed bit-field code. immLiterals is the full ordered immval_t
// set (model Package.ImmValLiterals); enc is the ROM encoding (whose imm field
// assigns each literal a numeric code).
//
// Returns an empty slice for the production spec (every literal is predefined),
// which keeps the simple/rom templates byte-identical.
func buildExtraImmConsts(immLiterals []string, enc *microcode.Encoding) ([]ExtraImmConst, error) {
	immField, hasImmField := immFieldFromEncoding(enc)

	var out []ExtraImmConst
	for _, lit := range immLiterals {
		if predefinedImmLiterals[lit] {
			continue
		}
		vhdl := microcode.ImmLiteralToVHDL(lit)
		if vhdl == "" {
			return nil, fmt.Errorf("immediate %q has no VHDL expansion (ImmLiteralToVHDL is "+
				"non-total over it); the direct decoder would emit a bare enum into a "+
				"std_logic_vector context", lit)
		}
		ec := ExtraImmConst{Literal: lit, VHDL: vhdl}

		if !hasImmField {
			return nil, fmt.Errorf("ROM encoding has no imm-value field but extra immediate "+
				"%q exists; rom decoder cannot encode it", lit)
		}
		code, found := immField.Codes[lit]
		if !found {
			return nil, fmt.Errorf("immediate %q is declared in immval_t but absent from the "+
				"ROM imm-field encoding; the rom decoder would silently drop it to "+
				"others => x\"00000000\"", lit)
		}
		if w := immField.Width(); w != romImmFieldBits {
			return nil, fmt.Errorf("ROM imm-value field is %d bits but the rom template "+
				"hardcodes a %d-bit selector (line(59 downto 55)); the rom template body "+
				"must be regenerated for the wider field before adding immediate %q",
				w, romImmFieldBits, lit)
		}
		ec.RomCode = fmt.Sprintf("%0*b", romImmFieldBits, code)
		out = append(out, ec)
	}
	return out, nil
}

// immFieldFromEncoding returns the encoding field that carries the immediate
// value (SigImmVal).
func immFieldFromEncoding(enc *microcode.Encoding) (microcode.Field, bool) {
	for _, f := range enc.Fields {
		if f.Signal == microcode.SigImmVal {
			return f, true
		}
	}
	return microcode.Field{}, false
}
