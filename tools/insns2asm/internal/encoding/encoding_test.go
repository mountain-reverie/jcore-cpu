package encoding

import "testing"

func TestParseCodeSingleWord(t *testing.T) {
	w, err := ParseCode("0110nnnnmmmm0011")
	if err != nil {
		t.Fatal(err)
	}
	if len(w) != 1 {
		t.Fatalf("want 1 word, got %d", len(w))
	}
	if w[0][0] != (Bit{Fixed: true, Val: 0}) {
		t.Errorf("bit15 = %+v", w[0][0])
	}
	if w[0][1] != (Bit{Fixed: true, Val: 1}) {
		t.Errorf("bit14 = %+v", w[0][1])
	}
	if w[0][4] != (Bit{Letter: 'n'}) {
		t.Errorf("bit11 = %+v", w[0][4])
	}
}

func TestParseCodeTwoWords(t *testing.T) {
	w, err := ParseCode("0011nnnnmmmm0001 0100dddddddddddd")
	if err != nil {
		t.Fatal(err)
	}
	if len(w) != 2 {
		t.Fatalf("want 2 words, got %d", len(w))
	}
}

func TestParseCodeRejectsBadLength(t *testing.T) {
	if _, err := ParseCode("0110"); err == nil {
		t.Error("want error for short word")
	}
}

func TestFields(t *testing.T) {
	w, _ := ParseCode("0110nnnnmmmm0011")
	fs := w[0].Fields()
	if len(fs) != 2 {
		t.Fatalf("want 2 fields (n,m), got %d: %+v", len(fs), fs)
	}
	if fs[0].Letter != 'n' || fs[0].Hi != 11 || fs[0].Lo != 8 || fs[0].Width != 4 {
		t.Errorf("n field wrong: %+v", fs[0])
	}
	if fs[1].Letter != 'm' || fs[1].Hi != 7 || fs[1].Lo != 4 {
		t.Errorf("m field wrong: %+v", fs[1])
	}
}

func TestParseFieldsTwoWords(t *testing.T) {
	w, _ := ParseCode("0011nnnnmmmm0001 0100dddddddddddd")
	fs := ParseFields(w)
	// n (word0), m (word0), d (word1, 12 bits)
	if len(fs) != 3 {
		t.Fatalf("want 3 fields, got %d: %+v", len(fs), fs)
	}
	d := fs[2]
	if d.Letter != 'd' || d.Word != 1 || d.Width != 12 {
		t.Errorf("d field wrong: %+v", d)
	}
}
