package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/emit"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/insns"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func runInsns(args []string) int {
	fs := flag.NewFlagSet("insns", flag.ExitOnError)
	specDir := fs.String("spec", "spec", "spec dir")
	jsonPath := fs.String("json", "../../docs/insns.json", "path to insns.json")
	timingDir := fs.String("timing-dir", "timing", "per-variant timing tables")
	check := fs.Bool("check", false, "verify insns.json is up to date; non-zero exit if not")
	fs.Parse(args) //nolint:errcheck

	var vds []insns.VariantData
	for _, v := range insns.Variants() {
		set, err := insns.LoadVariant(*specDir, v)
		if err != nil {
			fmt.Fprintln(os.Stderr, "insns:", err)
			return 1
		}
		tabPath := filepath.Join(*timingDir, strings.ToLower(v.Name)+".toml")
		var tab *insns.Table
		if _, statErr := os.Stat(tabPath); os.IsNotExist(statErr) {
			tab = &insns.Table{}
		} else {
			var err error
			tab, err = insns.LoadTable(tabPath)
			if err != nil {
				fmt.Fprintln(os.Stderr, "insns: timing:", err)
				return 1
			}
		}
		vds = append(vds, insns.VariantData{Variant: v, Set: set, Tab: tab})
	}
	doc, err := insns.Load(*jsonPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "insns: load json:", err)
		return 1
	}
	rep, err := insns.Sync(doc, vds)
	if err != nil {
		fmt.Fprintln(os.Stderr, "insns: sync:", err)
		return 1
	}
	out, err := doc.Bytes()
	if err != nil {
		fmt.Fprintln(os.Stderr, "insns: emit:", err)
		return 1
	}
	if *check {
		cur, _ := os.ReadFile(*jsonPath)
		if string(cur) != string(out) {
			fmt.Fprintln(os.Stderr, "insns.json is out of date — run `make -C decode insns`")
			return 1
		}
		return 0
	}
	if err := os.WriteFile(*jsonPath, out, 0o644); err != nil {
		fmt.Fprintln(os.Stderr, "insns: write:", err)
		return 1
	}
	fmt.Fprintf(os.Stderr, "insns.json updated (%d matched, %d appended)\n", rep.Matched, len(rep.Appended))
	return 0
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "insns" {
		os.Exit(runInsns(os.Args[2:]))
	}
	specDir := flag.String("spec", "spec", "directory of TOML instruction set files")
	width := flag.Int("w", 72, "ROM width: 64 or 72")
	outDir := flag.String("o", "", "output directory; if empty, validate only and exit")
	overlay := flag.String("overlay", "", "optional overlay spec dir (additive, for ISA variants)")
	flag.Parse()

	var s *spec.Spec
	var err error
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
	if *outDir == "" {
		fmt.Fprintf(os.Stderr, "loaded %d instructions from %s (no -o given; nothing emitted)\n",
			len(s.Instrs), *specDir)
		return
	}
	d, err := model.Build(s, *width)
	if err != nil {
		fmt.Fprintln(os.Stderr, "build:", err)
		os.Exit(1)
	}
	if err := emit.All(d, *outDir); err != nil {
		fmt.Fprintln(os.Stderr, "emit:", err)
		os.Exit(1)
	}
	if err := emit.CopyStatic(filepath.Join(*specDir, "static"), *outDir); err != nil {
		fmt.Fprintln(os.Stderr, "copy static:", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "emitted to %s\n", *outDir)
}
