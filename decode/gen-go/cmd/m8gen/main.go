// Command m8gen ties the M8 fault classifier and emitter into generated
// batched fault-test images. It loads the instruction spec (with the J4
// overlay), classifies every instruction, assigns each a STABLE numeric ID
// (instructions sorted by Name, so IDs do not churn between runs), and writes:
//
//	m8_dside.S     -- D-side load/store fault cases (EmitImage DSide)
//	m8_ifetch_N.S  -- I-fetch fault cases, split into 3 sub-images (EmitImage IFetch)
//	m8_manifest.txt -- ID -> instruction Name -> bucket/axis/skip-reason map
//
// All outputs go to -o (typically ../../sim/tests). The .S files #include
// "m8_runtime.inc" and define _m8_run_all (see faultgen/emit.go).
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/faultgen"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func main() {
	specDir := flag.String("spec", "spec", "directory of TOML instruction set files")
	overlay := flag.String("overlay", "spec/sh4", "overlay spec dir (additive, for ISA variants)")
	outDir := flag.String("o", "../../sim/tests", "output directory for generated images")
	skipList := flag.String("skip", "", "comma-separated D-side emitted case IDs to exclude from _m8_run_all (failure enumeration; cases still emitted, IDs stable)")
	flag.Parse()

	skip, err := parseSkip(*skipList)
	if err != nil {
		fmt.Fprintln(os.Stderr, "skip:", err)
		os.Exit(1)
	}

	var s *spec.Spec
	if *overlay != "" {
		s, err = spec.LoadProfile(*specDir, *overlay)
	} else {
		s, err = spec.Load(*specDir)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "load:", err)
		os.Exit(1)
	}
	if err := spec.Validate(s); err != nil {
		fmt.Fprintln(os.Stderr, "validate:", err)
		os.Exit(1)
	}

	// Deterministic ID assignment: sort instructions by Name, then classify.
	// The stable index (1-based) is the case ID used everywhere downstream.
	instrs := make([]spec.Instr, len(s.Instrs))
	copy(instrs, s.Instrs)
	sort.SliceStable(instrs, func(i, j int) bool {
		return instrs[i].Name < instrs[j].Name
	})

	classes := make([]faultgen.Class, len(instrs))
	for i, in := range instrs {
		classes[i] = faultgen.Classify(in)
	}

	dside, err := faultgen.EmitImageSkip(classes, faultgen.DSide, skip)
	if err != nil {
		fmt.Fprintln(os.Stderr, "emit dside:", err)
		os.Exit(1)
	}
	// The I-fetch axis is partitioned into sub-images (m8_ifetch_0.S ..
	// m8_ifetch_N.S) so each runs as a SEPARATE sim (CPU reset) under the co-sim
	// cumulative-fetch ceiling; together they execute ALL emitted I-fetch cases.
	ifetchImgs, err := faultgen.EmitIFetchImages(classes)
	if err != nil {
		fmt.Fprintln(os.Stderr, "emit ifetch:", err)
		os.Exit(1)
	}
	// The I-fetch-delay-slot axis (instruction under test planted in a branch
	// delay slot; its fetch IMISSes; the restart must land on the branch) is also
	// partitioned into sub-images for the cumulative-fetch ceiling.
	idslotImgs, err := faultgen.EmitIFetchDSlotImages(classes)
	if err != nil {
		fmt.Fprintln(os.Stderr, "emit ifetch-dslot:", err)
		os.Exit(1)
	}
	manifest := buildManifest(classes, skip)

	if err := os.MkdirAll(*outDir, 0o755); err != nil {
		fmt.Fprintln(os.Stderr, "mkdir:", err)
		os.Exit(1)
	}
	outputs := map[string]string{
		"m8_dside.S":      dside,
		"m8_manifest.txt": manifest,
	}
	for i, img := range ifetchImgs {
		outputs[fmt.Sprintf("m8_ifetch_%d.S", i)] = img
	}
	for i, img := range idslotImgs {
		outputs[fmt.Sprintf("m8_idslot_%d.S", i)] = img
	}
	for name, content := range outputs {
		if err := os.WriteFile(filepath.Join(*outDir, name), []byte(content), 0o644); err != nil {
			fmt.Fprintln(os.Stderr, "write", name, ":", err)
			os.Exit(1)
		}
	}
	// Remove the obsolete single-image m8_ifetch.S if a prior run left it.
	_ = os.Remove(filepath.Join(*outDir, "m8_ifetch.S"))
	fmt.Fprintf(os.Stderr, "m8gen: %d instructions classified -> %s\n", len(classes), *outDir)
}

func bucketName(b faultgen.Bucket) string {
	switch b {
	case faultgen.PrivMem:
		return "PrivMem"
	case faultgen.Bespoke:
		return "Bespoke"
	default:
		return "General"
	}
}

// buildManifest renders, per axis, the emitted case ID -> instruction Name ->
// bucket map plus the skipped instructions and why. The IDs are exactly those
// EmitImage assigns (per-axis, 1-based over emitted cases), so a co-sim
// "Result=<ID>" on m8_dside.img/m8_ifetch.img is directly decodable here.
// parseSkip parses a comma-separated list of positive integer case IDs into a
// set. Empty string -> nil (default, no skips).
func parseSkip(s string) (map[int]bool, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, nil
	}
	out := make(map[int]bool)
	for _, tok := range strings.Split(s, ",") {
		tok = strings.TrimSpace(tok)
		if tok == "" {
			continue
		}
		var id int
		if _, err := fmt.Sscanf(tok, "%d", &id); err != nil || id < 1 {
			return nil, fmt.Errorf("invalid skip ID %q", tok)
		}
		out[id] = true
	}
	return out, nil
}

func buildManifest(classes []faultgen.Class, skip map[int]bool) string {
	var b strings.Builder
	b.WriteString("# M8 fault-harness manifest. GENERATED by m8gen. Do not edit.\n")
	b.WriteString("# IDs are per-axis emitted case numbers (== co-sim Result=<ID>).\n")
	for _, ax := range []struct {
		axis faultgen.Axis
		name string
		file string
	}{
		{faultgen.DSide, "D-side", "m8_dside.S"},
		{faultgen.IFetch, "I-fetch", "m8_ifetch_N.S"},
	} {
		fmt.Fprintf(&b, "\n## %s axis (%s)\n", ax.name, ax.file)
		entries := faultgen.ImageManifest(classes, ax.axis)
		emitted := 0
		for _, e := range entries {
			if !e.Emitted {
				continue
			}
			emitted++
			tag := ""
			if ax.axis == faultgen.DSide && skip[e.ID] {
				tag = "    skipped-for-enumeration: " + fmt.Sprint(e.ID)
			}
			// MAC dual-base D-side cases run 3 fault positions, each reporting a
			// distinct ID (1000*pos + case ID) so a CI Result=<ID> localises the
			// faulting operand position.
			if ax.axis == faultgen.DSide && strings.HasPrefix(e.Name, "MAC.") {
				tag += fmt.Sprintf("    (3 positions report %d/%d/%d: 1=op1-only,2=op2-only,3=both-cold)",
					1000+e.ID, 2000+e.ID, 3000+e.ID)
			}
			fmt.Fprintf(&b, "%-4d %-20s %s%s\n", e.ID, e.Name, bucketName(e.Bucket), tag)
		}
		fmt.Fprintf(&b, "# %d emitted; skipped:\n", emitted)
		for _, e := range entries {
			if e.Emitted {
				continue
			}
			fmt.Fprintf(&b, "#   %-20s %s\n", e.Name, e.SkipReason)
		}
	}
	return b.String()
}
