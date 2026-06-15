package model

import (
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/logic"
)

func TestBuildPrivilegedExpr(t *testing.T) {
	lm := map[string]logic.LogicMap{
		// LDC Rm, VBR = 0100 mmmm 0010 1110
		"LDC Rm, VBR": logic.OpToLogicMap("0", "0100 mmmm 0010 1110"),
		// ADD Rm, Rn  = 0011 nnnn mmmm 1100 (not privileged)
		"ADD Rm, Rn": logic.OpToLogicMap("0", "0011 nnnn mmmm 1100"),
	}
	priv := map[string]bool{"LDC Rm, VBR": true}

	expr := buildPrivileged(lm, priv)
	if expr == "false" || expr == "" {
		t.Fatalf("expected a non-trivial privileged expression, got %q", expr)
	}
	if !strings.Contains(expr, "code") {
		t.Errorf("expression should reference `code`, got %q", expr)
	}
	if !strings.Contains(expr, "= '1'") {
		t.Errorf("expression should be wrapped for boolean context, got %q", expr)
	}
}

func TestBuildPrivilegedEmptyIsFalse(t *testing.T) {
	lm := map[string]logic.LogicMap{
		"ADD Rm, Rn": logic.OpToLogicMap("0", "0011 nnnn mmmm 1100"),
	}
	if got := buildPrivileged(lm, map[string]bool{}); got != "false" {
		t.Errorf("empty privileged set should yield \"false\", got %q", got)
	}
}
