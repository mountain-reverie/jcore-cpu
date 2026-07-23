package insns

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/BurntSushi/toml"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// Cell holds an issue/latency value that is either a fixed cycle count
// (Variable == false) or a lower-bound "n+" variable-latency count
// (Variable == true), as produced by the measure CLI for data-dependent
// timing (e.g. multi-cycle shifts, divides, cache misses).
type Cell struct {
	N        int
	Variable bool
}

// II builds a fixed (non-variable) Cell for n cycles.
func II(n int) Cell { return Cell{N: n} }

// ParseCell parses either a bare integer ("8") or a variable-latency
// string ("2+") into a Cell.
func ParseCell(s string) Cell {
	s = strings.TrimSpace(s)
	if strings.HasSuffix(s, "+") {
		n, _ := strconv.Atoi(strings.TrimSuffix(s, "+"))
		return Cell{N: n, Variable: true}
	}
	n, _ := strconv.Atoi(s)
	return Cell{N: n}
}

func (c Cell) String() string {
	if c.Variable {
		return fmt.Sprintf("%d+", c.N)
	}
	return strconv.Itoa(c.N)
}

// jsonValue returns the value to emit into the generated JSON doc: a bare
// number for fixed cells, the "n+" string for variable cells.
func (c Cell) jsonValue() any {
	if c.Variable {
		return c.String()
	}
	return json.Number(strconv.Itoa(c.N))
}

// UnmarshalTOML implements toml.Unmarshaler so a Cell field can decode
// either a TOML integer or a "n+" string.
func (c *Cell) UnmarshalTOML(data any) error {
	switch v := data.(type) {
	case int64:
		*c = Cell{N: int(v)}
	case int:
		*c = Cell{N: v}
	case string:
		*c = ParseCell(v)
	default:
		return fmt.Errorf("cell: unsupported TOML value %T (%v)", data, data)
	}
	return nil
}

type Timing struct {
	Issue   Cell   `toml:"issue"`
	Latency Cell   `toml:"latency"`
	Source  string `toml:"source"`
}

type Table struct {
	Units     map[string]int    `toml:"units"`
	Overrides map[string]Timing `toml:"overrides"`
	Measured  map[string]Timing `toml:"-"`
}

// measuredFile is the on-disk shape of a "<variant>.measured.toml" table,
// as produced by the measure CLI: a flat map of opcode -> Timing under
// the "entries" key.
type measuredFile struct {
	Entries map[string]Timing `toml:"entries"`
}

func LoadTable(path string) (*Table, error) {
	var t Table
	if _, err := toml.DecodeFile(path, &t); err != nil {
		return nil, err
	}
	if t.Units == nil {
		t.Units = map[string]int{}
	}
	if t.Overrides == nil {
		t.Overrides = map[string]Timing{}
	}
	t.Measured = map[string]Timing{}

	measuredPath := measuredSiblingPath(path)
	var mf measuredFile
	if _, err := toml.DecodeFile(measuredPath, &mf); err == nil {
		for k, v := range mf.Entries {
			t.Measured[normOpcode(k)] = v
		}
	}

	return &t, nil
}

// measuredSiblingPath derives "<variant>.measured.toml" from
// "<variant>.toml" in the same directory.
func measuredSiblingPath(path string) string {
	dir := filepath.Dir(path)
	base := filepath.Base(path)
	base = strings.TrimSuffix(base, ".toml")
	return filepath.Join(dir, base+".measured.toml")
}

// normOpcode strips spaces and preserves variable-bit letters for code field + override keys.
func normOpcode(s string) string {
	out := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		if s[i] != ' ' {
			out = append(out, s[i])
		}
	}
	return string(out)
}

// For resolves the timing of in, preferring a measured value, then a
// hand-written override, then falling back to unit-derived (or default
// 1/1) timing.
func (t *Table) For(in spec.Instr) Timing {
	key := normOpcode(in.Opcode)
	if t.Measured != nil {
		if mv, ok := t.Measured[key]; ok {
			return mv
		}
	}
	if t.Overrides != nil {
		if ov, ok := t.Overrides[key]; ok {
			return ov
		}
	}
	lat := 1
	issue := 1
	if u := unitOf(in); u != "" && t.Units != nil {
		if c, ok := t.Units[u]; ok && c > 0 {
			issue = c
			if c > lat {
				lat = c
			}
		}
	}
	return Timing{Issue: II(issue), Latency: II(lat)}
}

// unitOf returns the functional unit an instruction uses, based on slot signals.
// "mac_op" key present → "mult"; Task 8 extends this for "shift"/"divide".
func unitOf(in spec.Instr) string {
	for _, s := range in.Slots {
		if _, ok := s["mac_op"]; ok {
			return "mult"
		}
	}
	return ""
}
