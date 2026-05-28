package main

import (
	"flag"
	"fmt"
	"os"
	"sort"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

func main() {
	csvPath := flag.String("csv", "../gen/SH-2 Instruction Set.csv", "path to CSV input")
	histOnly := flag.Bool("histogram", false, "print column usage histogram and exit")
	outDir := flag.String("out", "spec", "output directory for split TOML files")
	flag.Parse()

	f, err := os.Open(*csvPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer f.Close()

	groups, err := readInstructionGroups(f)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	if *histOnly {
		// read header to learn the column list
		f2, _ := os.Open(*csvPath)
		defer f2.Close()
		cols := readHeader(f2)
		h := columnHistogram(groups, cols)
		sort.Strings(cols)
		for _, c := range cols {
			fmt.Printf("%-22s %d\n", c, h[c])
		}
		return
	}

	dropped := map[string]bool{} // populated by Task 4's findings if needed
	byCat := map[string][]spec.Instr{}
	for _, g := range groups {
		instr, err := convertGroup(g, dropped)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		cat := categoryFor(g.Name)
		byCat[cat] = append(byCat[cat], instr)
	}
	if err := emitTOML(*outDir, byCat); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "wrote %d instructions across %d files into %s\n",
		len(groups), len(byCat), *outDir)
}
