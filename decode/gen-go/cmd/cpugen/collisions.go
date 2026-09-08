package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/insns"
)

// baseline lists the identical-encoding same-variant pairs that exist today,
// as the two `format` strings sorted, with tabs normalised to a single space.
//
// THIS LIST MAY ONLY SHRINK. A baseline entry that no longer collides is also
// a failure, so the list cannot quietly outlive the defects it excuses. Each
// entry needs a reason and an owner; "it was already like that" is why the
// list exists, not a reason to add to it. Same discipline, and same reason, as
// the waiver list in jcore-workspace docs/fact-ownership.md.
//
// A baseline is what makes this a check rather than a warning: a sweep that
// failed on these two would have been switched off the day it landed.
var baseline = map[[2]string]bool{
	// 0100mmmm01110110 -- the DSP LDS pair. `lds Rm,A0` and `lds.l @Rm+,A0`
	// carry the same encoding in the source manual transcription; one of the
	// two is wrong. Owner: Wave-2 B4 (encoding sweep).
	{"lds Rm,A0", "lds.l @Rm+,A0"}: true,
	// 0100nnnn01100010 -- the DSP STS pair, same shape, same owner.
	{"sts.l A0,@-Rn", "sts.l DSR,@-Rn"}: true,
}

func runCollisions(args []string) int {
	fs := flag.NewFlagSet("collisions", flag.ContinueOnError)
	jsonPath := fs.String("insns", "../../docs/insns.json", "path to insns.json")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if rest := fs.Args(); len(rest) > 0 {
		fmt.Fprintf(os.Stderr, "collisions: unexpected argument %q; use -insns=PATH\n", rest[0])
		return 2
	}
	return sweepCollisions(*jsonPath, os.Stdout, os.Stderr)
}

// sweepCollisions is the whole check, factored out of runCollisions so the
// fixture suite can drive it over a synthetic insns.json and read back both
// streams. Returns the process exit status.
func sweepCollisions(path string, stdout, stderr io.Writer) int {
	fail := func(format string, a ...any) {
		msg := fmt.Sprintf(format, a...)
		// Both streams, deliberately. `::error::` on stdout is what turns the
		// finding into a GitHub annotation on the PR; `FAIL:` on stderr is what
		// makes it visible when the tool is run by hand or piped.
		fmt.Fprintf(stdout, "::error::%s\n", msg)
		fmt.Fprintf(stderr, "FAIL: %s\n", msg)
	}

	doc, err := insns.Load(path)
	if err != nil {
		fail("cannot read %s: %v", path, err)
		return 1
	}
	rep, err := insns.Collisions(doc)
	if err != nil {
		fail("%s: %v", path, err)
		return 1
	}

	rc := 0
	seen := map[[2]string]bool{}
	for _, c := range rep.Found {
		seen[c.Pair()] = true
		if baseline[c.Pair()] {
			continue
		}
		rc = 1
		fail("new same-variant encoding collision: `%s` and `%s` both encode as %s "+
			"and are both present on %s. Re-home one of them with "+
			"`cpugen freespace --avoid <the other> --form <its form>` "+
			"(--avoid is comma-separated, and these formats contain commas, "+
			"so pass one variant per invocation).",
			c.A, c.B, c.Code, strings.Join(c.Shared, "/"))
	}

	var stale [][2]string
	for pair := range baseline {
		if !seen[pair] {
			stale = append(stale, pair)
		}
	}
	sort.Slice(stale, func(i, j int) bool {
		if stale[i][0] != stale[j][0] {
			return stale[i][0] < stale[j][0]
		}
		return stale[i][1] < stale[j][1]
	})
	for _, pair := range stale {
		rc = 1
		fail("baseline entry `%s` / `%s` no longer collides. Delete it from "+
			"`baseline` in cmd/cpugen/collisions.go -- the list may only shrink, "+
			"and it must not outlive what it excuses.", pair[0], pair[1])
	}

	baselined := 0
	for pair := range seen {
		if baseline[pair] {
			baselined++
		}
	}
	fmt.Fprintf(stdout, "swept %d instructions over %d variants (%s); %d same-variant "+
		"identical-encoding collision(s), %d baselined, %d new\n",
		rep.Swept, len(rep.Variants), strings.Join(rep.Variants, ","),
		len(rep.Found), baselined, len(rep.Found)-baselined)
	return rc
}
