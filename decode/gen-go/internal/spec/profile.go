// decode/gen-go/internal/spec/profile.go
package spec

import (
	"fmt"

	"github.com/BurntSushi/toml"
)

// Profile is an optional per-variant overlay applied AFTER base+overlays load.
// Today it only drops instructions; the dropped opcodes are routed to the
// illegal-instruction trap by the model layer.
type Profile struct {
	Drop []string `toml:"drop"`
}

// ReadProfile decodes a profile TOML file.
func ReadProfile(path string) (Profile, error) {
	var p Profile
	if _, err := toml.DecodeFile(path, &p); err != nil {
		return Profile{}, fmt.Errorf("read profile %s: %w", path, err)
	}
	return p, nil
}

// ApplyDrops removes each named instruction from s.Instrs and records it in
// s.Dropped (preserving its opcode for illegal-routing). Every name must match
// exactly one loaded instruction.
func ApplyDrops(s *Spec, names []string) error {
	for _, name := range names {
		idx := -1
		for i := range s.Instrs {
			if s.Instrs[i].Name == name {
				idx = i
				break
			}
		}
		if idx < 0 {
			return fmt.Errorf("drop: instruction %q not found in spec", name)
		}
		s.Dropped = append(s.Dropped, s.Instrs[idx])
		s.Instrs = append(s.Instrs[:idx], s.Instrs[idx+1:]...)
	}
	return nil
}
