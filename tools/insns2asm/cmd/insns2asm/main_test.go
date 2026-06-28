package main

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func writeSample(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	p := filepath.Join(dir, "insns.json")
	data := `{"instructions":[
	  {"group":"Data Transfer Instructions","format":"mov\tRm,Rn","code":"0110nnnnmmmm0011","SH1":true,"J2":true},
	  {"group":"Data Transfer Instructions","format":"movi20\t#imm20,Rn","code":"0000nnnniiii0000 iiiiiiiiiiiiiiii","J2":true}
	]}`
	if err := os.WriteFile(p, []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestRunLLVM(t *testing.T) {
	var out bytes.Buffer
	if err := run([]string{"-in", writeSample(t), "-emit", "llvm"}, &out); err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(out.Bytes(), []byte("def MOV_")) {
		t.Errorf("llvm output missing def:\n%s", out.String())
	}
}

func TestRunGAS(t *testing.T) {
	var out bytes.Buffer
	if err := run([]string{"-in", writeSample(t), "-emit", "gas"}, &out); err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(out.Bytes(), []byte(`"movi20"`)) {
		t.Errorf("gas delta missing movi20:\n%s", out.String())
	}
}

func TestRunCheckPasses(t *testing.T) {
	var out bytes.Buffer
	if err := run([]string{"-in", writeSample(t), "-emit", "check"}, &out); err != nil {
		t.Fatalf("check should pass: %v", err)
	}
}
