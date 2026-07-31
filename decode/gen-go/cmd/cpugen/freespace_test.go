package main

import (
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/freespace"
)

func TestFormFromOpcode(t *testing.T) {
	// Fixed bits become free; operand fields are preserved.
	if got := formFromOpcode("0110nnnnmmmm0011"); got != "----nnnnmmmm----" {
		t.Errorf("formFromOpcode = %q, want \"----nnnnmmmm----\"", got)
	}
	if got := formFromOpcode("11000011iiiiiiii"); got != "--------iiiiiiii" {
		t.Errorf("formFromOpcode = %q, want \"--------iiiiiiii\"", got)
	}
}

func TestRunFreespaceRequiresAvoid(t *testing.T) {
	if code := runFreespace([]string{"mov"}); code == 0 {
		t.Error("runFreespace succeeded without --avoid, want non-zero exit")
	}
}

func TestCandidateStatusRendersBothShadowsAndShareable(t *testing.T) {
	c := freespace.Candidate{
		Shadows:   []string{"SH4: fpu op"},
		Shareable: []string{"SH2A: movi20 #imm20,Rn [ext iiiiiiiiiiiiiiii]"},
	}
	status, shadows := candidateStatus(c)
	if status != "shareable?" {
		t.Errorf("status = %q, want %q", status, "shareable?")
	}
	want := "SH4: fpu op; SH2A: movi20 #imm20,Rn [ext iiiiiiiiiiiiiiii]"
	if shadows != want {
		t.Errorf("shadows = %q, want %q (both lists must render, neither overwriting the other)", shadows, want)
	}
}

func TestCandidateStatusVirginAndShadowsOnly(t *testing.T) {
	if status, shadows := candidateStatus(freespace.Candidate{Virgin: true}); status != "virgin" || shadows != "—" {
		t.Errorf("virgin candidate = (%q, %q), want (virgin, —)", status, shadows)
	}
	c := freespace.Candidate{Shadows: []string{"SH4: fpu op"}}
	if status, shadows := candidateStatus(c); status != "shadows" || shadows != "SH4: fpu op" {
		t.Errorf("shadows-only candidate = (%q, %q), want (shadows, \"SH4: fpu op\")", status, shadows)
	}
}

func TestFormatList(t *testing.T) {
	if got := formatList(nil); got != "—" {
		t.Errorf("formatList(nil) = %q, want \"—\"", got)
	}
	three := []string{"a", "b", "c"}
	if got := formatList(three); got != "a; b; c" {
		t.Errorf("formatList(3 items) = %q, want \"a; b; c\"", got)
	}
	eight := []string{"a", "b", "c", "d", "e", "f", "g", "h"}
	if got := formatList(eight); got != "a; b; c; d; e; +3 more" {
		t.Errorf("formatList(8 items) = %q, want \"a; b; c; d; e; +3 more\"", got)
	}
}
