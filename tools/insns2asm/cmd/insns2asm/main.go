// Command insns2asm generates assembler definitions from jcore docs/insns.json.
package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/format"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/gas"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/ir"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/llvm"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/loader"
	"github.com/j-core/jcore-cpu/tools/insns2asm/internal/oracle"
)

func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "insns2asm:", err)
		os.Exit(1)
	}
}

func run(args []string, stdout io.Writer) error {
	fs := flag.NewFlagSet("insns2asm", flag.ContinueOnError)
	in := fs.String("in", "docs/insns.json", "path to insns.json")
	emit := fs.String("emit", "check", "what to emit: gas|llvm|check")
	out := fs.String("out", "", "output file (default stdout)")
	only := fs.String("only", "", "emit only instructions whose mnemonic contains this substring")
	if err := fs.Parse(args); err != nil {
		return err
	}

	f, err := os.Open(*in)
	if err != nil {
		return err
	}
	defer f.Close()
	raw, dropped, err := loader.Load(f)
	if err != nil {
		return err
	}
	if dropped > 0 {
		fmt.Fprintf(os.Stderr, "insns2asm: excluded %d DSP/coproc instructions\n", dropped)
	}
	insns, err := ir.Build(raw)
	if err != nil {
		return err
	}

	if *only != "" {
		filtered := insns[:0:0]
		for _, in := range insns {
			if strings.Contains(in.Mnemonic, *only) {
				filtered = append(filtered, in)
			}
		}
		insns = filtered
	}

	w := stdout
	if *out != "" {
		of, err := os.Create(*out)
		if err != nil {
			return err
		}
		defer of.Close()
		w = of
	}

	switch *emit {
	case "gas":
		out, err := gas.EmitDelta(insns)
		if err != nil {
			return err
		}
		_, err = io.WriteString(w, out)
		return err
	case "llvm":
		_, err = io.WriteString(w, llvm.EmitInstrInfo(insns))
		return err
	case "check":
		rawMap := map[string]string{}
		for _, r := range raw {
			p := format.Parse(r.Format)
			key := p.Mnemonic
			if len(p.Operands) > 0 {
				key += "\t" + strings.Join(p.Operands, ",")
			}
			rawMap[key] = r.Code
		}
		if errs := oracle.CheckAll(insns, rawMap); len(errs) > 0 {
			return errors.Join(errs...)
		}
		fmt.Fprintf(w, "ok: %d instructions round-trip\n", len(insns))
		return nil
	default:
		return fmt.Errorf("unknown -emit %q", *emit)
	}
}
