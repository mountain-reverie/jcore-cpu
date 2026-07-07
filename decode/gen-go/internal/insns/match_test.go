package insns

import "testing"

func TestKeyOfLetterAgnostic(t *testing.T) {
	a, ok := KeyOf("0110 nnnn mmmm 0011")
	if !ok {
		t.Fatal("spec opcode should parse")
	}
	b, ok := KeyOf("0110nnnnmmmm0011")
	if !ok {
		t.Fatal("json code should parse")
	}
	if a != b {
		t.Fatalf("same opcode, different keys: %+v vs %+v", a, b)
	}
}

func TestKeyOfTreatsUnknownLettersAsWildcard(t *testing.T) {
	// FP/DSP codes use letters like e,f,g — treat as don't-care, still parse.
	if _, ok := KeyOf("1111nnnneeee1101"); !ok {
		t.Fatal("unknown variable letters should be wildcards, not errors")
	}
}

func TestKeyOfRejectsBadLength(t *testing.T) {
	if _, ok := KeyOf("0110"); ok {
		t.Fatal("short code must be rejected")
	}
}

func TestKeyOf2(t *testing.T) {
	k, ok := KeyOf2("0011 nnnn mmmm 0001", "0110 dddd dddd dddd")
	if !ok || !k.Two {
		t.Fatalf("KeyOf2 ok=%v two=%v", ok, k.Two)
	}
	if k.Match != 0x3001 || k.Mask != 0xF00F {
		t.Errorf("word1 match/mask = %#04x/%#04x", k.Match, k.Mask)
	}
	if k.Match2 != 0x6000 || k.Mask2 != 0xF000 {
		t.Errorf("word2 match/mask = %#04x/%#04x", k.Match2, k.Mask2)
	}
}
