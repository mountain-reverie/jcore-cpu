package measure

import (
	"os"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func TestGenDefaultAdd(t *testing.T) {
	in := spec.Instr{Name: "ADD Rm, Rn", Opcode: "0011nnnnmmmm1100"}
	got, err := GenDefault(in, 100, 0xABCD0000)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := os.ReadFile("testdata/add_golden.S")
	if got != string(want) {
		t.Fatalf("generated .S mismatch:\n--- got ---\n%s", got)
	}
}
