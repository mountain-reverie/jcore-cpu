package measure

import (
	"github.com/BurntSushi/toml"
)

type Recipe struct {
	Template   string `toml:"template"`
	Ptr        string `toml:"ptr"`
	Region     uint32 `toml:"region"`
	Loop       int    `toml:"loop"`
	Measurable bool   `toml:"measurable"`
	Issue      int    `toml:"issue"`
	Latency    int    `toml:"latency"`
	Why        string `toml:"why"`
}

type Recipes struct {
	Default  Recipe
	ByOpcode map[string]Recipe
}

type recipesFile struct {
	Default   Recipe            `toml:"default"`
	Overrides map[string]Recipe `toml:"overrides"`
}

func LoadRecipes(path string) (*Recipes, error) {
	var f recipesFile
	if _, err := toml.DecodeFile(path, &f); err != nil {
		return nil, err
	}
	if f.Default.Template == "" {
		f.Default = Recipe{Template: "default"}
	}
	// bare [overrides."x"] entry names no template but measurable
	// still means "use default template + measurable".
	for k, v := range f.Overrides {
		if !v.Measurable && v.Why == "" && v.Template == "" {
			// not hand entry, not custom template: treat as default+measurable
			v.Measurable = true
			v.Template = f.Default.Template
			f.Overrides[k] = v
		}
	}
	return &Recipes{Default: f.Default, ByOpcode: f.Overrides}, nil
}

func (r *Recipes) For(opcodeNorm string) Recipe {
	rec, ok := r.ByOpcode[opcodeNorm]
	if ok {
		return rec
	}
	d := r.Default
	d.Measurable = true
	return d
}
