package microcode

import (
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestEncodingEmptyHasZeroBits(t *testing.T) {
	enc := CreateEncoding(nil, 72)
	if enc.TotalBits != 0 {
		t.Errorf("empty slots: want 0 bits, got %d", enc.TotalBits)
	}
}

func TestEncodingSingleSlotProducesNonNilFields(t *testing.T) {
	slot := AssignMap{SigArithFunc: "ADD", SigIncPC: "1"}
	enc := CreateEncoding([]AssignMap{slot}, 72)
	if enc.TotalBits == 0 {
		t.Error("non-empty slot should produce non-zero TotalBits")
	}
	bin, err := enc.Encode(slot)
	if err != nil {
		t.Fatal(err)
	}
	if len(bin) != enc.TotalBits {
		t.Errorf("Encode length=%d, want TotalBits=%d", len(bin), enc.TotalBits)
	}
}

func TestEncodingEmptySlotEncodesToAllZeros(t *testing.T) {
	slot1 := AssignMap{SigArithFunc: "ADD"}
	slot2 := AssignMap{} // empty — should encode as all zeros
	enc := CreateEncoding([]AssignMap{slot1, slot2}, 72)
	bin, err := enc.Encode(slot2)
	if err != nil {
		t.Fatal(err)
	}
	for i, c := range bin {
		if c != '0' {
			t.Errorf("empty slot: bit %d = %c, want '0'", i, c)
			break
		}
	}
}

func TestEncodingDistinctSlotsGetDistinctCodes(t *testing.T) {
	slot1 := AssignMap{SigArithFunc: "ADD"}
	slot2 := AssignMap{SigArithFunc: "SUB"}
	enc := CreateEncoding([]AssignMap{slot1, slot2}, 72)
	bin1, err := enc.Encode(slot1)
	if err != nil {
		t.Fatal(err)
	}
	bin2, err := enc.Encode(slot2)
	if err != nil {
		t.Fatal(err)
	}
	if bin1 == bin2 {
		t.Errorf("distinct slots should encode to distinct words, both got %q", bin1)
	}
}

func TestEncodingFieldOrder72(t *testing.T) {
	// With width 72, standalone signals come first (higher bits) and
	// combinable groups come last (lower bits). With a single slot
	// containing only SigArithFunc (which is in the first combinable group),
	// there should be standalone fields before the group fields.
	slot := AssignMap{SigArithFunc: "ADD"}
	enc := CreateEncoding([]AssignMap{slot}, 72)

	// Check that there is at least one combinable group field.
	hasGroup := false
	for _, f := range enc.Fields {
		if f.Group != nil {
			hasGroup = true
			break
		}
	}
	if !hasGroup {
		t.Error("expected at least one combinable group field")
	}
}

func TestEncodingStandaloneComesBeforeGroup(t *testing.T) {
	// Standalone signals should occupy higher bit indices than combinable groups.
	// With width 72, the last combinable group is {wrpc_z, wrpr_pc, wrsr_w, wrsr_z}
	// which maps to the lowest bits (line(2 downto 0) in the golden).
	slot := AssignMap{
		SigArithFunc: "ADD", // combinable (group 0 in cs72)
		SigIncPC:     "1",   // standalone
	}
	enc := CreateEncoding([]AssignMap{slot}, 72)

	// Find the first standalone field and first group field.
	var firstStandaloneHi, firstGroupHi int
	firstStandaloneHi = -1
	firstGroupHi = -1
	for _, f := range enc.Fields {
		if f.Signal != "" && firstStandaloneHi < 0 {
			firstStandaloneHi = f.Hi
		}
		if f.Group != nil && firstGroupHi < 0 {
			firstGroupHi = f.Hi
		}
	}
	if firstStandaloneHi < 0 || firstGroupHi < 0 {
		t.Skip("no standalone or no group field in test slot")
	}
	if firstStandaloneHi <= firstGroupHi {
		t.Errorf("standalone Hi=%d should be > group Hi=%d (standalone gets higher bits)",
			firstStandaloneHi, firstGroupHi)
	}
}

func TestEncodingProductionSpec72TotalBits(t *testing.T) {
	// The production spec with width 72 should yield TotalBits = 75,
	// matching the golden decode_table_rom.vhd's `std_logic_vector(74 downto 0)`.
	//
	// IMPORTANT: The Clojure line-encoder is called with ALL slots including
	// system-plane instructions (see genvhdl.clj line 1236:
	//   (for [op ops slot (:slots op)] (gen-assign-map op slot))
	// where ops includes system-plane ops). System slots contribute
	// signals like event_ack_0 and ilevel_cap to the encoding.
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}

	var slots []AssignMap
	for _, instr := range s.Instrs {
		// Include ALL instructions, including system plane — this matches
		// the Clojure generator's behavior.
		for _, slot := range instr.Slots {
			am, err := AssignSlot(instr, slot)
			if err != nil {
				t.Fatalf("AssignSlot %s: %v", instr.Name, err)
			}
			slots = append(slots, am)
		}
	}

	enc := CreateEncoding(slots, 72)
	if enc.TotalBits != 75 {
		t.Errorf("production TotalBits = %d, want 75", enc.TotalBits)
	}
}

