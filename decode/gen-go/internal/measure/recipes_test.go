package measure

import "testing"

func TestLoadRecipesAndLookup(t *testing.T) {
	r, err := LoadRecipes("testdata/recipes_min.toml")
	if err != nil { t.Fatal(err) }
	// default applies to an unlisted opcode
	d := r.For("0011nnnnmmmm1100")
	if d.Template != "default" { t.Fatalf("want default template, got %q", d.Template) }
	// hand entry
	h := r.For("0000000000011011") // sleep
	if h.Measurable || h.Latency != 3 || h.Why == "" {
		t.Fatalf("sleep hand entry wrong: %+v", h)
	}
}
