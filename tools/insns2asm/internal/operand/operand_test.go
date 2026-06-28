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

func TestClassifyMemRegFixedR0(t *testing.T) {
	o, err := Classify("@R0")
	if err != nil {
		t.Fatal(err)
	}
	if o.Class != MemReg || o.Fixed != "R0" || o.Letter != 0 {
		t.Errorf("@R0 => %+v", o)
	}
}

func TestClassifyMemR0GBR(t *testing.T) {
	o, err := Classify("@(R0,GBR)")
	if err != nil {
		t.Fatal(err)
	}
	if o.Class != MemR0GBR {
		t.Errorf("@(R0,GBR) => %+v", o)
	}
}

func TestClassifyUnknownErrors(t *testing.T) {
	if _, err := Classify("FRn"); err == nil {
		t.Error("FRn should be unmapped in phase 1")
	}
}

func TestClassifyBranchDisp(t *testing.T) {
	o, err := Classify("label")
	if err != nil {
		t.Fatal(err)
	}
	if o.Class != BranchDisp || o.Letter != 'd' {
		t.Errorf("label => %+v", o)
	}
}

func TestClassifyBankReg(t *testing.T) {
	o, _ := Classify("Rn_BANK")
	if o.Class != BankReg || o.Letter != 'n' {
		t.Errorf("Rn_BANK => %+v", o)
	}
}

func TestClassifyTBRDisp(t *testing.T) {
	o, _ := Classify("@@(disp8,TBR)")
	if o.Class != MemTBRDisp || o.Letter != 'd' {
		t.Errorf("@@(disp8,TBR) => %+v", o)
	}
}

func TestClassifyControlRegs(t *testing.T) {
	for tok, name := range map[string]string{"SSR": "SSR", "SPC": "SPC", "DBR": "DBR", "SGR": "SGR", "TBR": "TBR"} {
		o, err := Classify(tok)
		if err != nil {
			t.Fatalf("%s: %v", tok, err)
		}
		if o.Class != FixedReg || o.Fixed != name {
			t.Errorf("%s => %+v", tok, o)
		}
	}
}

func TestClassifyMemDispCarriesBaseLetter(t *testing.T) {
	o, _ := Classify("@(disp12,Rm)")
	if o.Class != MemDisp || o.Letter != 'd' || o.BaseLetter != 'm' {
		t.Errorf("@(disp12,Rm) => %+v", o)
	}
}

func TestClassifyImm3AndMMURegs(t *testing.T) {
	if o, _ := Classify("#imm3"); o.Class != Imm || o.Letter != 'i' {
		t.Errorf("#imm3 => %+v", o)
	}
	for _, tok := range []string{"PTEH", "PTEL", "ASIDR", "TSBPTR"} {
		o, err := Classify(tok)
		if err != nil || o.Class != FixedReg || o.Fixed != tok {
			t.Errorf("%s => %+v err=%v", tok, o, err)
		}
	}
}
