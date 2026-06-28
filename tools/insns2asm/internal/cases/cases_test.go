package cases

import (
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/loader"
)

var errBadForm = errors.New("bad asm form")

func fmtSscan(s string, v *int) (int, error) {
	n, err := fmt.Sscanf(s, "r%d", v)
	if err != nil {
		return n, errBadForm
	}
	return n, nil
}

func build(t *testing.T, raw loader.RawInsn) ir.Insn {
	t.Helper()
	is, err := ir.Build([]loader.RawInsn{raw})
	if err != nil {
		t.Fatal(err)
	}
	return is[0]
}

func TestSynthesizeMovSweepsAllRegistersDistinct(t *testing.T) {
	cs := Synthesize(build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov\tRm,Rn",
		Code: "0110nnnnmmmm0011", SH1: true,
	}))
	if len(cs) != 16 {
		t.Fatalf("want 16 cases, got %d", len(cs))
	}
	seenN := map[int]bool{}
	for k, c := range cs {
		var a, b int
		if _, err := scanMov(c.Asm, &a, &b); err != nil {
			t.Fatalf("case %d asm %q: %v", k, c.Asm, err)
		}
		if a == b {
			t.Errorf("case %d: rm==rn (%d) — swap bugs invisible: %q", k, a, c.Asm)
		}
		seenN[b] = true
	}
	for v := 0; v < 16; v++ {
		if !seenN[v] {
			t.Errorf("rn value r%d never tested", v)
		}
	}
}

func TestSynthesizeMovHexMatchesEncoding(t *testing.T) {
	cs := Synthesize(build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov\tRm,Rn",
		Code: "0110nnnnmmmm0011", SH1: true,
	}))
	// Check all cases: for each (rm, rn) pair, verify hex = 0x6000 | rn<<8 | rm<<4 | 3
	for k, c := range cs {
		var rm, rn int
		if _, err := scanMov(c.Asm, &rm, &rn); err != nil {
			t.Fatalf("case %d asm %q: %v", k, c.Asm, err)
		}
		expected := fmt.Sprintf("%02x %02x", byte(0x60|(rn)), byte(rm<<4|3))
		if c.Hex != expected {
			t.Errorf("case %d asm %q hex=%q want %q", k, c.Asm, c.Hex, expected)
		}
	}
}

func scanMov(s string, a, b *int) (int, error) {
	s = strings.TrimPrefix(s, "mov ")
	parts := strings.Split(s, ", ")
	if len(parts) != 2 {
		return 0, errBadForm
	}
	_, e1 := fmtSscan(parts[0], a)
	_, e2 := fmtSscan(parts[1], b)
	if e1 != nil {
		return 0, e1
	}
	if e2 != nil {
		return 0, e2
	}
	return 2, nil
}
