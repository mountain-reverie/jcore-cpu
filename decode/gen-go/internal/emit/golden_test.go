package emit

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// TestSh2instrAgainstClojureGolden is the M2 verification gate. It
// renders the production spec through sh2instr.c.tmpl, normalizes both
// the new output and the frozen Clojure golden via scripts/normalize.sh,
// then sorts the if/else-if clauses within each lineN function before
// comparing. Per design §3.3 our output is sorted while the Clojure
// generator emits in CSV row order — clause-sorted comparison strips
// that ordering noise while still catching any structural,
// instruction-content, or mask/match difference.
func TestSh2instrAgainstClojureGolden(t *testing.T) {
	s, err := spec.Load("../../spec")
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.Validate(s); err != nil {
		t.Fatal(err)
	}
	d, err := model.Build(s, 72)
	if err != nil {
		t.Fatal(err)
	}

	root := t.TempDir()
	outDir := filepath.Join(root, "out")
	goldDir := filepath.Join(root, "gold")
	if err := All(d, outDir); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(goldDir, 0o755); err != nil {
		t.Fatal(err)
	}
	src, err := os.ReadFile("../../testdata/golden/clj/sh2instr.c")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(goldDir, "sh2instr.c"), src, 0o644); err != nil {
		t.Fatal(err)
	}
	for _, dir := range []string{outDir, goldDir} {
		if err := NormalizeForDiff(dir, dir+".normalized"); err != nil {
			t.Fatalf("NormalizeForDiff %s: %v", dir, err)
		}
	}

	got, err := canonicalize(outDir + ".normalized/sh2instr.c")
	if err != nil {
		t.Fatal(err)
	}
	want, err := canonicalize(goldDir + ".normalized/sh2instr.c")
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		gotPath := filepath.Join(root, "got.canonical")
		wantPath := filepath.Join(root, "want.canonical")
		os.WriteFile(gotPath, []byte(got), 0o644)
		os.WriteFile(wantPath, []byte(want), 0o644)
		cmd := exec.Command("diff", "-u", wantPath, gotPath)
		out, _ := cmd.CombinedOutput()
		t.Errorf("structural diff (clause-sorted within each lineN):\n%s", out)
	}
}

// lineFuncRE matches the opening of a lineN function body. We use it
// to find the spans inside which clauses get sorted.
var lineFuncRE = regexp.MustCompile(`^static int line\d+\(char \*str, size_t size, uint16_t instr\) \{$`)

// canonicalize reads a normalized sh2instr.c and rewrites it with the
// if/else-if clauses inside each lineN function sorted by their byte
// representation. The trailing `else { return -1; }` stays in place,
// as does everything outside the line functions (preamble, dispatch
// table, op_name, print_instr).
func canonicalize(path string) (string, error) {
	src, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	lines := strings.Split(string(src), "\n")

	var out []string
	i := 0
	for i < len(lines) {
		line := lines[i]
		out = append(out, line)
		if !lineFuncRE.MatchString(line) {
			i++
			continue
		}
		// We're inside a lineN function. Collect clauses until the
		// function's closing brace at column 0 (`^}$`).
		// Each clause is a contiguous run of lines that ends in a
		// closing `}`, except the final else clause stays separate.
		i++
		var clauses [][]string
		var current []string
		var elseTail []string
		for i < len(lines) {
			ln := lines[i]
			if ln == "}" {
				// end of the lineN function body
				break
			}
			current = append(current, ln)
			// A clause ends with `}` (the trailing snippet at the end
			// of the closing brace before " else if" or " else").
			// We detect "this is the final line of a clause" by the
			// presence of `}` at the end after stripping. Since we're
			// normalized (no trailing whitespace), it's exactly `}`.
			if ln == "}" || strings.HasSuffix(ln, "}") {
				// Determine whether this clause is "else { return -1; }"
				// (terminator) or an if/else-if clause (sortable).
				if len(current) >= 2 && strings.HasPrefix(current[0], "} else {") {
					elseTail = current
				} else {
					clauses = append(clauses, current)
				}
				current = nil
			}
			i++
		}
		// At this point i is on the closing `}` of the lineN body
		// (or end of file). Sort the if/else-if clauses.
		sort.Slice(clauses, func(a, b int) bool {
			return strings.Join(clauses[a], "\n") < strings.Join(clauses[b], "\n")
		})
		// The first clause is the only one starting with "if " (not "} else if").
		// After sorting we need to rewrite so the leading clause is "if (...)"
		// and subsequent ones are "} else if (...)". Strip leading "} else if"
		// → "if" on whichever clause is first; prepend "} else if" on others.
		for idx, c := range clauses {
			head := c[0]
			if idx == 0 {
				// strip leading "} else if" → "if"
				if rest, ok := strings.CutPrefix(head, "} else if"); ok {
					c[0] = "if" + rest
				}
				// already starts with "if (...)" — leave alone
			} else {
				// ensure starts with "} else if"
				if rest, ok := strings.CutPrefix(head, "if "); ok {
					c[0] = "} else if " + rest
				}
			}
		}
		for _, c := range clauses {
			out = append(out, c...)
		}
		out = append(out, elseTail...)
		// i is on the closing `}` of the function — let the outer loop
		// emit it on the next iteration.
	}
	return strings.Join(out, "\n"), nil
}

