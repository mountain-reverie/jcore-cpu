package model

import (
	"sync"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// illegalVariantCache memoizes the (spec, overlays, width, mode) -> *Decoder
// builds shared by the illegal_* test files in this package.
//
// model.Build() runs Quine-McCluskey minimisation over the whole
// instruction set and is expensive (multiple seconds per variant). Several
// test functions in this package independently build the identical base,
// sh2a and sh4 variants at IllegalFull to check different properties of the
// resulting decoder (safety, completeness, nibble isolation). Rebuilding
// each variant once per test function multiplies that cost by the number
// of call sites for no benefit, since Build is a pure function of its
// inputs and none of these tests mutate the returned *Decoder — they only
// read Body.IllegalInstr (Eval and Arms). Building each distinct input
// combination once and sharing the *Decoder across tests removes that
// duplication without weakening any assertion.
//
// Go runs test functions within a package sequentially by default, so a
// simple mutex-guarded map is sufficient; it also happens to be safe if a
// future change parallelizes these tests via t.Parallel().
var (
	illegalVariantCacheMu sync.Mutex
	illegalVariantCache   = map[illegalVariantKey]*illegalVariantResult{}
)

type illegalVariantKey struct {
	overlay string // "" for base, else the overlay directory name (e.g. "sh2a")
	width   int
	mode    IllegalMode
}

type illegalVariantResult struct {
	spec *spec.Spec
	dec  *Decoder
}

// buildIllegalVariant loads the named overlay variant ("" for base J2,
// "sh2a", or "sh4") against ../../spec and builds its Decoder at the given
// width/mode, caching the result for reuse across test functions in this
// package. Callers must not mutate the returned *spec.Spec or *Decoder.
func buildIllegalVariant(t *testing.T, overlay string, width int, mode IllegalMode) (*spec.Spec, *Decoder) {
	t.Helper()

	key := illegalVariantKey{overlay: overlay, width: width, mode: mode}

	illegalVariantCacheMu.Lock()
	defer illegalVariantCacheMu.Unlock()

	if r, ok := illegalVariantCache[key]; ok {
		return r.spec, r.dec
	}

	var s *spec.Spec
	var err error
	if overlay == "" {
		s, err = spec.Load("../../spec")
	} else {
		s, err = spec.LoadProfile("../../spec", "../../spec/"+overlay)
	}
	if err != nil {
		t.Fatalf("load %q: %v", overlay, err)
	}
	d, err := Build(s, width, mode)
	if err != nil {
		t.Fatalf("Build %q: %v", overlay, err)
	}

	illegalVariantCache[key] = &illegalVariantResult{spec: s, dec: d}
	return s, d
}
