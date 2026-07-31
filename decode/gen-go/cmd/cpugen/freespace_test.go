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
