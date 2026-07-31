package freespace

import "testing"

func TestShape(t *testing.T) {
	cases := []struct {
		name string
		want string
	}{
		{"Rm,Rn", "----nnnnmmmm----"},
		{"Rn", "----nnnn--------"},
		{"#imm8,R0", "--------iiiiiiii"},
		{"#imm8", "--------iiiiiiii"},
		{"@(disp4,Rn)", "----nnnndddd----"},
		{"none", "----------------"},
	}
	for _, tc := range cases {
		got, ok := Shape(tc.name)
		if !ok {
			t.Errorf("Shape(%q) not found", tc.name)
			continue
		}
		if got != tc.want {
			t.Errorf("Shape(%q) = %q, want %q", tc.name, got, tc.want)
		}
	}
}

func TestShapeCaseAndSpaceInsensitive(t *testing.T) {
	got, ok := Shape(" rm, rn ")
	if !ok || got != "----nnnnmmmm----" {
		t.Errorf("Shape(\" rm, rn \") = %q, %v; want \"----nnnnmmmm----\", true", got, ok)
	}
}

func TestShapeUnknown(t *testing.T) {
	if _, ok := Shape("Rq,Rz"); ok {
		t.Error("Shape(\"Rq,Rz\") reported found, want not found")
	}
}

func TestShapeNamesSorted(t *testing.T) {
	names := ShapeNames()
	if len(names) == 0 {
		t.Fatal("ShapeNames() empty")
	}
	for i := 1; i < len(names); i++ {
		if names[i-1] >= names[i] {
			t.Fatalf("ShapeNames() not sorted at %d: %q then %q", i, names[i-1], names[i])
		}
	}
}
