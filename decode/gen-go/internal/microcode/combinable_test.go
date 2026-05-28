package microcode

import "testing"

func TestCombinableSignals72ExpectedGroupCount(t *testing.T) {
	groups := CombinableSignals(72)
	// rom.clj lines 65-71 define 7 groups for width 72.
	if len(groups) != 7 {
		t.Errorf("want 7 groups for width 72, got %d", len(groups))
	}
}

func TestCombinableSignals64ExpectedGroupCount(t *testing.T) {
	groups := CombinableSignals(64)
	// rom.clj lines 50-63 define 10 groups for width 64.
	if len(groups) != 10 {
		t.Errorf("want 10 groups for width 64, got %d", len(groups))
	}
}

func TestCombinableSignalsAllInVocabulary(t *testing.T) {
	known := map[Signal]bool{}
	for _, s := range AllSignals {
		known[s] = true
	}
	for _, w := range []int{64, 72} {
		for _, g := range CombinableSignals(w) {
			for _, s := range g {
				if !known[s] {
					t.Errorf("width %d: combinable group references unknown signal %q", w, s)
				}
			}
		}
	}
}

func TestCombinableSignalsUniqueWithinTable(t *testing.T) {
	for _, w := range []int{64, 72} {
		seen := map[Signal]bool{}
		for _, g := range CombinableSignals(w) {
			for _, s := range g {
				if seen[s] {
					t.Errorf("width %d: signal %q appears in two combinable groups", w, s)
				}
				seen[s] = true
			}
		}
	}
}

func TestCombinableSignals72LastGroupIsWrpcGroup(t *testing.T) {
	groups := CombinableSignals(72)
	last := groups[len(groups)-1]
	// The last group maps to line(2 downto 0) in the golden — it's the
	// {wrpc_z, wrpr_pc, wrsr_w, wrsr_z} group from rom.clj line 72.
	want := map[Signal]bool{
		SigWrpcZ: true, SigWrprPC: true, SigWrsrW: true, SigWrsrZ: true,
	}
	if len(last) != len(want) {
		t.Errorf("last group: want %d signals, got %d: %v", len(want), len(last), last)
		return
	}
	for _, s := range last {
		if !want[s] {
			t.Errorf("last group: unexpected signal %q", s)
		}
	}
}

func TestCombinableSignals72FirstGroupIsAluGroup(t *testing.T) {
	groups := CombinableSignals(72)
	first := groups[0]
	// The first group is {alumanip, shiftfunc, arith_func, logic_func}.
	want := map[Signal]bool{
		SigAluManip: true, SigShiftFunc: true, SigArithFunc: true, SigLogicFunc: true,
	}
	if len(first) != len(want) {
		t.Errorf("first group: want %d signals, got %d: %v", len(want), len(first), first)
		return
	}
	for _, s := range first {
		if !want[s] {
			t.Errorf("first group: unexpected signal %q", s)
		}
	}
}
