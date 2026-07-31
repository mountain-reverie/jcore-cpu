package main

import "testing"

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
