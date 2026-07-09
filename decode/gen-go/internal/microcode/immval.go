package microcode

import (
	"fmt"
	"math/bits"
	"sort"
	"strconv"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// tableRefKey converts a table_ref string like "A.38" into a numeric sort key.
// Returns maxInt for instructions without a table_ref (they are sorted last).
func tableRefKey(ref string) int {
	// Format is "A.NNN" — parse the number after the dot.
	if idx := strings.Index(ref, "."); idx >= 0 {
		if n, err := strconv.Atoi(ref[idx+1:]); err == nil {
			return n
		}
	}
	return 1<<31 - 1 // maxInt: instructions without table_ref sort last
}

// ImmVal is a parsed immediate value, either a small integer constant
// or a structured "extract these bits from the opcode" descriptor.
type ImmVal struct {
	Kind ImmKind // Numeric / Unsigned / Signed
	N    int     // numeric value (Kind == Numeric)
	W    int     // bit width (Kind == Unsigned or Signed)
	S    int     // shift count (Kind == Unsigned or Signed)
}

type ImmKind int

const (
	ImmNumeric ImmKind = iota
	ImmUnsigned
	ImmSigned
	// ImmUnsignedHi is an unsigned immediate sourced from the HIGH register
	// nibble op.code(11:8) (rather than the low bits like ImmUnsigned).
	// Needed by SH-2A movml.l pop, whose per-element displacement rides in
	// op.code(11:8) -- the wildcard register nibble that decode_core overrides
	// with the running index -- because op.code(3:0) is a fixed opcode
	// discriminant there and cannot be repurposed as a disp field.
	ImmUnsignedHi
)

// ImmLiteralToVHDL translates an immval_t enum literal name to the
// 32-bit std_logic_vector expression that names that immediate. Used
// by the direct decoder where ex.imm_val is assigned directly (no
// imm_enum intermediate). Returns "" for unrecognized literals.
//
// Mirrors the `with imm_enum select ex.imm_val <= ...` mux body in
// decode_table_simple.vhd.
func ImmLiteralToVHDL(lit string) string {
	switch lit {
	case "IMM_ZERO":
		return `x"00000000"`
	case "IMM_P1":
		return `x"00000001"`
	case "IMM_P2":
		return `x"00000002"`
	case "IMM_P4":
		return `x"00000004"`
	case "IMM_P8":
		return `x"00000008"`
	case "IMM_P16":
		return `x"00000010"`
	case "IMM_N1":
		return `x"ffffffff"`
	case "IMM_N2":
		return `x"fffffffe"`
	case "IMM_N8":
		return `x"fffffff8"`
	case "IMM_N16":
		return `x"fffffff0"`
	case "IMM_U_4_0":
		return `x"0000000" & op.code(3 downto 0)`
	case "IMM_U_4_1":
		return `"000000000000000000000000000" & op.code(3 downto 0) & "0"`
	case "IMM_U_4_2":
		return `"00000000000000000000000000" & op.code(3 downto 0) & "00"`
	case "IMM_U_8_0":
		return `x"000000" & op.code(7 downto 0)`
	case "IMM_U_8_1":
		return `"00000000000000000000000" & op.code(7 downto 0) & "0"`
	case "IMM_U_8_2":
		return `"0000000000000000000000" & op.code(7 downto 0) & "00"`
	case "IMM_U_H4_2":
		return `"00000000000000000000000000" & op.code(11 downto 8) & "00"`
	case "IMM_S_8_0":
		return "imms_8_0"
	case "IMM_S_8_1":
		return "imms_8_1"
	case "IMM_S_12_1":
		return "imms_12_1"
	case "IMM_U_12_0":
		return `x"00000" & ext_word(11 downto 0)`
	case "IMM_U_12_2":
		return `"000000000000000000" & ext_word(11 downto 0) & "00"`
	case "IMM_S_20_0":
		return `op.code(11) & op.code(11) & op.code(11) & op.code(11) & op.code(11) & op.code(11) & op.code(11) & op.code(11) & op.code(11) & op.code(11) & op.code(11) & op.code(11) & op.code(11 downto 8) & ext_word(15 downto 0)`
	}
	// General numeric constants: IMM_P<N> / IMM_N<N> for any N. The
	// explicit cases above are kept for low-churn review, but this
	// fallback produces byte-identical output for them (e.g. IMM_P16 ->
	// x"00000010", IMM_N16 -> x"fffffff0") and extends the immediate set
	// to arbitrary constants (IMM_P256 -> x"00000100"), which PM3+ needs.
	if s, ok := strings.CutPrefix(lit, "IMM_P"); ok {
		if n, err := strconv.ParseUint(s, 10, 32); err == nil {
			return fmt.Sprintf(`x"%08x"`, uint32(n))
		}
	}
	if s, ok := strings.CutPrefix(lit, "IMM_N"); ok {
		if n, err := strconv.ParseUint(s, 10, 32); err == nil {
			return fmt.Sprintf(`x"%08x"`, uint32(-int64(n))) // two's complement
		}
	}
	return ""
}

// Literal returns the VHDL enum literal for this ImmVal.
// IMM_ZERO, IMM_P4, IMM_N16, IMM_U_8_2, IMM_S_12_1, etc.
func (i ImmVal) Literal() string {
	switch i.Kind {
	case ImmNumeric:
		if i.N == 0 {
			return "IMM_ZERO"
		}
		if i.N > 0 {
			return fmt.Sprintf("IMM_P%d", i.N)
		}
		return fmt.Sprintf("IMM_N%d", -i.N)
	case ImmUnsigned:
		return fmt.Sprintf("IMM_U_%d_%d", i.W, i.S)
	case ImmSigned:
		return fmt.Sprintf("IMM_S_%d_%d", i.W, i.S)
	case ImmUnsignedHi:
		return fmt.Sprintf("IMM_U_H%d_%d", i.W, i.S)
	}
	return ""
}

// ParseImm parses a slot-field value into an ImmVal. Recognized forms:
//   - "0", "1", "-1", "16" — numeric integer.
//   - "u 8 2", "s 12 1" — structured: kind width shift, whitespace-separated.
//   - "[u 8 2]", "[s 12 1]" — Clojure-vector form (legacy; tolerate).
//
// Returns ok=false if v doesn't parse as an immediate.
// Note: TOML-style structured immediates like "U*4" require format context;
// use ParseImmToml for those.
func ParseImm(v string) (ImmVal, bool) {
	v = strings.TrimSpace(v)
	if v == "" {
		return ImmVal{}, false
	}
	// Try integer.
	if n, err := strconv.Atoi(v); err == nil {
		return ImmVal{Kind: ImmNumeric, N: n}, true
	}
	// Try structured. Accept both "u 8 2" and "[u 8 2]".
	trimmed := strings.TrimSuffix(strings.TrimPrefix(v, "["), "]")
	parts := strings.Fields(trimmed)
	if len(parts) != 3 {
		return ImmVal{}, false
	}
	w, err1 := strconv.Atoi(parts[1])
	s, err2 := strconv.Atoi(parts[2])
	if err1 != nil || err2 != nil {
		return ImmVal{}, false
	}
	switch parts[0] {
	case "u":
		return ImmVal{Kind: ImmUnsigned, W: w, S: s}, true
	case "s":
		return ImmVal{Kind: ImmSigned, W: w, S: s}, true
	}
	return ImmVal{}, false
}

// formatBitWidth returns the immediate bit-width encoded in the instruction
// format field. Mirrors Clojure parser.clj's extract-imm map:
//
//	md, nd4, nmd → 4 bits
//	d8, nd8, i8, ni → 8 bits
//	d12 → 12 bits
//
// Returns 0 for formats with no immediate field (e.g., "0", "n", "nm", "m").
func formatBitWidth(format string) int {
	switch format {
	case "md", "nd4", "nmd":
		return 4
	case "d8", "nd8", "i8", "ni":
		return 8
	case "d12", "nmd12":
		return 12
	default:
		return 0
	}
}

// multToShift converts a multiplication factor to a shift count.
// mult=1→0, mult=2→1, mult=4→2. Mirrors Clojure's log₂ computation.
func multToShift(mult int) int {
	if mult <= 1 {
		return 0
	}
	// log2 of mult: position of the highest set bit minus 1
	return bits.Len(uint(mult)) - 1
}

// ParseImmToml parses a TOML slot-field value into an ImmVal, using the
// instruction format to determine the bit-width for structured immediates.
//
// Recognized forms:
//   - Plain integer strings: "0", "1", "-16", "4" → ImmNumeric
//   - TOML structured: "U", "S" → unsigned/signed, width from format, shift 0
//   - TOML structured: "U*N", "S*N" → unsigned/signed, width from format, shift=log₂(N)
//
// Returns ok=false if v is not a recognized immediate form (e.g., a register name).
func ParseImmToml(format, v string) (ImmVal, bool) {
	v = strings.TrimSpace(v)
	if v == "" {
		return ImmVal{}, false
	}
	// Try integer first.
	if n, err := strconv.Atoi(v); err == nil {
		return ImmVal{Kind: ImmNumeric, N: n}, true
	}
	up := strings.ToUpper(v)
	// High-nibble unsigned immediate: "UH", "UH*N" -> op.code(11:8) << log2(N).
	// Width is fixed at 4 (the nibble), independent of the instruction format.
	if strings.HasPrefix(up, "UH") {
		rest := up[2:]
		mult := 1
		if rest != "" {
			if !strings.HasPrefix(rest, "*") {
				return ImmVal{}, false
			}
			n, err := strconv.Atoi(rest[1:])
			if err != nil {
				return ImmVal{}, false
			}
			mult = n
		}
		return ImmVal{Kind: ImmUnsignedHi, W: 4, S: multToShift(mult)}, true
	}
	// TOML structured immediate: "U", "S", "U*N", "S*N"
	var kind ImmKind
	var rest string
	if strings.HasPrefix(up, "U") {
		kind = ImmUnsigned
		rest = up[1:]
	} else if strings.HasPrefix(up, "S") {
		kind = ImmSigned
		rest = up[1:]
	} else {
		return ImmVal{}, false
	}
	// rest is either "" (no multiplier) or "*N"
	var mult int
	if rest == "" {
		mult = 1
	} else if strings.HasPrefix(rest, "*") {
		n, err := strconv.Atoi(rest[1:])
		if err != nil {
			return ImmVal{}, false
		}
		mult = n
	} else {
		return ImmVal{}, false
	}
	w := formatBitWidth(format)
	if w == 0 {
		// No immediate field in this format — shouldn't happen for valid TOML
		return ImmVal{}, false
	}
	s := multToShift(mult)
	return ImmVal{Kind: kind, W: w, S: s}, true
}

// CollectImmVals walks every slot in spec, collects every distinct
// ImmVal that appears in xbus/ybus/alu_y, and returns them in the
// canonical order: zero first, then positive integers ascending, then
// negative integers ascending (most-negative first), then structured
// immediates in first-encountered order (matching Clojure spreadsheet row order).
//
// Only non-system instructions are visited (plane != "system").
//
// For structured immediates, first-encountered order is determined by
// sorting instructions by their table_ref field (e.g., "A.38" < "A.43"),
// which mirrors the SH-2 instruction-set table ordering in the Clojure
// generator's source spreadsheet. Instructions with the same table_ref
// retain their within-file (TOML) order. Within each instruction, fields
// are scanned in the Clojure-canonical order: alu_y, xbus, ybus.
//
// Port of Clojure interface.clj generate-interface, lines 126–142.
func CollectImmVals(s *spec.Spec) []ImmVal {
	// Collect non-system instructions, preserving original (file-load) order
	// as the stable secondary key, then sort by table_ref.
	type instrWithIndex struct {
		instr spec.Instr
		idx   int
	}
	var instrs []instrWithIndex
	for i, instr := range s.Instrs {
		if instr.Plane != "system" {
			instrs = append(instrs, instrWithIndex{instr, i})
		}
	}
	sort.SliceStable(instrs, func(i, j int) bool {
		ki := tableRefKey(instrs[i].instr.TableRef)
		kj := tableRefKey(instrs[j].instr.TableRef)
		if ki != kj {
			return ki < kj
		}
		return instrs[i].idx < instrs[j].idx // stable: preserve within-file order
	})

	seen := map[ImmVal]bool{}
	var structuredOrder []ImmVal
	var positives, negatives []ImmVal
	includeZero := false

	for _, ii := range instrs {
		instr := ii.instr
		for _, slot := range instr.Slots {
			// Clojure canonical field order: aluy, x, y → alu_y, xbus, ybus
			for _, field := range []string{"alu_y", "xbus", "ybus"} {
				raw := slot[field]
				if raw == "" {
					continue
				}
				v, ok := ParseImmToml(instr.Format, raw)
				if !ok || seen[v] {
					continue
				}
				seen[v] = true
				switch {
				case v.Kind == ImmNumeric && v.N == 0:
					includeZero = true
				case v.Kind == ImmNumeric && v.N > 0:
					positives = append(positives, v)
				case v.Kind == ImmNumeric && v.N < 0:
					negatives = append(negatives, v)
				default:
					structuredOrder = append(structuredOrder, v)
				}
			}
		}
	}

	sort.Slice(positives, func(i, j int) bool { return positives[i].N < positives[j].N })
	sort.Slice(negatives, func(i, j int) bool { return negatives[i].N < negatives[j].N })

	var out []ImmVal
	if includeZero {
		out = append(out, ImmVal{Kind: ImmNumeric, N: 0})
	}
	out = append(out, positives...)
	out = append(out, negatives...)
	out = append(out, structuredOrder...)

	// System-plane immediates are excluded from the canonical collection
	// above (the Clojure port's behaviour: system instructions reuse the
	// same constants as non-system ones). That holds for every constant in
	// production — but a system instruction MAY introduce a numeric
	// immediate used nowhere else (PM3's VBR+0x100 fixed-vector offset is
	// the first). Such a constant must still be declared in immval_t so the
	// simple/direct decoders can name it. Collect any system-only numeric
	// immediates and append them at the END, sorted, so the existing order
	// — and thus byte-identical output for the production spec, where this
	// set is empty — is preserved.
	var systemExtras []ImmVal
	for _, instr := range s.Instrs {
		if instr.Plane != "system" {
			continue
		}
		for _, slot := range instr.Slots {
			for _, field := range []string{"alu_y", "xbus", "ybus"} {
				raw := slot[field]
				if raw == "" {
					continue
				}
				v, ok := ParseImmToml(instr.Format, raw)
				if !ok || seen[v] {
					continue
				}
				seen[v] = true
				// Only numeric constants are appended here. A system-only
				// structured immediate (opcode-field extraction) would also
				// need decoder-template support, which is out of scope until
				// one actually appears.
				if v.Kind == ImmNumeric {
					systemExtras = append(systemExtras, v)
				}
			}
		}
	}
	sort.Slice(systemExtras, func(i, j int) bool { return systemExtras[i].N < systemExtras[j].N })
	out = append(out, systemExtras...)

	return out
}
