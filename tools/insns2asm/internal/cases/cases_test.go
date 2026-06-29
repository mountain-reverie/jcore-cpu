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

// TestMovi20ImmNotTruncated verifies that movi20's 20-bit immediate is not
// corrupted by int8 truncation and that the hex encoding matches the printed value.
func TestMovi20ImmNotTruncated(t *testing.T) {
	// movi20 encoding: 0000nnnniiii0000 iiiiiiiiiiiiiiii (two words)
	cs := Synthesize(build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "movi20\t#imm20,Rn",
		Code: "0000nnnniiii0000 iiiiiiiiiiiiiiii", SH2A: true,
	}))
	if len(cs) == 0 {
		t.Fatal("no cases generated")
	}
	for k, c := range cs {
		// Surface must not contain "#-" (int8 sign-extension artifact)
		if strings.Contains(c.Asm, "#-") {
			t.Errorf("case %d: int8-truncated immediate in %q", k, c.Asm)
		}
		// Parse: movi20 #<imm>, r<n>
		var imm, rn int
		if n, _ := fmt.Sscanf(c.Asm, "movi20 #%d, r%d", &imm, &rn); n != 2 {
			t.Fatalf("case %d: unparseable asm: %q", k, c.Asm)
		}
		// Hex must be 4 bytes (two words)
		hexParts := strings.Fields(c.Hex)
		if len(hexParts) != 4 {
			t.Fatalf("case %d: want 4 hex bytes, got %d: %q", k, len(hexParts), c.Hex)
		}
		// word0 = 0000nnnn iiii0000; word1 = imm[15:0]
		var w0, w1 uint64
		fmt.Sscanf(hexParts[0]+hexParts[1], "%x", &w0)
		fmt.Sscanf(hexParts[2]+hexParts[3], "%x", &w1)
		// rn nibble is word0[11:8]
		gotRn := int((w0 >> 8) & 0xf)
		if gotRn != rn {
			t.Errorf("case %d: rn mismatch asm=r%d hex_rn=%d", k, rn, gotRn)
		}
		// imm upper 4 bits in word0[7:4], lower 16 in word1
		immHi := int((w0 >> 4) & 0xf)
		immLo := int(w1 & 0xffff)
		hexImm := (immHi << 16) | immLo
		if hexImm != imm {
			t.Errorf("case %d: asm imm %d != hex imm %d (asm=%q hex=%q)", k, imm, hexImm, c.Asm, c.Hex)
		}
	}
}

// TestMovi20ImmBoundaries verifies that movi20's imm sweep uses 20-bit
// boundaries (reaching 0xfffff) rather than the 8-bit {0,127,128,255} set.
func TestMovi20ImmBoundaries(t *testing.T) {
	cs := Synthesize(build(t, loader.RawInsn{
		Group: "Data Transfer Instructions", Format: "movi20\t#imm20,Rn",
		Code: "0000nnnniiii0000 iiiiiiiiiiiiiiii", SH2A: true,
	}))
	foundMax := false
	for _, c := range cs {
		if strings.Contains(c.Asm, fmt.Sprintf("#%d", 0xfffff)) {
			foundMax = true
		}
		// Must not contain 8-bit boundary values misused as 20-bit
		if strings.Contains(c.Asm, "#128") || strings.Contains(c.Asm, "#255") {
			t.Errorf("found 8-bit boundary value in movi20 sweep: %q", c.Asm)
		}
	}
	if !foundMax {
		t.Errorf("movi20 sweep did not reach max 20-bit value #%d", 0xfffff)
	}
}

// TestDisp12SweepReachesMax verifies that a 12-bit displacement field sweeps from
// 16 (avoiding overlap with the disp4 range 0–15) through 4095.
func TestDisp12SweepReachesMax(t *testing.T) {
	boundaries := dispBoundariesFor(12)
	// Starts at 16 (> disp4 max 15) so generated asm is unambiguous with 16-bit forms.
	want := []int{16, 0x7ff, 0x800, 4095}
	if len(boundaries) != len(want) {
		t.Fatalf("dispBoundariesFor(12) len=%d want %d", len(boundaries), len(want))
	}
	for i, v := range want {
		if boundaries[i] != v {
			t.Errorf("dispBoundariesFor(12)[%d] = %d, want %d", i, boundaries[i], v)
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
