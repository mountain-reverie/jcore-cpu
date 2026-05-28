package emit

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCopyStatic(t *testing.T) {
	out := t.TempDir()
	if err := CopyStatic("../../spec/static", out); err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"decode_table_rom_config.vhd",
		"decode_table_simple_config.vhd",
		"decode_table_direct_config.vhd",
	} {
		path := filepath.Join(out, want)
		if _, err := os.Stat(path); err != nil {
			t.Errorf("missing %s: %v", want, err)
		}
	}
}
