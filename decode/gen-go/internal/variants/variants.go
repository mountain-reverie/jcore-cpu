// Package variants reads components/cpu/variants.toml, the authoritative
// definition of what distinguishes each CPU variant. Both cpugen (for Make
// consumers) and jcore-soc's socgen read this table; nothing else may define
// a variant.
package variants

import (
	"fmt"
	"os"
	"sort"

	"github.com/BurntSushi/toml"
)

type Variant struct {
	Name       string            `toml:"-"`
	Generics   map[string]string `toml:"generics"`
	Overlay    string            `toml:"overlay"`
	ExtraFiles []string          `toml:"extra_files"`
	ConfigFile string            `toml:"config_file"`
}

func Load(path string) (map[string]Variant, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("variants: %w", err)
	}
	var raw map[string]Variant
	if err := toml.Unmarshal(b, &raw); err != nil {
		return nil, fmt.Errorf("variants: parsing %s: %w", path, err)
	}
	out := make(map[string]Variant, len(raw))
	for name, v := range raw {
		v.Name = name
		if v.Generics == nil {
			v.Generics = map[string]string{}
		}
		if _, bad := v.Generics["MMU_ARCH"]; bad {
			return nil, fmt.Errorf("variants: %s sets MMU_ARCH; PRIV_ARCH implies MMU", name)
		}
		if v.ConfigFile == "" {
			return nil, fmt.Errorf("variants: %s has no config_file", name)
		}
		out[name] = v
	}
	return out, nil
}

func Names(m map[string]Variant) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
