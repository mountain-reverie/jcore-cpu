// Package emit renders model.Decoder into the generator's output files
// using text/template. Helpers in funcMap format values; they do not
// derive new ones. Anything that requires computation belongs in
// model.Build.
package emit

import (
	"embed"
	"fmt"
	"os"
	"path/filepath"
	"text/template"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/model"
)

//go:embed tmpl/*.tmpl tmpl/partials/*.tmpl
var tmplFS embed.FS

// outputs lists every (file, template) pair the generator emits.
// Add entries as later milestones bring up more templates.
var outputs = []struct {
	file string
	tmpl string
}{
	{"sh2instr.c", "sh2instr.c.tmpl"},
	{"decode_pkg.vhd", "decode_pkg.vhd.tmpl"},
	{"decode_table_rom.vhd", "decode_table_rom.vhd.tmpl"},
	{"decode_body.vhd", "decode_body.vhd.tmpl"},
	{"decode_table_simple.vhd", "decode_table_simple.vhd.tmpl"},
	{"decode_table_direct.vhd", "decode_table_direct.vhd.tmpl"},
	{"decode.vhd", "decode.vhd.tmpl"},
}

// All renders every registered template against d, writing one output
// file per entry into outDir.
func All(d *model.Decoder, outDir string) error {
	tmpl, err := newTemplates()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return err
	}
	for _, o := range outputs {
		path := filepath.Join(outDir, o.file)
		f, err := os.Create(path)
		if err != nil {
			return fmt.Errorf("%s: %w", o.file, err)
		}
		if err := tmpl.ExecuteTemplate(f, o.tmpl, d); err != nil {
			f.Close()
			return fmt.Errorf("%s: %w", o.file, err)
		}
		if err := f.Close(); err != nil {
			return fmt.Errorf("%s: %w", o.file, err)
		}
	}
	return nil
}

func newTemplates() (*template.Template, error) {
	return template.New("").Funcs(funcMap).ParseFS(tmplFS, "tmpl/*.tmpl", "tmpl/partials/*.tmpl")
}

// CopyStatic copies every regular *.vhd file from srcDir to outDir
// verbatim. Used for hand-written config wiring files (rom_config,
// simple_config, direct_config) that cpugen ships alongside its
// generated output but does not produce.
func CopyStatic(srcDir, outDir string) error {
	entries, err := os.ReadDir(srcDir)
	if err != nil {
		return fmt.Errorf("read %s: %w", srcDir, err)
	}
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return err
	}
	for _, e := range entries {
		// Skip anything that isn't a regular file (directories, symlinks,
		// sockets, etc.). The .vhd extension filter further narrows this.
		if !e.Type().IsRegular() || filepath.Ext(e.Name()) != ".vhd" {
			continue
		}
		src := filepath.Join(srcDir, e.Name())
		dst := filepath.Join(outDir, e.Name())
		b, err := os.ReadFile(src)
		if err != nil {
			return fmt.Errorf("read %s: %w", src, err)
		}
		if err := os.WriteFile(dst, b, 0o644); err != nil {
			return fmt.Errorf("write %s: %w", dst, err)
		}
	}
	return nil
}
