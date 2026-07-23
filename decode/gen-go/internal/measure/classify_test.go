package measure

import (
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestClassify(t *testing.T) {
	cases := []struct {
		name     string
		in       spec.Instr
		wantTmpl string
		wantHand bool
	}{
		{
			name: "sub -> default",
			in: spec.Instr{
				Name: "SUB Rm, Rn", Format: "nm",
				Operation: "Rn ? Rm ? Rn",
			},
			wantTmpl: "default",
		},
		{
			name: "add #imm -> imm",
			in: spec.Instr{
				Name: "ADD #imm, Rn", Format: "ni",
				Operation: "Rn + imm ? Rn",
			},
			wantTmpl: "imm",
		},
		{
			name: "mov.l @Rm,Rn -> load",
			in: spec.Instr{
				Name: "MOV.L @Rm, Rn", Format: "nm",
				Operation: "@Rm ? Rn",
			},
			wantTmpl: "load",
		},
		{
			name: "mov.l Rm,@Rn -> store",
			in: spec.Instr{
				Name: "MOV.L Rm, @Rn", Format: "nm",
				Operation: "Rm ? @Rn",
			},
			wantTmpl: "store",
		},
		{
			name: "mov.l @(disp,Rm),Rn -> skip (disp addressing not templated)",
			in: spec.Instr{
				Name: "MOV.L @(disp, Rm), Rn", Format: "nmd",
				Operation: "(disp × 4+ Rm) ? Rn",
			},
			wantTmpl: "skip",
		},
		{
			name: "mov.b Rm,@(R0,Rn) -> skip (R0-indexed not templated)",
			in: spec.Instr{
				Name: "MOV.B Rm, @(R0, Rn)", Format: "nm",
				Operation: "Rm?(R0 +Rn)",
			},
			wantTmpl: "skip",
		},
		{
			name: "mov.l @Rm+,Rn -> skip (post-inc not templated)",
			in: spec.Instr{
				Name: "MOV.L @Rm+, Rn", Format: "nm",
				Operation: "(Rm) ? Rn, Rm + 4 ? Rm",
			},
			wantTmpl: "skip",
		},
		{
			name: "mov.l Rm,@-Rn -> skip (pre-dec not templated)",
			in: spec.Instr{
				Name: "MOV.L Rm,@-Rn", Format: "nm",
				Operation: "Rn – 4 ? Rn, Rm ? (Rn)",
			},
			wantTmpl: "skip",
		},
		{
			name: "cmp/eq -> default (slash mnemonic doesn't affect classify)",
			in: spec.Instr{
				Name: "CMP /EQ Rm, Rn", Format: "nm",
				Operation: "If Rn = Rm, 1 ? T",
			},
			wantTmpl: "default",
		},
		{
			name: "clrt -> nullary",
			in: spec.Instr{
				Name: "CLRT", Format: "0",
				Operation: "0 -> T",
			},
			wantTmpl: "nullary",
		},
		{
			name: "nop -> skip (calibration filler, not a DUT)",
			in: spec.Instr{
				Name: "NOP", Format: "0",
				Operation: "no operation",
			},
			wantTmpl: "skip",
		},
		{
			name: "bt -> hand (branch redirect penalty, not isolatable)",
			in: spec.Instr{
				Name: "BT label", Format: "d8",
				Operation: "When T=1, disp ?PC; T=0, nop",
			},
			wantHand: true,
		},
		{
			name: "rte -> hand",
			in: spec.Instr{
				Name: "RTE", Privileged: true, Format: "0",
				Operation: "Delayed branch, stack -> PC/SR",
			},
			wantHand: true,
		},
		{
			name: "shll Rn -> unary",
			in: spec.Instr{
				Name: "SHLL Rn", Format: "n",
				Operation: "T ? Rn ? MSB, Rn << 1",
			},
			wantTmpl: "unary",
		},
		{
			name: "fadd (FPU) -> skip",
			in: spec.Instr{
				Name: "FADD FRm, FRn", Format: "nm",
				Opcode:    "1111nnnnmmmm0000",
				Operation: "FRn + FRm ? FRn",
			},
			wantTmpl: "skip",
		},
		{
			name: "two-word @Rn+ -> twoword",
			in: spec.Instr{
				Name: "MOV.L @(disp12,Rm),Rn", Format: "nmd12",
				Opcode2:   "0110 dddd dddd dddd",
				Operation: "(disp12+Rm) ? Rn",
			},
			wantTmpl: "twoword",
		},
		{
			name: "Interrupt (plane=system) -> skip",
			in: spec.Instr{
				Name: "Interrupt", Format: "d8", Plane: "system",
			},
			wantTmpl: "skip",
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			rec := Classify(c.in)
			if c.wantHand {
				if rec.Measurable {
					t.Fatalf("Classify(%q) = %+v, want Measurable=false (hand)", c.in.Name, rec)
				}
				if rec.Why == "" {
					t.Fatalf("Classify(%q) = %+v, want non-empty Why for hand entry", c.in.Name, rec)
				}
				return
			}
			if rec.Template != c.wantTmpl {
				t.Fatalf("Classify(%q).Template = %q, want %q", c.in.Name, rec.Template, c.wantTmpl)
			}
		})
	}
}

// TestClassifySkipDropsMeasurable ensures the skip marker doesn't
// accidentally look measurable/hand — the CLI must special-case it.
func TestClassifySkipDropsMeasurable(t *testing.T) {
	rec := Classify(spec.Instr{Name: "Interrupt", Plane: "system"})
	if rec.Template != "skip" {
		t.Fatalf("Template = %q, want skip", rec.Template)
	}
	if rec.Measurable {
		t.Fatalf("skip recipe should not be Measurable=true")
	}
	if rec.Why != "" {
		t.Fatalf("skip recipe should not set Why (that's the hand-entry sentinel)")
	}
}

// TestClassifyLoadStorePtrRegion ensures plain register-indirect load/store
// recipes carry a concrete Ptr/Region (matching movl_load_golden.S), not an
// empty pointer that would emit an unassemblable/wrong-instruction
// benchmark.
func TestClassifyLoadStorePtrRegion(t *testing.T) {
	load := Classify(spec.Instr{Name: "MOV.L @Rm, Rn", Format: "nm", Operation: "@Rm ? Rn"})
	if load.Ptr != "r10" || load.Region != 0x00008000 {
		t.Fatalf("load recipe Ptr/Region = %q/%#x, want r10/0x8000", load.Ptr, load.Region)
	}
	store := Classify(spec.Instr{Name: "MOV.L Rm, @Rn", Format: "nm", Operation: "Rm ? @Rn"})
	if store.Ptr != "r10" || store.Region != 0x00008000 {
		t.Fatalf("store recipe Ptr/Region = %q/%#x, want r10/0x8000", store.Ptr, store.Region)
	}
}

func TestClassifyPrivilegedLdcStc(t *testing.T) {
	for _, name := range []string{"LDC Rm, SR", "STC SR, Rn"} {
		rec := Classify(spec.Instr{Name: name, Format: "n"})
		if rec.Measurable {
			t.Fatalf("Classify(%q) should be hand (Measurable=false), got %+v", name, rec)
		}
		if rec.Why == "" {
			t.Fatalf("Classify(%q) hand entry needs Why set", name)
		}
	}
}
