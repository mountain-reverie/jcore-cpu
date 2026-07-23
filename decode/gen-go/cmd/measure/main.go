// Command measure orchestrates build/run/emit of per-instruction latency
// microbenchmarks against a J-Core cosim build, producing a
// timing/<variant>.measured.toml table.
//
// For -variant J1 no cosim is run at all (Finding B: J1's seq shifter/mult
// aren't present in any cosim config): the tool writes a hand-value table
// straight from the recipes' non-measurable entries.
//
// For J2/J2A/J4 it generates a microbenchmark .S per instruction (via
// measure.Gen), assembles+links+objcopies it to a raw image, runs it against
// the cosim binary (measure.RunOne), parses the LED markers it emits
// (measure.ParseMarkers), and computes issue/latency (measure.NSPerCycle +
// measure.Measure). A calibration gate — nop/add both == 1 cycle within
// tolerance, using the two-bracket difference method — must pass before any
// output file is written; the gate deliberately does NOT anchor on
// multi-cycle hand values (mul.l/tas/divs), which the Task-1 spike proved
// wrong for at least mul.l.
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/insns"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/measure"
	"github.com/j-core/jcore-cpu/decode/gen-go/internal/spec"
)

const ledAddr = 0xABCD0000

// normOpcode mirrors internal/insns.normOpcode (unexported there): strip
// spaces so a spec.Instr.Opcode string can be compared/keyed the same way
// recipes/subset opcodes are.
func normOpcode(s string) string {
	return strings.ReplaceAll(s, " ", "")
}

func main() {
	variant := flag.String("variant", "", "J2|J2A|J4|J1")
	recipesPath := flag.String("recipes", "measure/recipes.toml", "path to recipes TOML")
	specDir := flag.String("spec", "spec", "path to spec directory")
	out := flag.String("out", "", "output .measured.toml path (required)")
	count := flag.Int("count", 100, "op-chain length per bracket (>=100 recommended)")
	subset := flag.String("subset", "all", "comma-separated opcode patterns, or \"all\"")
	cosimBin := flag.String("cosim", "sim/cpu_ctb", "path to cpu_ctb cosim binary")
	simDir := flag.String("simdir", "sim", "sim/ directory (assemble+run cwd)")
	flag.Parse()

	if *variant == "" || *out == "" {
		fmt.Fprintln(os.Stderr, "usage: measure -variant J2|J2A|J4|J1 -out path [-recipes path] [-spec dir] [-count n] [-subset all|op,op,...]")
		os.Exit(2)
	}

	v, ok := lookupVariant(*variant)
	if !ok {
		log.Fatalf("unknown -variant %q (want J2, J2A, J4, or J1)", *variant)
	}

	recipes, err := measure.LoadRecipes(*recipesPath)
	if err != nil {
		log.Fatalf("load recipes: %v", err)
	}

	set, err := insns.LoadVariant(*specDir, v)
	if err != nil {
		log.Fatalf("load spec for %s: %v", *variant, err)
	}

	want := subsetSet(*subset)

	if *variant == "J1" {
		results := handTableJ1(set, recipes, want)
		if err := os.MkdirAll(filepath.Dir(*out), 0o755); err != nil && filepath.Dir(*out) != "." {
			log.Fatalf("mkdir %s: %v", filepath.Dir(*out), err)
		}
		if err := os.WriteFile(*out, []byte(measure.EmitTable(results)), 0o644); err != nil {
			log.Fatalf("write %s: %v", *out, err)
		}
		log.Printf("J1: wrote %d hand entries to %s (no cosim run)", len(results), *out)
		return
	}

	results, measuredN, skippedN, err := runMeasured(set, recipes, want, *count, *simDir, *cosimBin)
	if err != nil {
		log.Fatalf("%v", err)
	}
	log.Printf("%s: measured=%d skipped(hand)=%d", *variant, measuredN, skippedN)

	if err := os.MkdirAll(filepath.Dir(*out), 0o755); err != nil && filepath.Dir(*out) != "." {
		log.Fatalf("mkdir %s: %v", filepath.Dir(*out), err)
	}
	if err := os.WriteFile(*out, []byte(measure.EmitTable(results)), 0o644); err != nil {
		log.Fatalf("write %s: %v", *out, err)
	}
	log.Printf("wrote %s", *out)
}

