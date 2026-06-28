package format

import (
	"reflect"
	"testing"
)

func TestParseSimple(t *testing.T) {
	p := Parse("mov\tRm,Rn")
	if p.Mnemonic != "mov" {
		t.Errorf("mnemonic %q", p.Mnemonic)
	}
	if !reflect.DeepEqual(p.Operands, []string{"Rm", "Rn"}) {
		t.Errorf("operands %#v", p.Operands)
	}
}

func TestParseDisplacementKeepsInnerComma(t *testing.T) {
	p := Parse("mov.l\t@(disp12,Rm),Rn")
	if !reflect.DeepEqual(p.Operands, []string{"@(disp12,Rm)", "Rn"}) {
		t.Errorf("operands %#v", p.Operands)
	}
}

func TestParseNoOperands(t *testing.T) {
	p := Parse("nop")
	if p.Mnemonic != "nop" || len(p.Operands) != 0 {
		t.Errorf("got %+v", p)
	}
}

func TestParseR0Indexed(t *testing.T) {
	p := Parse("mov.b\t@(R0,Rm),Rn")
	if !reflect.DeepEqual(p.Operands, []string{"@(R0,Rm)", "Rn"}) {
		t.Errorf("operands %#v", p.Operands)
	}
}

func TestParseSpaceSeparatedFormat(t *testing.T) {
	// SH-2A bit insns use multiple spaces instead of a tab.
	p := Parse("bclr       #imm3,Rn")
	if p.Mnemonic != "bclr" {
		t.Errorf("mnemonic = %q, want bclr", p.Mnemonic)
	}
	if !reflect.DeepEqual(p.Operands, []string{"#imm3", "Rn"}) {
		t.Errorf("operands = %#v, want [#imm3 Rn]", p.Operands)
	}
}
