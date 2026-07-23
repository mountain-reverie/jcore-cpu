package measure

import "testing"

func TestFormatCellAndEmit(t *testing.T) {
	if got := FormatCell(2.4, false); got != 2 {
		t.Fatalf("round: %v", got)
	}
	if got := FormatCell(2.0, true); got != "2+" {
		t.Fatalf("variable: %v", got)
	}
	out := EmitTable([]Result{
		{Opcode: "0100nnnn10010100", Issue: 33, Latency: 33, Source: "measured"},
		{Opcode: "0100nnnn11110101", Issue: 2, Latency: 2, Variable: true, Source: "measured"},
	})
	want := `[entries."0100nnnn10010100"]
issue = 33
latency = 33
source = "measured"

[entries."0100nnnn11110101"]
issue = "2+"
latency = "2+"
source = "measured"
`
	if out != want {
		t.Fatalf("emit mismatch:\n%s", out)
	}
}
