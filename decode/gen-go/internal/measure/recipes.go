package measure

import (
	"github.com/BurntSushi/toml"
)

type Recipe struct {
	Template   string
	Ptr        string
	Region     uint32
	Loop       int
	Measurable bool
	Issue      int
	Latency    int
	Why        string
}

type Recipes struct {
	Default  Recipe
	ByOpcode map[string]Recipe
}

type recipesFile struct {
	Default   Recipe
	Overrides map[string]Recipe
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
		if v.Measurable == false && v.Why == "" && v.Template == "" {
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
