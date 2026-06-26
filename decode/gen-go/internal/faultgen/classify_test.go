package faultgen

import (
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func find(t *testing.T, s *spec.Spec, name string) spec.Instr {
	t.Helper()
	for _, in := range s.Instrs {
		if in.Name == name {
			return in
		}
	}
	t.Fatalf("instruction %q not found in spec", name)
	return spec.Instr{}
}

func TestClassify(t *testing.T) {
	s, err := spec.LoadProfile("../../spec", "../../spec/sh4")
	if err != nil {
		t.Fatalf("load spec: %v", err)
	}
	cases := []struct {
		name   string
		bucket Bucket
		mem    MemKind
		addr   AddrMode
		base   string
		dctrl  string
	}{
		{"MOV.L @Rm+, Rn", General, Read, PostInc, "Rm", ""},
		{"MOV.L Rm,@-Rn", General, Write, PreDec, "Rn", ""},
		{"LDS.L @Rm+, PR", PrivMem, Read, PostInc, "Rm", "PR"},
		{"MAC.L @Rm+, @Rn+", General, Read, PostInc, "Rm", ""}, // dual-postinc; see Task-6 note
		{"ADD Rm, Rn", General, NoMem, NoAddr, "", ""},
		{"RTE", Bespoke, NoMem, NoAddr, "", ""},
	}
	for _, c := range cases {
		got := Classify(find(t, s, c.name))
		if got.Bucket != c.bucket || got.Mem != c.mem || got.Addr != c.addr || got.BaseReg != c.base || got.DestCtrl != c.dctrl {
			t.Errorf("%s: got bucket=%d mem=%d addr=%d base=%q dctrl=%q",
				c.name, got.Bucket, got.Mem, got.Addr, got.BaseReg, got.DestCtrl)
		}
	}
}
