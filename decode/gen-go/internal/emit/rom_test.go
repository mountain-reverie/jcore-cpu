package emit

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestROMBitPatternEquality72 is the M3 Task 9 L2 verification gate.
// It renders decode_table_rom.vhd at width 72, extracts the ROM constant
// entries as map[address]bitstring, and compares them byte-for-byte against
// the frozen Clojure golden file. A mismatch is reported per-address so
// that diagnostic context (bit widths, encoding differences) is clear.
func TestROMBitPatternEquality72(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}
	d, err := model.Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}

	tmpl, err := newTemplates()
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	if err := tmpl.ExecuteTemplate(&buf, "decode_table_rom.vhd.tmpl", d); err != nil {
		t.Fatal(err)
	}

	got := parseROMBits(t, buf.String())

	goldenSrc, err := os.ReadFile("../../testdata/golden/clj/decode_table_rom.vhd")
	if err != nil {
		t.Fatal(err)
	}
	want := parseROMBits(t, string(goldenSrc))

	if len(got) == 0 {
		t.Fatal("generated ROM is empty — romLines parsing yielded no entries")
	}
	if len(want) == 0 {
		t.Fatal("golden ROM is empty — romLines parsing yielded no entries")
	}

	// Compare per-address for diagnostic clarity.
	failures := 0
	for addr := 0; addr < 256; addr++ {
		g, wOK := got[addr]
		w, wantOK := want[addr]
		if !wantOK && !wOK {
			continue // both unused — fine
		}
		if !wantOK {
			t.Errorf("addr %d: generated has %q but golden has nothing", addr, g)
			failures++
			continue
		}
		if !wOK {
			t.Errorf("addr %d: golden has %q but generated has nothing", addr, w)
			failures++
			continue
		}
		if g != w {
			t.Errorf("addr %d:\n  got  %q\n  want %q", addr, g, w)
			failures++
		}
		if failures >= 20 {
			t.Errorf("... (too many failures, stopping)")
			return
		}
	}
}

// TestDecodeTableROMAgainstClojureGolden is the L1 structural test (full
// byte-for-byte comparison after normalization). Verifies that the complete
// decode_table_rom.vhd file matches the Clojure golden including all
// static VHDL boilerplate.
func TestDecodeTableROMAgainstClojureGolden(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}
	d, err := model.Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}

	tmpDir := t.TempDir()
	outDir := fmt.Sprintf("%s/out", tmpDir)
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		t.Fatal(err)
	}

	tmpl, err := newTemplates()
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	if err := tmpl.ExecuteTemplate(&buf, "decode_table_rom.vhd.tmpl", d); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(fmt.Sprintf("%s/decode_table_rom.vhd", outDir), buf.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}

	goldDir := fmt.Sprintf("%s/gold", tmpDir)
	if err := os.MkdirAll(goldDir, 0o755); err != nil {
		t.Fatal(err)
	}
	src, err := os.ReadFile("../../testdata/golden/clj/decode_table_rom.vhd")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(fmt.Sprintf("%s/decode_table_rom.vhd", goldDir), src, 0o644); err != nil {
		t.Fatal(err)
	}

	runNormalizeAndDiff(t, outDir, goldDir, "decode_table_rom.vhd")
}

// TestROMStructuralIntegrityWidth64 exercises the width-64 code path
// without a Clojure golden (no `lein` available in this environment to
// regenerate one). The test catches regressions in our width-64 code
// path by asserting structural invariants that any correct ROM must
// satisfy, even if we can't verify byte-equality against Clojure:
//
//   - Build(s, 64) succeeds.
//   - The ROM is 256 entries.
//   - Every ROM word is the same width (66 bits for our current cs64).
//   - Width-64 ROM is narrower than width-72 ROM (this is the whole point).
//   - Every word is well-formed binary.
//
// Note: structural correctness does NOT imply byte-equality with a
// Clojure-generated width-64 ROM. M5's Layer 3 differential simulation
// would catch a semantic divergence; until then this test is regression
// insurance, not a correctness gate.
func TestROMStructuralIntegrityWidth64(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}
	d64, err := model.Build(s, 64)
	if err != nil {
		t.Fatal(err)
	}
	d72, err := model.Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if d64.ROM == nil {
		t.Fatal("width-64 Build produced nil ROM")
	}
	if len(d64.ROM.Words) != 256 {
		t.Errorf("width-64 ROM has %d words, want 256", len(d64.ROM.Words))
	}
	if d64.ROM.TotalBits >= d72.ROM.TotalBits {
		t.Errorf("width-64 ROM (%d bits) not narrower than width-72 ROM (%d bits)",
			d64.ROM.TotalBits, d72.ROM.TotalBits)
	}
	bitRE := regexp.MustCompile(`^[01]*$`)
	for i, w := range d64.ROM.Words {
		if len(w.Bits) != d64.ROM.TotalBits {
			t.Errorf("addr %d: bit string length %d, want %d",
				i, len(w.Bits), d64.ROM.TotalBits)
		}
		if !bitRE.MatchString(w.Bits) {
			t.Errorf("addr %d: bit string %q contains non-binary characters", i, w.Bits)
		}
	}
}

// romEntryRE matches lines like:
//   0 => "0101...", -- CLRT
//   4 => "...", 5 => "...", 6 => "...", 7 => "...", -- RTE
//   254 => "000...000", 255 => "000...000");
// We extract all addr => "bits" pairs from each line.
var romEntryRE = regexp.MustCompile(`(\d+)\s*=>\s*"([01]+)"`)

// parseROMBits scans a VHDL file for the microcode_rom constant and
// returns a map from address to bit-pattern string.
func parseROMBits(t *testing.T, src string) map[int]string {
	t.Helper()
	result := make(map[int]string)

	inROM := false
	scanner := bufio.NewScanner(strings.NewReader(src))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.Contains(line, "constant microcode_rom") {
			inROM = true
		}
		if !inROM {
			continue
		}
		matches := romEntryRE.FindAllStringSubmatch(line, -1)
		for _, m := range matches {
			addr, err := strconv.Atoi(m[1])
			if err != nil || addr < 0 || addr > 255 {
				t.Errorf("invalid ROM address %q in line: %s", m[1], line)
				continue
			}
			result[addr] = m[2]
		}
		// Stop scanning after the closing ");" of the ROM constant.
		if inROM && strings.Contains(line, ");") {
			break
		}
	}
	return result
}
