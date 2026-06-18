package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/emit"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func main() {
	specDir := flag.String("spec", "spec", "directory of TOML instruction set files")
	width := flag.Int("w", 72, "ROM width: 64 or 72")
	outDir := flag.String("o", "", "output directory; if empty, validate only and exit")
	overlay := flag.String("overlay", "", "optional overlay spec dir (additive, for ISA variants)")
	profilePath := flag.String("profile", "", "optional variant profile TOML (drop list)")
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
	if *profilePath != "" {
		prof, err := spec.ReadProfile(*profilePath)
		if err != nil {
			fmt.Fprintln(os.Stderr, "profile:", err)
			os.Exit(1)
		}
		if err := spec.ApplyDrops(s, prof.Drop); err != nil {
			fmt.Fprintln(os.Stderr, "profile:", err)
			os.Exit(1)
		}
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
