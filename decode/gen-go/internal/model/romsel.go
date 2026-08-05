package model

import (
	"fmt"
	"sort"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/microcode"
)

// buildROMSelectors derives the decode_table_rom.vhd architecture body from
// the ROM word Encoding: one `with line(Hi downto Lo) select <sig> <= ...`
// block per (encoding field, signal-in-that-field).
//
// WHY THIS IS GENERATED. It used to be 290 lines of hand-written VHDL in
// decode_table_rom.vhd.tmpl with the bit positions AND the per-value binary
// codes baked in as literals. That text was a transcription of the layout
// CreateEncoding happens to produce for the BASE spec. The ROM *words*,
// though, have always been packed data-driven from the live Encoding. Any
// spec that changes the Encoding — an ISA overlay adding values to a field,
// widening it, or introducing a new field — moved the packing while the
// reader stayed still, so every control signal was decoded from the wrong
// bits and/or the wrong codes. The sh4 overlay does exactly that (75-bit ROM
// word -> 85-bit, four new fields, and first-encounter code reassignment even
// in fields whose position did not move), which is why the J4 ROM decoder
// could not boot. Deriving the reader from the same Encoding that does the
// packing makes the two structurally incapable of disagreeing.
func buildROMSelectors(enc *microcode.Encoding) ([]ROMSelector, error) {
	// Encoding.Fields is MSB-first; emit ascending by Lo so the generated
	// architecture reads bottom-of-word to top.
	fields := make([]microcode.Field, len(enc.Fields))
	copy(fields, enc.Fields)
	sort.SliceStable(fields, func(i, j int) bool { return fields[i].Lo < fields[j].Lo })

	var out []ROMSelector
	for _, f := range fields {
		sigs := f.Group
		if sigs == nil {
			sigs = microcode.CombinableGroup{f.Signal}
		}
		for i, s := range sigs {
			sel, err := buildOneROMSelector(f, s, i, len(sigs) > 1 || f.Group != nil)
			if err != nil {
				return nil, err
			}
			out = append(out, sel)
		}
	}
	return out, nil
}

func buildOneROMSelector(f microcode.Field, s microcode.Signal, idx int, grouped bool) (ROMSelector, error) {
	lhs := microcode.SignalROMPath(s)
	if lhs == "" {
		return ROMSelector{}, fmt.Errorf("rom selector: no VHDL path for signal %q", s)
	}
	def, ok := microcode.SignalROMDefault(s)
	if !ok {
		return ROMSelector{}, fmt.Errorf("rom selector: no `when others` default for signal %q "+
			"(add it to microcode.SignalROMDefault)", s)
	}
	width := f.Width()

	// Rendered-value -> the codes that select it.
	byVal := map[string][]int{}
	for key, code := range f.Codes {
		if key == "" {
			continue // the all-absent tuple -> `others`
		}
		raw := key
		if grouped {
			parts := strings.Split(key, ",")
			if idx >= len(parts) {
				return ROMSelector{}, fmt.Errorf("rom selector: group key %q has no component %d", key, idx)
			}
			raw = parts[idx]
		}
		if raw == "" {
			continue // absent for this signal in this tuple -> falls into `others`
		}
		v, err := romRHS(s, raw)
		if err != nil {
			return ROMSelector{}, err
		}
		byVal[v] = append(byVal[v], code)
	}

	// A zero-width field carries no bits: the signal is constant.
	if width == 0 {
		val := def
		for v := range byVal {
			val = v
		}
		return ROMSelector{Signal: lhs, Hi: f.Hi, Lo: f.Lo, Default: val, Constant: true}, nil
	}

	var cases []ROMCase
	for v, codes := range byVal {
		if v == def {
			continue // folds into `when others`
		}
		sort.Ints(codes)
		strs := make([]string, len(codes))
		for i, c := range codes {
			strs[i] = fmt.Sprintf("%0*b", width, c)
		}
		cases = append(cases, ROMCase{Value: v, Codes: strs})
	}
	// Deterministic order: by first (lowest) code, then by value text.
	sort.Slice(cases, func(i, j int) bool {
		if cases[i].Codes[0] != cases[j].Codes[0] {
			return cases[i].Codes[0] < cases[j].Codes[0]
		}
		return cases[i].Value < cases[j].Value
	})

	sel := ROMSelector{Signal: lhs, Hi: f.Hi, Lo: f.Lo, Cases: cases, Default: def}

	// One-bit std_logic field whose only value is '1' collapses to a bare
	// `sig <= line(N);` — the shape the hand-written architecture used.
	if width == 1 && s.IsStdLogic() && len(cases) == 1 &&
		cases[0].Value == "'1'" && len(cases[0].Codes) == 1 && cases[0].Codes[0] == "1" &&
		def == "'0'" {
		sel.SingleBit = true
		sel.Cases = nil
	}
	if len(cases) == 0 && !sel.SingleBit {
		// Nothing but the default: emit a constant assignment rather than a
		// degenerate mux.
		sel.Constant = true
	}
	return sel, nil
}

// romRHS renders one symbolic signal value as the VHDL expression the ROM
// architecture assigns. Same rules as the simple/direct decoders
// (signalRHS), plus imm_val, which the ROM drives as a 32-bit value rather
// than through the imm_enum intermediate.
func romRHS(s microcode.Signal, v string) (string, error) {
	if s == microcode.SigImmVal {
		e := microcode.ImmLiteralToVHDL(v)
		if e == "" {
			return "", fmt.Errorf("rom selector: unrecognized immediate literal %q", v)
		}
		return e, nil
	}
	return signalRHS(s, v), nil
}
