package emit

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNormalizeForDiff(t *testing.T) {
	tests := []struct {
		name     string
		filename string
		input    string
		want     string
	}{
		{
			name:     "GeneratedAtHeaderRemoved",
			filename: "out.vhd",
			input:    "-- Generated at 2024-01-15T10:30:00Z\nsignal foo : std_logic;\n",
			want:     "signal foo : std_logic;\n",
		},
		{
			name:     "TrailingWhitespaceStripped",
			filename: "out.vhd",
			input:    " foo   \t\n",
			want:     " foo\n",
		},
		{
			name:     "BlankLinesRemoved",
			filename: "out.vhd",
			input:    "line one\n\nline two\n",
			want:     "line one\nline two\n",
		},
		{
			name:     "WhitespaceOnlyLineRemoved",
			filename: "out.vhd",
			input:    "line one\n   \t  \nline two\n",
			want:     "line one\nline two\n",
		},
		{
			name:     "VhdlCommentOnlyLineRemoved",
			filename: "out.vhd",
			input:    "signal a : std_logic;\n   --   \nsignal b : std_logic;\n",
			want:     "signal a : std_logic;\nsignal b : std_logic;\n",
		},
		{
			name:     "CCommentOnlyLineRemoved",
			filename: "out.c",
			input:    "int x;\n//\nint y;\n",
			want:     "int x;\nint y;\n",
		},
		{
			name:     "RealCommentPreserved",
			filename: "out.c",
			input:    "// some real comment\n",
			want:     "// some real comment\n",
		},
		{
			name:     "VhdlRealCommentPreserved",
			filename: "out.vhd",
			input:    "-- this is a meaningful comment\n",
			want:     "-- this is a meaningful comment\n",
		},
		{
			name:     "PlainSignalPreserved",
			filename: "out.vhd",
			input:    "signal foo : std_logic;\n",
			want:     "signal foo : std_logic;\n",
		},
		{
			name:     "MultipleTransformations",
			filename: "out.vhd",
			input: "-- Generated at 2024-03-01T00:00:00Z\n" +
				"-- \n" +
				"signal foo : std_logic;   \n" +
				"\n" +
				"-- a real comment\n" +
				"//\n",
			want: "signal foo : std_logic;\n" +
				"-- a real comment\n",
		},
		{
			name:     "CommentOnlyLineNoSpaces",
			filename: "out.vhd",
			input:    "--\n",
			want:     "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			srcDir := t.TempDir()
			dstDir := t.TempDir()

			srcPath := filepath.Join(srcDir, tc.filename)
			if err := os.WriteFile(srcPath, []byte(tc.input), 0o644); err != nil {
				t.Fatalf("write src: %v", err)
			}

			if err := NormalizeForDiff(srcDir, dstDir); err != nil {
				t.Fatalf("NormalizeForDiff: %v", err)
			}

			dstPath := filepath.Join(dstDir, tc.filename)
			got, err := os.ReadFile(dstPath)
			if err != nil {
				t.Fatalf("read dst: %v", err)
			}
			if string(got) != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

func TestNormalizeForDiff_EmptySrcDir(t *testing.T) {
	srcDir := t.TempDir()
	dstDir := t.TempDir()

	if err := NormalizeForDiff(srcDir, dstDir); err != nil {
		t.Fatalf("NormalizeForDiff: %v", err)
	}

	entries, err := os.ReadDir(dstDir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 0 {
		names := make([]string, len(entries))
		for i, e := range entries {
			names[i] = e.Name()
		}
		t.Errorf("expected empty dstDir, got: %s", strings.Join(names, ", "))
	}
}

func TestNormalizeForDiff_NonVhdCFilesIgnored(t *testing.T) {
	srcDir := t.TempDir()
	dstDir := t.TempDir()

	// Write a .txt file; it must not appear in dstDir.
	if err := os.WriteFile(filepath.Join(srcDir, "notes.txt"), []byte("ignored\n"), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}
	// Write a .vhd file so we know the function ran.
	if err := os.WriteFile(filepath.Join(srcDir, "real.vhd"), []byte("signal x : bit;\n"), 0o644); err != nil {
		t.Fatalf("write: %v", err)
	}

	if err := NormalizeForDiff(srcDir, dstDir); err != nil {
		t.Fatalf("NormalizeForDiff: %v", err)
	}

	entries, err := os.ReadDir(dstDir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 1 || entries[0].Name() != "real.vhd" {
		names := make([]string, len(entries))
		for i, e := range entries {
			names[i] = e.Name()
		}
		t.Errorf("expected only real.vhd in dst, got: %s", strings.Join(names, ", "))
	}
}
