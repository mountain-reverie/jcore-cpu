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
			name: "bt -> branch",
			in: spec.Instr{
				Name: "BT label", Format: "d8",
				Operation: "When T=1, disp ?PC; T=0, nop",
			},
			wantTmpl: "branch",
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
