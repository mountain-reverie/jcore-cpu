package model

import (
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestCheckROMTwoWordFiresOnCollision asserts the ROM guard fires for a
// spec that contains two-word instructions sharing a word1 pattern (the
// SH-2A @(disp12,Rn) mov family, all word1 0011nnnnmmmm0001). The ROM
// predecode path (predecode_rom_addr) is indexed by word1 only and cannot
// discriminate these by ext_word[15:12], so a ROM decoder build must error
// rather than silently emit a shadowing table.
func TestCheckROMTwoWordFiresOnCollision(t *testing.T) {
	s, err := spec.LoadProfile("../../spec", "../../spec/sh2a")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if len(d.TwoWordWord1Collisions) == 0 {
		t.Fatalf("expected the sh2a overlay to produce >=1 word1 collision, got none")
	}
	err = d.CheckROMTwoWord()
	if err == nil {
		t.Fatalf("CheckROMTwoWord: expected an error for the colliding sh2a spec, got nil")
	}
	if !strings.Contains(err.Error(), "decode_table_rom") {
		t.Errorf("CheckROMTwoWord error does not mention decode_table_rom: %v", err)
	}
}

// TestCheckROMTwoWordSilentOnBase asserts the guard does NOT false-positive
// on the base spec (no two-word instructions), so the default/base ROM
// builds keep succeeding.
func TestCheckROMTwoWordSilentOnBase(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if len(d.TwoWordWord1Collisions) != 0 {
		t.Errorf("base spec unexpectedly reports word1 collisions: %v", d.TwoWordWord1Collisions)
	}
	if err := d.CheckROMTwoWord(); err != nil {
		t.Errorf("CheckROMTwoWord fired on the base spec (false positive): %v", err)
	}
}

// TestCheckROMTwoWordSilentOnJ4 asserts the SH-4 overlay (adds R*_BANK
// single-word instructions, no two-word ops) does not trip the guard.
func TestCheckROMTwoWordSilentOnJ4(t *testing.T) {
	s, err := spec.LoadProfile("../../spec", "../../spec/sh4")
	if err != nil {
		t.Fatal(err)
	}
	d, err := Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}
	if err := d.CheckROMTwoWord(); err != nil {
		t.Errorf("CheckROMTwoWord fired on the sh4 overlay (false positive): %v", err)
	}
}
