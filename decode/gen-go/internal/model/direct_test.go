package model

import (
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestBuildDirectProducesImpBits(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if d.Direct == nil {
		t.Fatal("Build did not produce Direct")
	}
	// We expect SOME imp_bit_N signals — the Clojure golden has 173.
	// Our port should be in the same order of magnitude.
	if got := len(d.Direct.ImpBits); got < 50 || got > 500 {
		t.Errorf("ImpBits count = %d, expected 50..500", got)
	}
	// Every imp_bit name must start with "imp_bit_".
	for _, ib := range d.Direct.ImpBits {
		if !strings.HasPrefix(ib.Name, "imp_bit_") {
			t.Errorf("imp_bit name %q malformed", ib.Name)
		}
	}
	// Every output expr should have an LHS that's a known signal path.
	if len(d.Direct.OutputExprs) == 0 {
		t.Error("DirectDecoder has no OutputExprs")
	}
	t.Logf("ImpBits: %d", len(d.Direct.ImpBits))
	t.Logf("OutputExprs: %d", len(d.Direct.OutputExprs))
	t.Logf("CondSigs: %d", len(d.Direct.CondSigs))
}

// TestBuildDirectSemanticSpotChecks guards against the classes of bugs
// fixed in commits 44b1481 (T/NT → t_bcc translation), 60e2a53
// (per-signal defaults), and the SigMacBusy default fix. Each property
// below corresponds to one of those bugs reappearing.
func TestBuildDirectSemanticSpotChecks(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}

	var macBusy *OutputExpr
	var sawTBcc bool
	for i := range d.Direct.OutputExprs {
		o := &d.Direct.OutputExprs[i]
		if o.LHS == "mac_busy" {
			macBusy = o
		}
		// Any output expression referencing t_bcc means the T/NT
		// conditional translation is active. Conditional branches
		// (BT/BF) drive their conditionals through t_bcc.
		if strings.Contains(o.Expr, "t_bcc") {
			sawTBcc = true
		}
		if o.IsMux && o.Mux != nil {
			if strings.Contains(o.Mux.Default, "t_bcc") {
				sawTBcc = true
			}
			for _, arm := range o.Mux.Arms {
				if strings.Contains(arm.Value, "t_bcc") {
					sawTBcc = true
				}
			}
		}
	}
	if !sawTBcc {
		t.Error("expected at least one direct-decoder output to reference t_bcc (conditional branch translation)")
	}
	if macBusy == nil {
		t.Fatal("mac_busy output expression not found in DirectDecoder")
	}
	if !macBusy.IsMux || macBusy.Mux == nil {
		t.Fatalf("mac_busy must be a with/select mux, got IsMux=%v", macBusy.IsMux)
	}
	if macBusy.Mux.Default != "NOT_BUSY" {
		t.Errorf("mac_busy mux default = %q, want %q (SigMacBusy enum first literal)", macBusy.Mux.Default, "NOT_BUSY")
	}
	// 3-bit width: cond is "imp_bit_X & imp_bit_Y & imp_bit_Z" — one bit
	// per non-default arm (WB_NOT_STALL, WB_BUSY, EX_NOT_STALL).
	// NOT_BUSY itself is the "when others" default.
	if got := len(macBusy.Mux.Bits); got != 3 {
		t.Errorf("mac_busy mux bit-count = %d, want 3 (one per non-default arm)", got)
	}
	if got := len(macBusy.Mux.Arms); got != 3 {
		t.Errorf("mac_busy mux arms = %d, want 3 explicit arms + NOT_BUSY default", got)
	}
}
