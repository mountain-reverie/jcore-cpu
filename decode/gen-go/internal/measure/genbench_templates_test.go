package measure

import (
	"os"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestGenRegRegSub(t *testing.T) {
	// register-register default form: sub Rm,Rn (no immediate form exists)
	in := spec.Instr{Name: "SUB Rm, Rn", Opcode: "0011nnnnmmmm1000"}
	got, err := Gen(in, Recipe{Template: "default"}, 50, 0xABCD0000)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := os.ReadFile("testdata/sub_regreg_golden.S")
	if got != string(want) {
		t.Fatalf("regreg .S mismatch:\n%s", got)
	}
	// the imm-form add still routes through GenDefault via template "imm"
	add := spec.Instr{Name: "ADD Rm, Rn", Opcode: "0011nnnnmmmm1100"}
	g2, _ := Gen(add, Recipe{Template: "imm"}, 100, 0xABCD0000)
	d2, _ := GenDefault(add, 100, 0xABCD0000)
	if g2 != d2 {
		t.Fatal(`template "imm" must equal GenDefault`)
	}
}

func TestGenUnaryShll(t *testing.T) {
	// single-register-operand form: shll Rn (format "n", no memory ref).
	in := spec.Instr{Name: "SHLL Rn", Format: "n", Opcode: "0100nnnn00000000"}
	got, err := Gen(in, Recipe{Template: "unary", Measurable: true}, 50, 0xABCD0000)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := os.ReadFile("testdata/shll_unary_golden.S")
	if got != string(want) {
		t.Fatalf("unary .S mismatch:\n%s", got)
	}
}

func TestGenLoadTemplate(t *testing.T) {
	in := spec.Instr{Name: "MOV.L @Rm, Rn", Opcode: "0110nnnnmmmm0010"}
	rec := Recipe{Template: "load", Ptr: "r10", Region: 0x00008000}
	got, err := Gen(in, rec, 50, 0xABCD0000)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := os.ReadFile("testdata/movl_load_golden.S")
	if got != string(want) {
		t.Fatalf("load .S mismatch:\n%s", got)
	}
}

func TestGenHandValueSentinel(t *testing.T) {
	in := spec.Instr{Name: "TRAPA #imm", Opcode: "11000011iiiiiiii"}
	rec := Recipe{Measurable: false, Why: "halts"}
	got, err := Gen(in, rec, 50, 0xABCD0000)
	if err != nil {
		t.Fatal(err)
	}
	if got != "" {
		t.Fatalf("expected empty string sentinel, got %q", got)
	}
}

func TestGenNullarySett(t *testing.T) {
	in := spec.Instr{Name: "SETT", Format: "0", Opcode: "0000000000011000"}
	got, err := Gen(in, Recipe{Template: "nullary", Measurable: true}, 50, 0xABCD0000)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := os.ReadFile("testdata/sett_nullary_golden.S")
	if got != string(want) {
		t.Fatalf("nullary .S mismatch:\n%s", got)
	}
}

func TestMnemonicSlashOps(t *testing.T) {
	cases := []struct{ name, want string }{
		{"CMP /EQ Rm, Rn", "cmp/eq"},
		{"CMP /HS Rm, Rn", "cmp/hs"},
		{"CMP /GE Rm, Rn", "cmp/ge"},
		{"CMP /HI Rm, Rn", "cmp/hi"},
		{"CMP /GT Rm, Rn", "cmp/gt"},
		{"CMP /STR Rm, Rn", "cmp/str"},
		{"CMP /PL Rn", "cmp/pl"},
		{"CMP /PZ Rn", "cmp/pz"},
		{"CMP /EQ #imm, R0", "cmp/eq"},
		{"ADD Rm, Rn", "add"},
	}
	for _, c := range cases {
		got := mnemonic(spec.Instr{Name: c.name})
		if got != c.want {
			t.Errorf("mnemonic(%q) = %q, want %q", c.name, got, c.want)
		}
	}
}

func TestGenSregTemplate(t *testing.T) {
	in := spec.Instr{Name: "STS MACL, Rn", Format: "n", Opcode: "0000nnnn00011010"}
	got, err := Gen(in, Recipe{Template: "sreg", Measurable: true}, 50, 0xABCD0000)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := os.ReadFile("testdata/sts_macl_sreg_golden.S")
	if got != string(want) {
		t.Fatalf("sreg .S mismatch:\n%s", got)
	}
}

func TestGenImmR0Template(t *testing.T) {
	in := spec.Instr{Name: "AND #imm, R0", Format: "i8", Opcode: "11001001iiiiiiii"}
	got, err := Gen(in, Recipe{Template: "immr0", Measurable: true}, 50, 0xABCD0000)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := os.ReadFile("testdata/and_immr0_golden.S")
	if got != string(want) {
		t.Fatalf("immr0 .S mismatch:\n%s", got)
	}
}

func TestGenBranchTemplate(t *testing.T) {
	in := spec.Instr{Name: "BT label", Opcode: "10001001dddddddd"}
	rec := Recipe{Template: "branch", Loop: 50}
	got, err := Gen(in, rec, 50, 0xABCD0000)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := os.ReadFile("testdata/bt_branch_golden.S")
	if got != string(want) {
		t.Fatalf("branch .S mismatch:\n%s", got)
	}
}
