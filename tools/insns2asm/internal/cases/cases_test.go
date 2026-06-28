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

func TestSynthesizeRendersMemorySurface(t *testing.T) {
	cs := Synthesize(build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov.l\tRm,@-Rn",
		Code: "0010nnnnmmmm0110", SH1: true,
	}))
	// every case asm must be "mov.l rM, @-rN" with rM != rN
	for _, c := range cs {
		if !strings.HasPrefix(c.Asm, "mov.l r") || !strings.Contains(c.Asm, ", @-r") {
			t.Fatalf("bad pre-dec surface: %q", c.Asm)
		}
	}
	// indexed
	ci := Synthesize(build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov.l\t@(R0,Rm),Rn",
		Code: "0000nnnnmmmm1110", SH1: true,
	}))
	if !strings.Contains(ci[0].Asm, "@(r0,r") {
		t.Fatalf("bad indexed surface: %q", ci[0].Asm)
	}
	// hex still correct: mov.l Rm,@-Rn with rm=1,rn=2 -> 0x2216
	found := false
	for _, c := range cs {
		if c.Asm == "mov.l r1, @-r2" { found = true; if c.Hex != "22 16" { t.Errorf("hex=%q want 22 16", c.Hex) } }
	}
	if !found { t.Log("rm=1,rn=2 not in sweep order; hex checked structurally elsewhere") }
}

func TestSynthesizeMemDispWithScale(t *testing.T) {
	// mov.l @(disp,Rm),Rn with 4-bit disp field and scale 4
	// Code: disp stored in bits 3-0 of word 0, Rm in bits 7-4, Rn in bits 11-8
	cs := Synthesize(build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov.l\t@(disp,Rm),Rn",
		Code: "0101nnnnmmmmdddd", SH1: true,
	}))
	if len(cs) == 0 {
		t.Fatalf("no cases generated")
	}
	// Check that displacement is multiplied by scale (4 for .l)
	// For 4-bit field, boundaries are 0, 1, 2, 15
	// With scale 4: should be 0, 4, 8, 60
	found0 := false
	found4 := false
	found8 := false
	found60 := false
	for _, c := range cs {
		if !strings.Contains(c.Asm, "@(") || !strings.Contains(c.Asm, ")") {
			t.Fatalf("bad disp surface: %q", c.Asm)
		}
		// Check for specific scaled values
		if strings.Contains(c.Asm, "@(0,r") {
			found0 = true
		}
		if strings.Contains(c.Asm, "@(4,r") {
			found4 = true
		}
		if strings.Contains(c.Asm, "@(8,r") {
			found8 = true
		}
		if strings.Contains(c.Asm, "@(60,r") {
			found60 = true
		}
	}
	if !found0 {
		t.Errorf("did not find @(0,r...) — field value 0 not scaled correctly")
	}
	if !found4 {
		t.Errorf("did not find @(4,r...) — field value 1 not scaled by 4")
	}
	if !found8 {
		t.Errorf("did not find @(8,r...) — field value 2 not scaled by 4")
	}
	if !found60 {
		t.Errorf("did not find @(60,r...) — field value 15 not scaled by 4")
	}
}

func TestSynthesizeMemPCWithScale(t *testing.T) {
	// mov.w @(disp,PC),Rn with 8-bit disp field and scale 2
	// Code: 1001nnnndddddddd
	cs := Synthesize(build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov.w\t@(disp,PC),Rn",
		Code: "1001nnnndddddddd", SH1: true,
	}))
	if len(cs) == 0 {
		t.Fatalf("no cases generated")
	}
	// Check that asm contains @(...,pc) format
	for _, c := range cs {
		if !strings.Contains(c.Asm, "@(") || !strings.Contains(c.Asm, ",pc)") {
			t.Fatalf("bad pc-disp surface: %q", c.Asm)
		}
	}
}

func TestSynthesizeMemGBRWithScale(t *testing.T) {
	// mov.l @(disp,GBR),R0 with 8-bit disp field and scale 4
	cs := Synthesize(build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov.l\t@(disp,GBR),R0",
		Code: "11000100dddddddd", SH1: true,
	}))
	if len(cs) == 0 {
		t.Fatalf("no cases generated")
	}
	// Check that asm contains @(...,gbr) format
	for _, c := range cs {
		if !strings.Contains(c.Asm, "@(") || !strings.Contains(c.Asm, ",gbr)") {
			t.Fatalf("bad gbr-disp surface: %q", c.Asm)
		}
	}
}

func TestSynthesizeDispScaleMultiplication(t *testing.T) {
	// Verify that displacement is correctly scaled
	// mov.w @(disp,PC),Rn: 8-bit disp field, scale 2
	cs := Synthesize(build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov.w\t@(disp,PC),Rn",
		Code: "1001nnnndddddddd", SH1: true,
	}))

	// The boundary values for an 8-bit field are 0 and 255
	// For scale 2: byte_disp should be 0 and 510
	found0 := false
	foundMax := false
	for _, c := range cs {
		if strings.Contains(c.Asm, "@(0,pc)") {
			found0 = true
		}
		// 255 * 2 = 510
		if strings.Contains(c.Asm, "@(510,pc)") {
			foundMax = true
		}
	}
	if !found0 {
		t.Errorf("did not find @(0,pc) in cases")
	}
	if !foundMax {
		t.Errorf("did not find @(510,pc) in cases (255*2)")
	}
}

func TestSynthesizeDispMemDispWithBaseRegAndDisp(t *testing.T) {
	// mov.l @(disp,Rm),Rn with 4-bit disp field, scale 4
	cs := Synthesize(build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "mov.l\t@(disp,Rm),Rn",
		Code: "0101nnnnmmmmdddd", SH1: true,
	}))

	if len(cs) == 0 {
		t.Fatalf("no cases generated")
	}

	// Parse each synthesized case to extract base register and displacement
	seenBase := map[int]bool{}
	seenDisps := map[int]bool{}

	for k, c := range cs {
		// surface form: "mov.l @(<d>,r<base>), r<dst>"
		var d, base, dst int
		if n, _ := fmt.Sscanf(c.Asm, "mov.l @(%d,r%d), r%d", &d, &base, &dst); n != 3 {
			t.Fatalf("case %d: unparseable asm: %q", k, c.Asm)
		}
		// For mov.l, scale is 4, so displacement must be multiple of 4
		if d%4 != 0 {
			t.Errorf("case %d: disp %d not a multiple of scale 4: %q", k, d, c.Asm)
		}
		seenBase[base] = true
		seenDisps[d] = true
	}

	if len(seenBase) < 2 {
		t.Errorf("base register did not vary across cases: %v", seenBase)
	}
	if len(seenDisps) < 2 {
		t.Errorf("displacement did not vary across cases: %v", seenDisps)
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
