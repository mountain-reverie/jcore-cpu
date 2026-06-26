package insns

import (
	"github.com/BurntSushi/toml"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

type Timing struct {
	Issue   int `toml:"issue"`
	Latency int `toml:"latency"`
}

type Table struct {
	Units     map[string]int    `toml:"units"`
	Overrides map[string]Timing `toml:"overrides"`
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
	return &t, nil
}

// normOpcode strips spaces and replaces variable bits (non-0/1 chars) with '0'.
func normOpcode(s string) string {
	out := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c == ' ' {
			continue
		}
		if c != '0' && c != '1' {
			c = '0'
		}
		out = append(out, c)
	}
	return string(out)
}

func (t *Table) For(in spec.Instr) Timing {
	if t.Overrides != nil {
		if ov, ok := t.Overrides[normOpcode(in.Opcode)]; ok {
			return ov
		}
	}
	lat := len(in.Slots)
	if lat < 1 {
		lat = 1
	}
	issue := 1
	if u := unitOf(in); u != "" && t.Units != nil {
		if c, ok := t.Units[u]; ok && c > 0 {
			issue = c
			if c > lat {
				lat = c
			}
		}
	}
	return Timing{Issue: issue, Latency: lat}
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
