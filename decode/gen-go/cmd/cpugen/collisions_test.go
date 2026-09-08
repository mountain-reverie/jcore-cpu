package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Fixture suite for `cpugen collisions`.
//
// WHY THIS EXISTS. The sweep shipped with its non-vacuity demonstrated once, by
// hand, in a commit message. That is not a property anyone can re-check, and
// this repository's standard for a guard is a fixture plus a mutation. A
// one-time manual exercise decays into a claim about the past.
//
// Each case builds a synthetic insns.json in a temp directory and asserts the
// sweep's EXIT STATUS and, where a failure is expected, WHICH message produced
// it. Exit status alone cannot tell "the check I meant fired" from "something
// else did".

// baselineRows are the two pairs the shipped baseline excuses. Cases that want
// a clean tree must include them, or the "baseline entry no longer collides"
// arm fires -- which is itself one of the things under test.
var baselineRows = []map[string]any{
	{"format": "lds\tRm,A0", "code": "0100mmmm01110110", "DSP": true},
	{"format": "lds.l\t@Rm+,A0", "code": "0100mmmm01110110", "DSP": true},
	{"format": "sts.l\tDSR,@-Rn", "code": "0100nnnn01100010", "DSP": true},
	{"format": "sts.l\tA0,@-Rn", "code": "0100nnnn01100010", "DSP": true},
}

// withBaseline returns a document whose only collisions are the baselined ones,
// plus the given extra rows.
func withBaseline(extra ...map[string]any) any {
	rows := append(append([]map[string]any{}, baselineRows...), extra...)
	return map[string]any{"instructions": rows}
}

// runSweep writes doc (a value to marshal, or a raw string for malformed input)
// to a temp insns.json and runs the sweep over it.
func runSweep(t *testing.T, doc any) (int, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "insns.json")
	var raw []byte
	if s, ok := doc.(string); ok {
		raw = []byte(s)
	} else {
		var err error
		raw, err = json.Marshal(doc)
		if err != nil {
			t.Fatalf("marshal fixture: %v", err)
		}
	}
	if err := os.WriteFile(path, raw, 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	var out, errOut bytes.Buffer
	rc := sweepCollisions(path, &out, &errOut)
	return rc, out.String() + errOut.String()
}

func TestSweepCollisions(t *testing.T) {
	cases := []struct {
		name     string
		doc      any
		wantFail bool
		wantMsg  string // substring that must appear when a failure is expected
	}{
		{
			name: "baseline-only input passes",
			doc:  withBaseline(),
		},
		{
			name: "a new same-variant identical encoding fails",
			doc: withBaseline(
				map[string]any{"format": "mov\tRm,Rn", "code": "0110nnnnmmmm0011", "J4": true},
				map[string]any{"format": "zzz\tRm,Rn", "code": "0110nnnnmmmm0011", "J4": true},
			),
			wantFail: true,
			wantMsg:  "new same-variant encoding collision",
		},
		{
			// The rule that keeps the sweep usable. LDC Rm,PTEH and DSP's
			// LDC Rm,MOD share an encoding and never ship on one core; failing
			// on that would fail on ~94 legitimate entries and the sweep would
			// be deleted.
			name: "an identical encoding on DISJOINT variants passes",
			doc: withBaseline(
				map[string]any{"format": "ldc\tRm,PTEH", "code": "0100mmmm01011110", "J4": true},
				map[string]any{"format": "ldc\tRm,MOD", "code": "0100mmmm01011110", "DSP": true},
			),
		},
		{
			// The list may only shrink, and it must not outlive what it excuses.
			name:     "a baseline entry that no longer collides fails",
			doc:      map[string]any{"instructions": baselineRows[:2]},
			wantFail: true,
			wantMsg:  "no longer collides",
		},
		{
			name:     "an empty instruction array fails closed",
			doc:      map[string]any{"instructions": []any{}},
			wantFail: true,
			wantMsg:  "nothing was swept",
		},
		{
			name:     "a missing instructions key fails closed",
			doc:      map[string]any{},
			wantFail: true,
			wantMsg:  "nothing was swept",
		},
		{
			name:     "unparseable JSON fails closed",
			doc:      "{not json",
			wantFail: true,
			wantMsg:  "cannot read",
		},
		{
			// Every pair would trivially share no variant, so the sweep would
			// report zero collisions over any input at all.
			name: "rows with no boolean variant column fail closed",
			doc: map[string]any{"instructions": []map[string]any{
				{"format": "a", "code": "0000000000000000"},
				{"format": "b", "code": "0000000000000000"},
			}},
			wantFail: true,
			wantMsg:  "boolean product column",
		},
		{
			name: "rows carrying no code at all fail closed",
			doc: map[string]any{"instructions": []map[string]any{
				{"format": "a", "J4": true},
				{"format": "b", "J4": true},
			}},
			wantFail: true,
			wantMsg:  "nothing to compare",
		},
		{
			// Not in the Python original. A code the encoding parser cannot
			// read would otherwise be dropped from the comparison silently,
			// which is the fail-open shape this whole check exists to avoid.
			name: "an unparseable encoding fails closed",
			doc: withBaseline(
				map[string]any{"format": "mov\tRm,Rn", "code": "0110nnnn", "J4": true},
			),
			wantFail: true,
			wantMsg:  "unparseable encoding",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rc, out := runSweep(t, tc.doc)
			if (rc != 0) != tc.wantFail {
				t.Fatalf("exit %d, want %s\noutput:\n%s", rc,
					map[bool]string{true: "non-zero", false: "0"}[tc.wantFail], out)
			}
			if tc.wantMsg != "" && !strings.Contains(out, tc.wantMsg) {
				t.Fatalf("exit status agreed, but wanted message %q\noutput:\n%s", tc.wantMsg, out)
			}
			if tc.wantFail && !strings.Contains(out, "::error::") {
				t.Errorf("a failure must emit a ::error:: annotation\noutput:\n%s", out)
			}
		})
	}
}

// TestSweepCollisionsOnRealInsnsJSON is the case the fixtures cannot stand in
// for: the shipped baseline must describe the shipped encoding database, both
// that nothing new collides and that neither excused pair has gone stale.
func TestSweepCollisionsOnRealInsnsJSON(t *testing.T) {
	const real = "../../../../docs/insns.json"
	var out, errOut bytes.Buffer
	if rc := sweepCollisions(real, &out, &errOut); rc != 0 {
		t.Fatalf("sweep of %s exited %d, want 0\n%s%s", real, rc, out.String(), errOut.String())
	}
	if !strings.Contains(out.String(), "2 baselined, 0 new") {
		t.Errorf("summary = %q, want the two baselined pairs and no new ones", strings.TrimSpace(out.String()))
	}
}

// TestRunCollisionsRejectsPositionalArgs guards the CLI surface: the Python it
// replaces took the path positionally, so a stale invocation must be told, not
// silently swept over the default file.
func TestRunCollisionsRejectsPositionalArgs(t *testing.T) {
	if rc := runCollisions([]string{"docs/insns.json"}); rc == 0 {
		t.Error("runCollisions accepted a positional path, want non-zero exit")
	}
}
