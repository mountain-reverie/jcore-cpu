package microcode

import (
	"fmt"
	"math/bits"
	"sort"
	"strings"
)

// Encoding describes the ROM word bit-field layout. It is computed once
// per generator run (per ROM width) from the union of AssignMaps across
// all kept slots. The layout is deterministic: standalone signals sorted
// alphabetically by name come first (getting the HIGH bits), then
// combinable-group fields in CombinableSignals order (getting the LOW
// bits). This matches the Clojure create-encoding key-fn construction:
//
//	key-fns = concat(standalone-sorted-alpha, combinable-groups)
//
// and the bit-position assignment that starts at (dec full-width) and
// steps downward, so the first key-fn gets the highest bit indices.
//
// Verify against decode_table_rom.vhd golden:
//   - line(74 downto 73): aluinx_sel     ← first standalone alpha
//   - line(2 downto 0):   wrpc_z group   ← last combinable group
type Encoding struct {
	TotalBits int     // total ROM word width
	Fields    []Field // ordered MSB-first (fields[0].Hi is the highest bit)
}

// Field is one bit-region of the ROM word. Either a standalone signal
// or a combinable group.
type Field struct {
	// Signal is set for standalone fields; Group is set for combinable fields.
	Signal Signal          // empty string iff Group is non-nil
	Group  CombinableGroup // nil iff Signal is non-empty

	Hi, Lo int // bit positions in the ROM word; Hi >= Lo

	// Codes maps a tuple-key to its integer code. The empty string key
	// is code 0 (nil/all-absent). Other values are 1, 2, 3 ... in
	// first-encountered order across the slots slice.
	//
	// For standalone fields the key is the signal value (e.g., "ADD").
	// For group fields the key is the comma-joined tuple of values for
	// all signals in the group (e.g., "ADD,,SEL_IMM"), with missing
	// signals represented as empty strings.
	Codes map[string]int
}

// Width returns the number of bits this field occupies.
func (f Field) Width() int {
	n := len(f.Codes)
	if n <= 1 {
		return 0
	}
	return bits.Len(uint(n - 1))
}

// NillableSignals is the set of signals that are "nillable" in the
// Clojure encoding. For nillable standalone signals, the nil/absent
// case is represented as all-zeros binary (not as a distinct code).
// The encode-width is ceil(log2(N)) where N is the count of DISTINCT
// NON-NIL values, not N+1. This matches the Clojure nillable-outputs
// set in interface.clj lines 406-415.
//
// Combinable groups are never nillable — the nil/all-absent tuple is
// always treated as code 0 for groups.
var NillableSignals = map[Signal]bool{
	SigShiftFunc:   true,
	SigImmVal:      true,
	SigMaWr:        true,
	SigArithFunc:   true,
	SigArithSrFn:   true,
	SigLogicFunc:   true,
	SigLogicSrFn:   true,
	SigZbusSel:     true,
	SigMemAddrSel:  true,
	SigMemSize:     true,
	SigMemWdataSel: true,
	SigRegnumW:     true,
	SigRegnumX:     true,
	SigRegnumY:     true,
	SigRegnumZ:     true,
}

// CreateEncoding walks every AssignMap in slots, gathers distinct
// value-tuples per field, assigns codes (0 = nil/absent), computes
// bit positions MSB-down, and returns the resulting Encoding.
//
// Port of cpugen.rom/create-encoding (rom.clj lines 74-132).
//
// The key-fn order is: standalone signals sorted alphabetically first,
// then combinable groups in CombinableSignals order. The bit-position
// assignment starts at (TotalBits-1) for key-fns[0] and steps downward,
// so key-fns[0] gets the highest bits.
func CreateEncoding(slots []AssignMap, width int) *Encoding {
	groups := CombinableSignals(width)

	// Build the set of all signals that are covered by a combinable group.
	inGroup := map[Signal]bool{}
	for _, g := range groups {
		for _, s := range g {
			inGroup[s] = true
		}
	}

	// Collect standalone signals: appear in any slot AND are not in any group.
	// Clojure: (->> slots (mapcat keys) distinct sort (filter (complement all-combines)) ...)
	standaloneSet := map[Signal]bool{}
	for _, sl := range slots {
		for k := range sl {
			if !inGroup[k] {
				standaloneSet[k] = true
			}
		}
	}
	var standalone []Signal
	for s := range standaloneSet {
		standalone = append(standalone, s)
	}
	// Sort alphabetically by Signal string value — matches Clojure's (sort) on keywords.
	sort.Slice(standalone, func(i, j int) bool { return standalone[i] < standalone[j] })

	// Build fields: standalone first, then combinable groups.
	// This matches the Clojure key-fns construction order.
	var fields []Field

	for _, s := range standalone {
		fields = append(fields, buildSingletonField(s, slots))
	}
	for _, g := range groups {
		fields = append(fields, buildGroupField(g, slots))
	}

	// Compute TotalBits as sum of all field widths.
	totalBits := 0
	for _, f := range fields {
		totalBits += f.Width()
	}

	// Assign Hi/Lo positions. The Clojure code starts at (dec full-width)
	// and steps downward:
	//   left  = i
	//   right = (inc (- i width))  = i - width + 1
	//   next i = i - width
	//
	// So fields[0] gets Hi = totalBits-1 (the highest bit).
	hi := totalBits - 1
	for i := range fields {
		w := fields[i].Width()
		if w == 0 {
			// Zero-width field: both Hi and Lo are conventionally set to
			// a sentinel. We use hi+1 downto hi+2 (which is invalid but
			// signals "zero bits"). In practice CreateEncoding is only
			// called when fields have at least 1 distinct value.
			fields[i].Hi = hi
			fields[i].Lo = hi + 1
		} else {
			fields[i].Hi = hi
			fields[i].Lo = hi - w + 1
			hi -= w
		}
	}

	return &Encoding{
		TotalBits: totalBits,
		Fields:    fields,
	}
}

