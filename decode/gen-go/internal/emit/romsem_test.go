package emit

import (
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"testing"
)

// romArchSemantics reduces a decode_table_rom.vhd architecture body to what it
// MEANS: for every driven signal, the ROM word bit-range it reads and the value
// it produces for every possible code of that range (with `when others`
// expanded over the unnamed codes).
//
// Used to compare the generated ROM architecture against the frozen Clojure
// golden. The architecture is now emitted from the Encoding rather than
// hand-written, so the order of the selector blocks and of the arms within a
// block is ours, not the Clojure generator's. Comparing the two as SETS of
// (signal, bit-range, code -> value) tuples ignores that ordering while still
// catching any real difference: a moved field, a changed code, a different
// value, a dropped or added signal. Same rationale as the clause-sorted
// comparison in TestSh2instrAgainstClojureGolden.
//
// This deliberately does NOT relax the comparison of the microcode_rom
// constant, which callers still compare byte-for-byte.
type romSignalSem struct {
	Hi, Lo int
	Table  map[int]string // code -> VHDL value expression; -1 => constant assignment
}

var (
	romSelBlockRe  = regexp.MustCompile(`(?s)with line\((\d+)(?: downto (\d+))?\) select\s*\n\s*([\w.]+) <=\s*\n(.*?);\n`)
	romBitAsgnRe   = regexp.MustCompile(`(?m)^\s{4}([\w.]+) <= line\((\d+)\);$`)
	romConstAsgnRe = regexp.MustCompile(`(?m)^\s{4}([\w.]+) <= ([^;\n]+);$`)
)

func romArchSemantics(t *testing.T, text string) map[string]romSignalSem {
	t.Helper()
	i := strings.Index(text, "\nbegin\n")
	if i < 0 {
		t.Fatalf("no architecture body")
	}
	body := text[i:]

	out := map[string]romSignalSem{}
	for _, m := range romSelBlockRe.FindAllStringSubmatch(body, -1) {
		hi, _ := strconv.Atoi(m[1])
		lo := hi
		if m[2] != "" {
			lo, _ = strconv.Atoi(m[2])
		}
		lhs := m[3]
		width := hi - lo + 1
		table := map[int]string{}
		others := ""
		for _, line := range strings.Split(m[4], "\n") {
			line = strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(line), ","))
			if line == "" {
				continue
			}
			idx := strings.LastIndex(line, " when ")
			if idx < 0 {
				t.Fatalf("%s: unparsable arm %q", lhs, line)
			}
			val := strings.TrimSpace(line[:idx])
			choice := strings.TrimSpace(line[idx+len(" when "):])
			if choice == "others" {
				others = val
				continue
			}
			for _, c := range strings.Split(choice, "|") {
				c = strings.Trim(strings.TrimSpace(c), `"`)
				n, err := strconv.ParseInt(c, 2, 32)
				if err != nil {
					t.Fatalf("%s: bad code %q", lhs, c)
				}
				table[int(n)] = val
			}
		}
		for c := 0; c < 1<<width; c++ {
			if _, ok := table[c]; !ok {
				table[c] = others
			}
		}
		out[lhs] = romSignalSem{Hi: hi, Lo: lo, Table: table}
	}
	for _, m := range romBitAsgnRe.FindAllStringSubmatch(body, -1) {
		n, _ := strconv.Atoi(m[2])
		out[m[1]] = romSignalSem{Hi: n, Lo: n, Table: map[int]string{0: "'0'", 1: "'1'"}}
	}
	for _, m := range romConstAsgnRe.FindAllStringSubmatch(body, -1) {
		if strings.Contains(m[2], "line(") {
			continue
		}
		if _, seen := out[m[1]]; seen {
			continue
		}
		out[m[1]] = romSignalSem{Hi: -1, Lo: -1, Table: map[int]string{-1: strings.TrimSpace(m[2])}}
	}
	return out
}

// assertROMSemanticsEqual reports every difference between two architecture
// bodies' meaning, ignoring block/arm ordering.
func assertROMSemanticsEqual(t *testing.T, wantText, gotText, label string) {
	t.Helper()
	want := romArchSemantics(t, wantText)
	got := romArchSemantics(t, gotText)

	var names []string
	seen := map[string]bool{}
	for k := range want {
		names = append(names, k)
		seen[k] = true
	}
	for k := range got {
		if !seen[k] {
			names = append(names, k)
		}
	}
	sort.Strings(names)

	for _, n := range names {
		w, okW := want[n]
		g, okG := got[n]
		switch {
		case !okG:
			t.Errorf("%s: signal %s driven in golden but not in generated output", label, n)
		case !okW:
			t.Errorf("%s: signal %s driven in generated output but not in golden", label, n)
		case w.Hi != g.Hi || w.Lo != g.Lo:
			t.Errorf("%s: signal %s reads line(%d downto %d) in golden, line(%d downto %d) in generated output",
				label, n, w.Hi, w.Lo, g.Hi, g.Lo)
		default:
			var diffs []string
			for c, wv := range w.Table {
				if gv := g.Table[c]; gv != wv {
					diffs = append(diffs, fmt.Sprintf("code %d: golden=%q generated=%q", c, wv, gv))
				}
			}
			sort.Strings(diffs)
			if len(diffs) > 0 {
				t.Errorf("%s: signal %s decodes differently:\n  %s", label, n, strings.Join(diffs, "\n  "))
			}
		}
	}
}