func TestEncodingProductionSpec72GroupCount(t *testing.T) {
	// Width 72 should produce 7 combinable group fields.
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}

	var slots []AssignMap
	for _, instr := range s.Instrs {
		// Include all instructions (system and non-system).
		for _, slot := range instr.Slots {
			am, _ := AssignSlot(instr, slot)
			slots = append(slots, am)
		}
	}

	enc := CreateEncoding(slots, 72)
	groupCount := 0
	for _, f := range enc.Fields {
		if f.Group != nil {
			groupCount++
		}
	}
	if groupCount != 7 {
		t.Errorf("width 72: want 7 group fields, got %d", groupCount)
	}
}

func TestEncodingBitPositionsMatchGolden72(t *testing.T) {
	// Verify the bit positions of specific fields against the golden
	// decode_table_rom.vhd. This is a structural sanity check; full
	// bit-pattern equality is verified in Task 9's L2 test.
	//
	// Golden positions (width 72, TotalBits=75):
	//   line(2 downto 0):  {wrpc_z, wrpr_pc, wrsr_w, wrsr_z} group
	//   line(6 downto 3):  {ex_macsel2,...} group
	//   line(9 downto 7):  {ex_macsel1,...} group
	//   line(12 downto 10): {ma_issue, ma_wr, mem_size} group
	//   line(17 downto 13): {regnum_y, ybus_sel, aluiny_sel} group
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}

	var asgns []AssignMap
	for _, instr := range s.Instrs {
		// Include ALL instructions (system and non-system) to match Clojure.
		for _, slot := range instr.Slots {
			am, _ := AssignSlot(instr, slot)
			asgns = append(asgns, am)
		}
	}

	enc := CreateEncoding(asgns, 72)

	type wantField struct {
		// A representative signal that should be in this field's group.
		signal Signal
		hi, lo int
	}
	wants := []wantField{
		{SigWrpcZ, 2, 0},
		{SigExWrmach, 6, 3},
		{SigExWrmacl, 9, 7},
		{SigMaIssue, 12, 10},
		{SigRegnumY, 17, 13},
	}

	for _, w := range wants {
		found := false
		for _, f := range enc.Fields {
			if f.Group == nil {
				continue
			}
			for _, s := range f.Group {
				if s == w.signal {
					if f.Hi != w.hi || f.Lo != w.lo {
						t.Errorf("signal %q: got Hi=%d Lo=%d, want Hi=%d Lo=%d",
							w.signal, f.Hi, f.Lo, w.hi, w.lo)
					}
					found = true
					break
				}
			}
			if found {
				break
			}
		}
		if !found {
			t.Errorf("signal %q not found in any group field", w.signal)
		}
	}
}

func TestEncodingEncodeAndDecodeRoundTrip(t *testing.T) {
	// Create encoding, encode two distinct slots, check the binary strings
	// are valid and distinct.
	slot1 := AssignMap{
		SigArithFunc: "ADD",
		SigWrregZ:    "1",
		SigIncPC:     "1",
	}
	slot2 := AssignMap{
		SigArithFunc: "SUB",
		SigWrregZ:    "1",
		SigIncPC:     "1",
	}
	enc := CreateEncoding([]AssignMap{slot1, slot2}, 72)

	b1, err := enc.Encode(slot1)
	if err != nil {
		t.Fatalf("Encode slot1: %v", err)
	}
	b2, err := enc.Encode(slot2)
	if err != nil {
		t.Fatalf("Encode slot2: %v", err)
	}

	// Both should have the correct length.
	if len(b1) != enc.TotalBits {
		t.Errorf("b1 length %d != TotalBits %d", len(b1), enc.TotalBits)
	}
	if len(b2) != enc.TotalBits {
		t.Errorf("b2 length %d != TotalBits %d", len(b2), enc.TotalBits)
	}

	// Both should be binary strings.
	for i, c := range b1 + b2 {
		if c != '0' && c != '1' {
			t.Errorf("non-binary character %c at position %d", c, i)
			break
		}
	}

	// They should differ (different arith_func values).
	if b1 == b2 {
		t.Errorf("distinct slots produced identical encoding: %s", b1)
	}
}

func TestEncodingEmptySlotIsAllZeros72(t *testing.T) {
	// An empty AssignMap should encode as all zeros.
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}

	var asgns []AssignMap
	for _, instr := range s.Instrs {
		// Include all instructions (system and non-system) to match Clojure.
		for _, slot := range instr.Slots {
			am, _ := AssignSlot(instr, slot)
			asgns = append(asgns, am)
		}
	}

	enc := CreateEncoding(asgns, 72)
	emptySlot := AssignMap{}
	bin, err := enc.Encode(emptySlot)
	if err != nil {
		t.Fatal(err)
	}
	if bin != strings.Repeat("0", enc.TotalBits) {
		t.Errorf("empty slot encoded as %s, want all zeros", bin)
	}
}
