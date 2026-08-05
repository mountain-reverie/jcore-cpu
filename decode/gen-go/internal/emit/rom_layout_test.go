package emit

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/microcode"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestROMTemplateMatchesEncoding cross-checks the EMITTED decode_table_rom.vhd
// architecture text against the Encoding that packed the ROM words, for every
// instruction-set variant (base and each additive overlay).
//
// WHY THIS TEST EXISTS — and why it must not be "simplified" into a structural
// check.
//
// decode_table_rom.vhd has two halves that must agree about one thing: the ROM
// word's bit-field layout. The `microcode_rom` constant is PACKED by
// microcode.CreateEncoding. The architecture body READS it back with
// `with line(Hi downto Lo) select ... when "<code>"`. For a long time the
// reading half was hand-written VHDL in the template with the base spec's
// layout baked in as literals, while the packing half stayed data-driven. The
// two silently diverged the moment any spec changed the Encoding: the sh4
// overlay grew the word from 75 to 85 bits, added four fields, and — because
// codes are assigned in first-encounter order over the slot list, and an
// overlay interleaves instructions rather than appending them — reshuffled the
// per-value codes even in fields whose bit position had not moved. Every
// control signal was then decoded from the wrong bits and/or the wrong codes,
// and a J4 built on the ROM decoder could not reach its bootloader banner.
//
// THE TESTS THAT ALREADY EXISTED COULD NOT SEE THIS:
//
//   - The synthetic >256-slot fixture from the rom-addr-widening work asserts
//     ROM array bounds and address width. It says nothing about field layout.
//
//   - model.TestDecoderDifferentialROM decodes each ROM word back to an
//     AssignMap and compares it to AssignSlot. But it decodes using the SAME
//     Encoding object that packed the word. That round-trip is self-consistent
//     by construction and can never observe that the VHDL reader uses a
//     different layout — the VHDL text is not an input to it at all.
//
// The invariant that was actually violated is a relationship between two
// INDEPENDENTLY PRODUCED artefacts: the Encoding, and the generated VHDL text.
// So this test parses the generated text. Any replacement that stops reading
// the emitted file, or stops enumerating every variant, reopens the hole.
func TestROMTemplateMatchesEncoding(t *testing.T) {
	for _, variant := range []struct{ name, overlay string }{
		{"base", ""},
		{"sh4", "../../spec/sh4"},
		{"sh2a", "../../spec/sh2a"},
	} {
		t.Run(variant.name, func(t *testing.T) {
			var s *spec.Spec
			var err error
			if variant.overlay == "" {
				s, err = spec.Load("../../spec")
			} else {
				s, err = spec.LoadProfile("../../spec", variant.overlay)
			}
			if err != nil {
				t.Fatal(err)
			}
			d, err := model.Build(s, 72, model.IllegalFull)
			if err != nil {
				t.Fatal(err)
			}
			dir := t.TempDir()
			if err := All(d, dir); err != nil {
				t.Fatal(err)
			}
			body := readArchBody(t, filepath.Join(dir, "decode_table_rom.vhd"))
			checkROMLayout(t, d.ROM.Enc, body)
		})
	}
}

// romField is one field of the Encoding flattened to what the VHDL reader can
// observe: its bit range and the set of codes it can legally present.
type romFieldRange struct {
	hi, lo, width int
}

