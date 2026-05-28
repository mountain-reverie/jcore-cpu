package emit

import (
	"bufio"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var (
	// generatedAtRE matches the "-- Generated at <timestamp>" header line
	// produced by the generator. Anchored at the start of the line to match
	// the sed -E pattern /^-- Generated at /d.
	generatedAtRE = regexp.MustCompile(`^-- Generated at `)

	// commentOnlyRE matches lines whose only non-whitespace content is "--"
	// or "//". These are noise-only separator lines emitted by the Clojure
	// generator; we drop them so they don't produce false diff hits.
	commentOnlyRE = regexp.MustCompile(`^[[:space:]]*(--|//)[[:space:]]*$`)
)

// NormalizeForDiff reads every *.vhd and *.c file in srcDir and writes a
// normalized copy to dstDir. The normalized form strips:
//   - "-- Generated at <timestamp>" header lines
//   - trailing whitespace on each line
//   - blank lines
//   - lines whose only non-whitespace content is "--" or "//"
//
// Used by the L1 best-effort diff against the Clojure golden output:
// timestamps and whitespace-only differences are noise, not signal.
//
// Both dirs are created if missing. Existing files in dstDir are
// overwritten. Files outside *.vhd/*.c are ignored.
func NormalizeForDiff(srcDir, dstDir string) error {
	if err := os.MkdirAll(dstDir, 0o755); err != nil {
		return err
	}

	patterns := []string{
		filepath.Join(srcDir, "*.vhd"),
		filepath.Join(srcDir, "*.c"),
	}

	for _, pattern := range patterns {
		matches, err := filepath.Glob(pattern)
		if err != nil {
			return err
		}
		for _, src := range matches {
			dst := filepath.Join(dstDir, filepath.Base(src))
			if err := normalizeFile(src, dst); err != nil {
				return err
			}
		}
	}
	return nil
}

// normalizeFile applies the normalization transformations to a single file.
func normalizeFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()

	w := bufio.NewWriter(out)
	// Default 64 KB line buffer is adequate for all currently-generated files.
	// If a future template ever emits a single line longer than that,
	// scanner.Err() returns bufio.ErrTooLong (loud failure, not silent
	// truncation) and the buffer can be enlarged via scanner.Buffer().
	scanner := bufio.NewScanner(in)
	for scanner.Scan() {
		line := scanner.Text()

		// Drop "-- Generated at <timestamp>" header lines.
		if generatedAtRE.MatchString(line) {
			continue
		}

		// Strip trailing whitespace (space and tab, matching [[:space:]]+ in sed
		// where the sed pattern only strips horizontal trailing whitespace; sed's
		// [[:space:]] on a line already split by newline matches \t and space).
		line = strings.TrimRight(line, " \t")

		// Drop blank lines (including lines that were only whitespace).
		if line == "" {
			continue
		}

		// Drop comment-only lines ("--" or "//" with optional surrounding whitespace).
		if commentOnlyRE.MatchString(line) {
			continue
		}

		w.WriteString(line)
		w.WriteByte('\n')
	}
	if err := scanner.Err(); err != nil {
		return err
	}
	return w.Flush()
}