// buildSingletonField builds a Field for a single standalone signal.
//
// For NON-nillable signals: code 0 = absent/nil, codes 1,2,3... = distinct
// non-nil values in first-encountered order. encode-width = ceil(log2(N+1))
// where N is the number of distinct non-nil values.
//
// For NILLABLE signals (per NillableSignals): the nil/absent case maps to
// all-zeros binary by convention (NOT stored as code 0 in the Codes map).
// Codes 0,1,2... are assigned to the distinct non-nil values directly.
// encode-width = ceil(log2(N)) where N = count of distinct non-nil values.
// The Codes map for nillable fields does NOT contain the "" key.
//
// Port of Clojure create-encoding singleton key-fn path with nillable filter.
func buildSingletonField(s Signal, slots []AssignMap) Field {
	nillable := NillableSignals[s]

	if nillable {
		// Nillable: collect distinct non-nil values, assign codes 0,1,2...
		// The absent case (all zeros) is not stored in the Codes map.
		codes := map[string]int{}
		next := 0
		for _, sl := range slots {
			v := sl[s]
			if v == "" {
				continue
			}
			if _, ok := codes[v]; !ok {
				codes[v] = next
				next++
			}
		}
		return Field{Signal: s, Codes: codes}
	}

	// Non-nillable: nil is code 0, other values are 1,2,...
	codes := map[string]int{"": 0}
	next := 1
	for _, sl := range slots {
		v := sl[s]
		if v == "" {
			continue
		}
		if _, ok := codes[v]; !ok {
			codes[v] = next
			next++
		}
	}
	return Field{Signal: s, Codes: codes}
}

// buildGroupField builds a Field for a combinable group. The tuple key
// is the comma-joined values of all signals in the group for one slot.
// The empty string key represents "none of the group's signals are set".
//
// Port of Clojure create-encoding's group key-fn path.
func buildGroupField(g CombinableGroup, slots []AssignMap) Field {
	codes := map[string]int{"": 0} // "" = all-absent tuple
	next := 1
	for _, sl := range slots {
		key := tupleKey(g, sl)
		if key == "" {
			continue // maps to code 0
		}
		if _, ok := codes[key]; !ok {
			codes[key] = next
			next++
		}
	}
	return Field{Group: g, Codes: codes}
}

// tupleKey computes the tuple key for a combinable group from one
// slot's AssignMap. Returns "" if no signal in the group is set.
// The key is the comma-joined values: "val0,val1,...", where absent
// signals contribute an empty component.
//
// Example: group = {SigExMacsel1, SigWbMacsel1}, slot sets only
// SigExMacsel1="SEL_XBUS" → key = "SEL_XBUS,"
func tupleKey(g CombinableGroup, sl AssignMap) string {
	parts := make([]string, len(g))
	any := false
	for i, s := range g {
		parts[i] = sl[s]
		if parts[i] != "" {
			any = true
		}
	}
	if !any {
		return ""
	}
	return strings.Join(parts, ",")
}

// Encode produces the TotalBits-wide binary string for one slot, with
// bit fields laid out MSB-first in the string (string[0] = bit TotalBits-1,
// string[TotalBits-1] = bit 0). This matches the VHDL std_logic_vector
// literal convention.
//
// Returns an error if a field value is not found in the Codes map
// (which would indicate a slot seen at Encode time but not at
// CreateEncoding time — a programming error).
func (e *Encoding) Encode(sl AssignMap) (string, error) {
	if e.TotalBits == 0 {
		return "", nil
	}
	// Build a byte slice of '0'/'1', indexed as: out[0] = MSB = bit (TotalBits-1).
	// We write each field's code at the correct position.
	out := make([]byte, e.TotalBits)
	for i := range out {
		out[i] = '0'
	}

	for _, f := range e.Fields {
		w := f.Width()
		if w == 0 {
			continue
		}
		// Determine the tuple key for this field.
		var key string
		if f.Signal != "" {
			key = sl[f.Signal]
		} else {
			key = tupleKey(f.Group, sl)
		}

		code, ok := f.Codes[key]
		if !ok {
			if key == "" {
				// Nillable field: absent/nil case → all zeros (code 0 by convention).
				// The Clojure encoder uses (or (encoding ...) (repeat encode-width \0)).
				code = 0
			} else {
				return "", fmt.Errorf("encode: no code for key %q in field %v/%v", key, f.Signal, f.Group)
			}
		}

		// Write the code as a w-bit big-endian binary at positions Hi..Lo
		// in the bit vector. In the output string:
		//   out[TotalBits-1-bitPos] corresponds to bit bitPos.
		// Fields[i].Hi >= Fields[i].Lo; Hi is the most significant bit.
		for bit := 0; bit < w; bit++ {
			// bit 0 here = MSB of the code field = position Hi in the vector.
			bitPos := f.Hi - bit
			b := byte('0') + byte((code>>(w-1-bit))&1)
			out[e.TotalBits-1-bitPos] = b
		}
	}

	return string(out), nil
}