func lookupVariant(name string) (insns.Variant, bool) {
	for _, v := range insns.Variants() {
		if v.Name == name {
			return v, true
		}
	}
	return insns.Variant{}, false
}

// subsetSet parses -subset into a lookup set of normalized opcodes, or nil
// meaning "all".
func subsetSet(subset string) map[string]bool {
	if subset == "" || subset == "all" {
		return nil
	}
	out := map[string]bool{}
	for _, s := range strings.Split(subset, ",") {
		s = strings.TrimSpace(s)
		if s == "" {
			continue
		}
		out[normOpcode(s)] = true
	}
	return out
}

func included(want map[string]bool, code string) bool {
	if want == nil {
		return true
	}
	return want[code]
}

// handTableJ1 builds a Result set entirely from the recipes' hand-entered
// (non-measurable) values -- J1's seq shifter/mult aren't present in any
// cosim config, so J1 is never actually run.
func handTableJ1(set *insns.InstrSet, recipes *measure.Recipes, want map[string]bool) []measure.Result {
	var results []measure.Result
	for _, in := range set.Order {
		code := normOpcode(in.Opcode)
		if !included(want, code) {
			continue
		}
		rec := recipes.For(code)
		results = append(results, measure.Result{
			Opcode:  code,
			Issue:   float64(rec.Issue),
			Latency: float64(rec.Latency),
			Source:  "hand",
		})
	}
	return results
}

// calibration knowns: only add/nop are trustworthy per Finding A.
var calKnown = map[string]float64{
	"add": 1.0,
	"nop": 1.0,
}

func runMeasured(set *insns.InstrSet, recipes *measure.Recipes, want map[string]bool, count int, simDir, cosimBin string) (results []measure.Result, measuredN, skippedN int, err error) {
	tmp, err := os.MkdirTemp("", "measure-*")
	if err != nil {
		return nil, 0, 0, fmt.Errorf("mkdtemp: %w", err)
	}
	defer os.RemoveAll(tmp)

	type measured struct {
		code    string
		mnemVal string
		issue   float64
		latency float64
	}
	var raw []measured
	calMeasured := map[string]float64{}

	for _, in := range set.Order {
		code := normOpcode(in.Opcode)
		if !included(want, code) {
			continue
		}
		rec := recipes.For(code)
		if !rec.Measurable && rec.Why != "" {
			results = append(results, measure.Result{
				Opcode:  code,
				Issue:   float64(rec.Issue),
				Latency: float64(rec.Latency),
				Source:  "hand",
			})
			skippedN++
			continue
		}

		src, err := measure.Gen(in, rec, count, ledAddr)
		if err != nil {
			return nil, 0, 0, fmt.Errorf("gen %s (%s): %w", in.Name, code, err)
		}
		if src == "" {
			// sentinel: hand entry despite falling through (shouldn't
			// normally happen given the check above, but stay defensive).
			results = append(results, measure.Result{
				Opcode:  code,
				Issue:   float64(rec.Issue),
				Latency: float64(rec.Latency),
				Source:  "hand",
			})
			skippedN++
			continue
		}

		trace, err := assembleAndRun(src, code, tmp, simDir, cosimBin)
		if err != nil {
			return nil, 0, 0, fmt.Errorf("assemble/run %s (%s): %w", in.Name, code, err)
		}

		m := measure.ParseMarkers(trace)
		ns, err := measure.NSPerCycle(m, 100, 200)
		if err != nil {
			return nil, 0, 0, fmt.Errorf("nsPerCycle %s (%s): %w", in.Name, code, err)
		}
		iss, lat, err := measure.Measure(m, ns, count, 2)
		if err != nil {
			return nil, 0, 0, fmt.Errorf("measure %s (%s): %w", in.Name, code, err)
		}

		mn := mnemonicOf(in)
		if mn == "add" || mn == "nop" {
			calMeasured[mn] = iss
		}
		raw = append(raw, measured{code: code, mnemVal: mn, issue: iss, latency: lat})
		measuredN++
	}

	// Calibration gate: only gate on add/nop==1, never on multi-cycle hand
	// values (Finding A). If either wasn't in the subset, we can't gate --
	// treat as a hard failure rather than silently skipping the gate, since
	// the whole point of the gate is to catch a broken measurement pipeline.
	if err := measure.CalibrationOK(calKnown, calMeasured, 0.2); err != nil {
		return nil, measuredN, skippedN, fmt.Errorf("calibration gate failed: %w", err)
	}

	for _, r := range raw {
		results = append(results, measure.Result{
			Opcode:  r.code,
			Issue:   r.issue,
			Latency: r.latency,
			Source:  "measured",
		})
	}
	return results, measuredN, skippedN, nil
}

