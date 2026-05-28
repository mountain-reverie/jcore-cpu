package microcode

import "testing"

func TestAllSignalsUnique(t *testing.T) {
	seen := map[Signal]bool{}
	for _, s := range AllSignals {
		if seen[s] {
			t.Errorf("duplicate signal in AllSignals: %q", s)
		}
		seen[s] = true
	}
}

func TestAllSignalsNonEmpty(t *testing.T) {
	for _, s := range AllSignals {
		if s == "" {
			t.Errorf("empty signal value in AllSignals")
		}
	}
}

// nillableSignals is the canonical "no default" set, mirrored from the
// Clojure reference at decode/gen-clj-archive/src/cpugen/interface.clj
// lines 405-416 (the :nillable-outputs set). A signal in this set MUST
// return (_, false) from SignalDefault; any other signal MUST return
// (non-empty, true).
//
// This test would have caught the SigMacBusy default-missing bug — at
// the time of writing, SigMacBusy was not in nillableSignals (correctly
// per the Clojure source) but had no default either, so the direct
// decoder emitted the wrong "when others" arm for ~140 non-MAC slots.
var nillableSignals = map[Signal]bool{
	SigShiftFunc:    true,
	SigImmVal:       true,
	SigMaWr:         true,
	SigArithFunc:    true,
	SigArithSrFn:    true,
	SigLogicFunc:    true,
	SigLogicSrFn:    true,
	SigZbusSel:      true,
	SigMemAddrSel:   true,
	SigMemSize:      true,
	SigMemWdataSel:  true,
	SigRegnumW:      true,
	SigRegnumX:      true,
	SigRegnumY:      true,
	SigRegnumZ:      true,
}

func TestSignalVHDLPathCoversAllSignals(t *testing.T) {
	for _, s := range AllSignals {
		if SignalVHDLPath[s] == "" {
			t.Errorf("Signal %q has no VHDL path entry", s)
		}
	}
}

func TestSignalDefaultCoversAllSignals(t *testing.T) {
	for _, s := range AllSignals {
		def, ok := SignalDefault(s)
		if nillableSignals[s] {
			if ok {
				t.Errorf("signal %q is nillable but SignalDefault returned (%q, true); expected (\"\", false)", s, def)
			}
			continue
		}
		if !ok {
			t.Errorf("signal %q is not nillable but SignalDefault returned (\"\", false); needs a default value", s)
			continue
		}
		if def == "" {
			t.Errorf("signal %q SignalDefault returned (\"\", true); empty default is invalid", s)
		}
	}
}
