package operand

import "testing"

func TestClassifyGPR(t *testing.T) {
	o, err := Classify("Rn")
	if err != nil {
		t.Fatal(err)
	}
	if o.Class != GPR || o.Letter != 'n' {
		t.Errorf("Rn => %+v", o)
	}
}

func TestClassifyImm(t *testing.T) {
	o, _ := Classify("#imm")
	if o.Class != Imm || o.Letter != 'i' {
		t.Errorf("#imm => %+v", o)
	}
}

func TestClassifyMemDisp(t *testing.T) {
	o, _ := Classify("@(disp12,Rm)")
	if o.Class != MemDisp || o.Letter != 'd' {
		t.Errorf("@(disp12,Rm) => %+v", o)
	}
}

func TestClassifyMemPostInc(t *testing.T) {
	o, _ := Classify("@Rm+")
	if o.Class != MemPostInc || o.Letter != 'm' {
		t.Errorf("@Rm+ => %+v", o)
	}
}

func TestClassifyFixedReg(t *testing.T) {
	o, _ := Classify("GBR")
	if o.Class != FixedReg || o.Fixed != "GBR" {
		t.Errorf("GBR => %+v", o)
	}
}

func TestClassifyR0Fixed(t *testing.T) {
	o, _ := Classify("R0")
	if o.Class != R0Fixed {
		t.Errorf("R0 => %+v", o)
	}
}

func TestClassifyUnknownErrors(t *testing.T) {
	if _, err := Classify("FRn"); err == nil {
		t.Error("FRn should be unmapped in phase 1")
	}
}
