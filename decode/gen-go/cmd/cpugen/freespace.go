package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strings"
	"text/tabwriter"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/freespace"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/insns"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

// formFromOpcode turns a concrete encoding into a search form by freeing the
// bits it fixes while keeping its operand fields in place. This is mode C:
// "give me other encodings with this instruction's field layout".
func formFromOpcode(pattern string) string {
	var b strings.Builder
	for _, c := range strings.ReplaceAll(pattern, " ", "") {
		switch c {
		case 'n', 'm', 'd', 'i':
			b.WriteRune(c)
		default:
			b.WriteByte('-')
		}
	}
	return b.String()
}

func runFreespace(args []string) int {
	fs := flag.NewFlagSet("freespace", flag.ContinueOnError)
	specDir := fs.String("spec", "spec", "spec dir")
	overlay := fs.String("overlay", "", "spec overlay subdirectory (e.g. sh2a) for mode C lookup")
	jsonPath := fs.String("insns", "../../docs/insns.json", "path to insns.json")
	avoid := fs.String("avoid", "", "comma-separated variants the encoding must not collide with (required)")
	form := fs.String("form", "", "bit pattern (----nnnnmmmm----) or named shape (Rm,Rn); overrides the instruction's own form")
	region := fs.String("region", "", "comma-separated hex nibble prefixes constraining the encoding, e.g. 4 or 0,4,8")
	family := fs.String("family", "", "instruction group to rank proximity against, e.g. \"Shift Instructions\"")
	twoWord := fs.Bool("two-word", false, "candidate is word1 of a two-word instruction")
	limit := fs.Int("n", 20, "maximum candidates to print")
	asJSON := fs.Bool("json", false, "emit results as JSON")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	if strings.TrimSpace(*avoid) == "" {
		fmt.Fprintln(os.Stderr, "freespace: --avoid is required; known variants: "+
			strings.Join(freespace.Variants(), ", "))
		return 2
	}

	pattern, exitCode := resolveForm(fs.Args(), *form, *specDir, *overlay)
	if exitCode != 0 {
		return exitCode
	}

	doc, err := insns.Load(*jsonPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "freespace: load insns.json:", err)
		return 1
	}
	claims, err := freespace.Claims(doc)
	if err != nil {
		fmt.Fprintln(os.Stderr, "freespace:", err)
		return 1
	}

	cands, err := freespace.Search(freespace.Options{
		Form:    pattern,
		Regions: splitList(*region),
		Avoid:   splitList(*avoid),
		TwoWord: *twoWord,
	}, claims)
	if err != nil {
		fmt.Fprintln(os.Stderr, "freespace:", err)
		return 2
	}
	freespace.Rank(cands, *family, claims)

	total := len(cands)
	virgin := 0
	for _, c := range cands {
		if c.Virgin {
			virgin++
		}
	}
	if *limit > 0 && len(cands) > *limit {
		cands = cands[:*limit]
	}

	if *asJSON {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(cands); err != nil {
			fmt.Fprintln(os.Stderr, "freespace:", err)
			return 1
		}
		return 0
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "CODE\tSTATUS\tSHADOWS\tNEAREST FAMILY MEMBER")
	sawShareable := false
	for _, c := range cands {
		status, shadows := candidateStatus(c)
		if len(c.Shareable) > 0 {
			sawShareable = true
		}
		near := "—"
		if n, ok := freespace.Nearest(c, *family, claims); ok {
			near = strings.ReplaceAll(n.Format, "\t", " ")
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\n", c.Code, status, shadows, near)
	}
	w.Flush() //nolint:errcheck
	fmt.Printf("\n%s: %d candidates survived --avoid, %d of them virgin\n", pattern, total, virgin)
	if sawShareable {
		fmt.Println(`note: "shareable?" means only word 1 was compared. Verify a free ext_word[15:12] discriminant remains against the extension words listed.`)
	}
	return 0
}

// resolveForm picks the search form: --form (mode A/B) wins, otherwise the
// named spec instruction's own field layout (mode C).
func resolveForm(rest []string, form, specDir, overlay string) (string, int) {
	if form != "" {
		if p, ok := freespace.Shape(form); ok {
			return p, 0
		}
		return form, 0 // treated as a literal pattern; Search validates it
	}
	if len(rest) != 1 {
		fmt.Fprintln(os.Stderr, "freespace: give one instruction name, or use --form")
		return "", 2
	}
	var s *spec.Spec
	var err error
	if overlay != "" {
		s, err = spec.LoadProfile(specDir, specDir+"/"+overlay)
	} else {
		s, err = spec.Load(specDir)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "freespace: load spec:", err)
		return "", 1
	}
	for _, in := range s.Instrs {
		if in.Name == rest[0] {
			return formFromOpcode(in.Opcode), 0
		}
	}
	fmt.Fprintf(os.Stderr, "freespace: no instruction %q in %s\n", rest[0], specDir)
	return "", 1
}

// candidateStatus renders a candidate's STATUS and SHADOWS table cells.
// Shadows and shareable claims are independent findings — a candidate can
// have both — so both are rendered rather than one overwriting the other.
func candidateStatus(c freespace.Candidate) (status, shadows string) {
	status = "shadows"
	if c.Virgin {
		status = "virgin"
	}
	var cells []string
	if len(c.Shadows) > 0 {
		cells = append(cells, formatList(c.Shadows))
	}
	if len(c.Shareable) > 0 {
		status = "shareable?"
		cells = append(cells, formatList(c.Shareable))
	}
	if len(cells) == 0 {
		return status, "—"
	}
	return status, strings.Join(cells, "; ")
}

// maxShown caps how many claim descriptions a table cell lists. A common
// query such as --form Rm,Rn overlaps ~100 legacy encodings on one candidate,
// and printing them all destroys the table. --json still carries the full set.
const maxShown = 5

// formatList renders a claim list for a table cell, capped at maxShown.
func formatList(items []string) string {
	if len(items) == 0 {
		return "—"
	}
	if len(items) <= maxShown {
		return strings.Join(items, "; ")
	}
	return fmt.Sprintf("%s; +%d more",
		strings.Join(items[:maxShown], "; "), len(items)-maxShown)
}

func splitList(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
