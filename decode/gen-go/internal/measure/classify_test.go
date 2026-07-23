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
			name: "mov.l @(disp,Rm),Rn -> loaddisp",
			in: spec.Instr{
				Name: "MOV.L @(disp, Rm), Rn", Format: "nmd",
				Operation: "(disp × 4+ Rm) ? Rn",
			},
			wantTmpl: "loaddisp",
		},
		{
			name: "mov.b Rm,@(R0,Rn) -> storer0idx",
			in: spec.Instr{
				Name: "MOV.B Rm, @(R0, Rn)", Format: "nm",
				Operation: "Rm?(R0 +Rn)",
			},
			wantTmpl: "storer0idx",
		},
		{
			name: "mov.l @Rm+,Rn -> loadinc",
			in: spec.Instr{
				Name: "MOV.L @Rm+, Rn", Format: "nm",
				Operation: "(Rm) ? Rn, Rm + 4 ? Rm",
			},
			wantTmpl: "loadinc",
		},
		{
			name: "mov.l Rm,@-Rn -> storedec",
			in: spec.Instr{
				Name: "MOV.L Rm,@-Rn", Format: "nm",
				Operation: "Rn – 4 ? Rn, Rm ? (Rn)",
			},
			wantTmpl: "storedec",
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

func TestClassifySpecialRegMove(t *testing.T) {
	// Plain register forms -> "sreg" template, measurable.
	for _, tc := range []struct{ name, format string }{
		{"STS MACH, Rn", "n"},
		{"STS MACL, Rn", "n"},
		{"STS PR, Rn", "n"},
		{"LDS Rm, MACH", "m"},
		{"LDS Rm, MACL", "m"},
		{"LDS Rm, PR", "m"},
	} {
		rec := Classify(spec.Instr{Name: tc.name, Format: tc.format})
		if rec.Template != "sreg" || !rec.Measurable {
			t.Errorf("Classify(%q) = %+v, want Template=sreg, Measurable=true", tc.name, rec)
		}
	}

	// Coprocessor STS/LDS forms -> hand.
	for _, name := range []string{"STS CPI_COM, Rn", "STS CP0_COM, Rn", "LDS Rm, CPI_COM", "LDS Rm, CP0_COM"} {
		rec := Classify(spec.Instr{Name: name})
		if rec.Measurable || rec.Why == "" {
			t.Errorf("Classify(%q) = %+v, want hand (Measurable=false, Why set)", name, rec)
		}
	}

	// .L pre-dec/post-inc memory forms -> hand, not skip.
	for _, name := range []string{"STS.L MACH, @-Rn", "LDS.L @Rm+, MACH"} {
		rec := Classify(spec.Instr{Name: name, Format: "n"})
		if rec.Measurable || rec.Why == "" {
			t.Errorf("Classify(%q) = %+v, want hand (Measurable=false, Why set)", name, rec)
		}
		if rec.Template == "skip" {
			t.Errorf("Classify(%q).Template = skip, want hand entry not skip", name)
		}
	}
}

func TestClassifyImmR0(t *testing.T) {
	for _, name := range []string{"AND #imm, R0", "OR #imm, R0", "XOR #imm, R0", "TST #imm, R0", "CMP /EQ #imm, R0"} {
		rec := Classify(spec.Instr{Name: name, Format: "i8"})
		if rec.Template != "immr0" || !rec.Measurable {
			t.Errorf("Classify(%q) = %+v, want Template=immr0, Measurable=true", name, rec)
		}
	}
	// General immediate ops (Rn destination) still use "imm".
	rec := Classify(spec.Instr{Name: "ADD #imm, Rn", Format: "ni"})
	if rec.Template != "imm" {
		t.Errorf("Classify(%q).Template = %q, want imm", "ADD #imm, Rn", rec.Template)
	}
}

func TestClassifyHandOverrides(t *testing.T) {
	for _, name := range []string{"TAS.B @Rn", "XTRACT Rm, Rn", "MAC.W @Rm+, @Rn+", "MAC.L @Rm+, @Rn+",
		"TST.B #imm, @(R0, GBR)", "AND.B #imm, @(R0, GBR)", "XOR.B #imm, @(R0, GBR)", "OR.B #imm, @(R0, GBR)"} {
		rec := Classify(spec.Instr{Name: name, Format: "i8"})
		if rec.Measurable || rec.Why == "" {
			t.Errorf("Classify(%q) = %+v, want hand (Measurable=false, Why set)", name, rec)
		}
		if rec.Template == "skip" {
			t.Errorf("Classify(%q).Template = skip, want hand entry not skip", name)
		}
	}
}

// TestClassifyMemoryAddressingModes covers the iter4 memory-addressing-mode
// templates (displacement, R0-indexed, post-increment, pre-decrement) and
// the residual modes that remain genuinely un-representable (GBR-relative,
// PC-relative, multi-operand RMW).
func TestClassifyMemoryAddressingModes(t *testing.T) {
	cases := []struct {
		name     string
		in       spec.Instr
		wantTmpl string
	}{
		{"disp load general -> loaddisp", spec.Instr{Name: "MOV.L @(disp, Rm), Rn", Format: "nmd"}, "loaddisp"},
		{"disp store general -> storedisp", spec.Instr{Name: "MOV.L Rm, @(disp, Rn)", Format: "nmd"}, "storedisp"},
		{"disp load fixed-R0 (md) -> loaddispr0", spec.Instr{Name: "MOV.B @(disp, Rm), R0", Format: "md"}, "loaddispr0"},
		{"disp load fixed-R0 word (md) -> loaddispr0", spec.Instr{Name: "MOV.W @(disp, Rm), R0", Format: "md"}, "loaddispr0"},
		{"disp store fixed-R0 (nd4) -> storedispr0", spec.Instr{Name: "MOV.B R0, @(disp, Rn)", Format: "nd4"}, "storedispr0"},
		{"disp store fixed-R0 word (nd4) -> storedispr0", spec.Instr{Name: "MOV.W R0, @(disp, Rn)", Format: "nd4"}, "storedispr0"},
		{"R0-indexed load -> loadr0idx", spec.Instr{Name: "MOV.L @(R0, Rm), Rn", Format: "nm"}, "loadr0idx"},
		{"R0-indexed load byte -> loadr0idx", spec.Instr{Name: "MOV.B @(R0, Rm), Rn", Format: "nm"}, "loadr0idx"},
		{"R0-indexed store -> storer0idx", spec.Instr{Name: "MOV.L Rm, @(R0, Rn)", Format: "nm"}, "storer0idx"},
		{"post-inc load byte -> loadinc", spec.Instr{Name: "MOV.B @Rm+, Rn", Format: "nm"}, "loadinc"},
		{"post-inc load word -> loadinc", spec.Instr{Name: "MOV.W @Rm+, Rn", Format: "nm"}, "loadinc"},
		{"post-inc load long -> loadinc", spec.Instr{Name: "MOV.L @Rm+, Rn", Format: "nm"}, "loadinc"},
		{"pre-dec store byte -> storedec", spec.Instr{Name: "MOV.B Rm, @-Rn", Format: "nm"}, "storedec"},
		{"pre-dec store word -> storedec", spec.Instr{Name: "MOV.W Rm, @-Rn", Format: "nm"}, "storedec"},
		{"pre-dec store long -> storedec", spec.Instr{Name: "MOV.L Rm, @-Rn", Format: "nm"}, "storedec"},
		{"GBR-relative store -> skip", spec.Instr{Name: "MOV.L R0, @(disp, GBR)", Format: "d8"}, "skip"},
		{"GBR-relative load -> skip", spec.Instr{Name: "MOV.L @(disp, GBR), R0", Format: "d8"}, "skip"},
		{"PC-relative load -> skip", spec.Instr{Name: "MOV.L @(disp, PC), Rn", Format: "nd8"}, "skip"},
		{"PC-relative load word -> skip", spec.Instr{Name: "MOV.W @(disp, PC), Rn", Format: "nd8"}, "skip"},
		{"multi-operand RMW -> skip", spec.Instr{Name: "CAS.L Rm, Rn, @R0", Format: "nm"}, "skip"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			rec := Classify(c.in)
			if rec.Template != c.wantTmpl {
				t.Fatalf("Classify(%q).Template = %q, want %q (rec=%+v)", c.in.Name, rec.Template, c.wantTmpl, rec)
			}
			if c.wantTmpl == "skip" {
				if rec.Measurable {
					t.Fatalf("Classify(%q) skip entry should not be Measurable", c.in.Name)
				}
			} else {
				if !rec.Measurable {
					t.Fatalf("Classify(%q) = %+v, want Measurable=true", c.in.Name, rec)
				}
				if rec.Ptr != "r10" {
					t.Fatalf("Classify(%q).Ptr = %q, want r10", c.in.Name, rec.Ptr)
				}
			}
		})
	}
}

// TestClassifyStoreDecRegion ensures the "storedec" recipe uses a
// high-enough base region (not the plain load/store 0x8000) so
// pre-decrements never run outside RAM even without the mid-body reset.
func TestClassifyStoreDecRegion(t *testing.T) {
	rec := Classify(spec.Instr{Name: "MOV.L Rm, @-Rn", Format: "nm"})
	if rec.Region <= 0x00008000 {
		t.Fatalf("storedec Region = %#x, want > 0x8000", rec.Region)
	}
}