func mnemonicOf(in spec.Instr) string {
	name := strings.TrimSpace(in.Name)
	if i := strings.IndexAny(name, " \t"); i >= 0 {
		name = name[:i]
	}
	return strings.ToLower(name)
}

// assembleAndRun writes src to a .S under tmp, assembles/links/objcopies it
// to a raw .img (the sim/tests %.elf Makefile rule can't be reused here --
// it depends on $^ being non-empty for a single explicit source, which it
// isn't for a generated one-off), then runs it against cosimBin from simDir
// and returns the captured trace text.
func assembleAndRun(src, code, tmp, simDir, cosimBin string) (string, error) {
	base := filepath.Join(tmp, sanitizeForFilename(code))
	sPath := base + ".S"
	oPath := base + ".o"
	elfPath := base + ".elf"
	imgPath := base + ".img"

	if err := os.WriteFile(sPath, []byte(src), 0o644); err != nil {
		return "", fmt.Errorf("write %s: %w", sPath, err)
	}

	testsDir := filepath.Join(simDir, "tests")
	linkerScript := filepath.Join(testsDir, "sh32.x")

	if out, err := run(testsDir, "sh2-elf-gcc", "-Os", "-I.", "-c", sPath, "-o", oPath); err != nil {
		return "", fmt.Errorf("gcc: %w\n%s", err, out)
	}

	libgcc, err := runCapture(testsDir, "sh2-elf-gcc", "-print-file-name=libgcc.a")
	if err != nil {
		return "", fmt.Errorf("gcc -print-file-name: %w", err)
	}
	libgcc = strings.TrimSpace(libgcc)

	if out, err := run(testsDir, "sh2-elf-ld", "-T", linkerScript, oPath, libgcc, "-o", elfPath); err != nil {
		return "", fmt.Errorf("ld: %w\n%s", err, out)
	}

	if out, err := run(testsDir, "sh2-elf-objcopy", "-S", "-O", "binary", elfPath, imgPath); err != nil {
		return "", fmt.Errorf("objcopy: %w\n%s", err, out)
	}

	absImg, err := filepath.Abs(imgPath)
	if err != nil {
		return "", err
	}
	absCosim, err := filepath.Abs(cosimBin)
	if err != nil {
		return "", err
	}
	return measure.RunOne(absImg, absCosim)
}

func sanitizeForFilename(code string) string {
	return strings.Map(func(r rune) rune {
		if r == '0' || r == '1' {
			return r
		}
		return '_'
	}, code)
}

func run(dir string, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func runCapture(dir string, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	out, err := cmd.Output()
	return string(out), err
}