func checkROMLayout(t *testing.T, enc *microcode.Encoding, body string) {
	t.Helper()

	valid := map[romFieldRange]bool{}
	byRange := map[[2]int]microcode.Field{}
	for _, f := range enc.Fields {
		if f.Width() == 0 {
			continue // carries no bits; the reader emits a constant assignment
		}
		valid[romFieldRange{f.Hi, f.Lo, f.Width()}] = true
		byRange[[2]int{f.Hi, f.Lo}] = f
	}

	// 1. Every `line(...)` reference must name exactly one Encoding field.
	//    Catches misalignment, off-by-N, straddling two fields, and reading
	//    bits that the packer never writes.
	referenced := map[[2]int]bool{}
	refRe := regexp.MustCompile(`line\((\d+)(?: downto (\d+))?\)`)
	for _, m := range refRe.FindAllStringSubmatch(body, -1) {
		hi := atoi(t, m[1])
		lo := hi
		if m[2] != "" {
			lo = atoi(t, m[2])
		}
		if !valid[romFieldRange{hi, lo, hi - lo + 1}] {
			t.Errorf("architecture reads line(%d downto %d), which is not an "+
				"Encoding field boundary (fields: %s)", hi, lo, describeFields(enc))
			continue
		}
		referenced[[2]int{hi, lo}] = true
	}

	// 2. Every Encoding field must be read. Catches an overlay-only field
	//    (e.g. sh4's mmu_reg_sel / mmu_reg_wr / tlb_wr) that the packer emits
	//    but the architecture never decodes, leaving the signal undriven.
	for r := range byRange {
		if !referenced[r] {
			f := byRange[r]
			t.Errorf("Encoding field %s at line(%d downto %d) is packed into the "+
				"ROM word but never read by the architecture", fieldName(f), r[0], r[1])
		}
	}

	// 3. Every `when "<code>"` literal must be the width of the field its
	//    block selects on, and must be a code the field actually assigns.
	//    Catches a stale literal that still fits (base-width code on a widened
	//    field) and a code that no value maps to.
	// 4. Every non-default code of every field must be named by some arm, or
	//    else be covered by `when others`. Codes that fall into `others`
	//    silently are the failure mode when an overlay adds a new value to an
	//    existing field.
	blockRe := regexp.MustCompile(`(?s)with line\((\d+)(?: downto (\d+))?\) select\s*\n\s*([\w.]+) <=\s*\n(.*?);\n`)
	seen := map[[2]int]map[int]bool{}
	hasOthers := map[[2]int]bool{}
	for _, m := range blockRe.FindAllStringSubmatch(body, -1) {
		hi := atoi(t, m[1])
		lo := hi
		if m[2] != "" {
			lo = atoi(t, m[2])
		}
		width := hi - lo + 1
		f, ok := byRange[[2]int{hi, lo}]
		if !ok {
			continue // already reported by check 1
		}
		if seen[[2]int{hi, lo}] == nil {
			seen[[2]int{hi, lo}] = map[int]bool{}
		}
		for _, line := range strings.Split(m[4], "\n") {
			line = strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(line), ","))
			if line == "" {
				continue
			}
			idx := strings.LastIndex(line, " when ")
			if idx < 0 {
				t.Errorf("%s: unparsable selector arm %q", m[3], line)
				continue
			}
			choice := strings.TrimSpace(line[idx+len(" when "):])
			if choice == "others" {
				hasOthers[[2]int{hi, lo}] = true
				continue
			}
			for _, c := range strings.Split(choice, "|") {
				c = strings.Trim(strings.TrimSpace(c), `"`)
				if len(c) != width {
					t.Errorf("%s: arm code %q is %d bits but line(%d downto %d) is %d bits",
						m[3], c, len(c), hi, lo, width)
					continue
				}
				n := 0
				for _, ch := range c {
					n = n<<1 | int(ch-'0')
				}
				if n >= len(f.Codes) {
					// Codes are dense 0..n-1, so a code at or past the count
					// is one no value can produce.
					t.Errorf("%s: arm code %q (%d) is not assigned to any value of field %s (%d codes)",
						m[3], c, n, fieldName(f), len(f.Codes))
				}
				seen[[2]int{hi, lo}][n] = true
			}
		}
	}
	for r, f := range byRange {
		if !hasOthers[r] && len(seen[r]) > 0 && len(seen[r]) < len(f.Codes) {
			t.Errorf("field %s at line(%d downto %d): %d of %d codes named and no "+
				"`when others` arm — some codes decode to nothing",
				fieldName(f), r[0], r[1], len(seen[r]), len(f.Codes))
		}
	}
}

func readArchBody(t *testing.T, path string) string {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	b := string(raw)
	// Everything after the microcode_rom constant, i.e. the architecture body.
	i := strings.Index(b, "\nbegin\n")
	if i < 0 {
		t.Fatalf("%s: no architecture body", path)
	}
	return b[i:]
}

func fieldName(f microcode.Field) string {
	if f.Group != nil {
		return fmt.Sprint(f.Group)
	}
	return string(f.Signal)
}

func describeFields(enc *microcode.Encoding) string {
	var p []string
	for _, f := range enc.Fields {
		p = append(p, fmt.Sprintf("%s=%d..%d", fieldName(f), f.Hi, f.Lo))
	}
	return strings.Join(p, " ")
}

func atoi(t *testing.T, s string) int {
	t.Helper()
	n := 0
	for _, c := range s {
		n = n*10 + int(c-'0')
	}
	return n
}
