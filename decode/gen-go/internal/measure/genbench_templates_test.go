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
