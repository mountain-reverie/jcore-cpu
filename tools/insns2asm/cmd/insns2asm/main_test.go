package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
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

func TestRunExcludesDSPCoproc(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "insns.json")
	data := `{"instructions":[
	  {"group":"System Control Instructions","format":"ldc\tRm,SR","code":"0100mmmm00001110","SH1":true},
	  {"group":"System Control Instructions","format":"lds\tRm,DSR","code":"0100mmmm01101010","DSP":true}
	]}`
	if err := os.WriteFile(p, []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	if err := run([]string{"-in", p, "-emit", "check"}, &out); err != nil {
		t.Fatalf("check should pass: %v", err)
	}
	if !bytes.Contains(out.Bytes(), []byte("ok: 1 instructions round-trip")) {
		t.Errorf("expected 1 kept insn (ldc Rm,SR), got:\n%s", out.String())
	}
}

func TestRunOnlyFilter(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "insns.json")
	data := `{"instructions":[
	  {"group":"Data Transfer Instructions","format":"mov\tRm,Rn","code":"0110nnnnmmmm0011","J2":true},
	  {"group":"Data Transfer Instructions","format":"add\tRm,Rn","code":"0011nnnnmmmm1100","J2":true}
	]}`
	if err := os.WriteFile(p, []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	if err := run([]string{"-in", p, "-emit", "llvm", "-only", "mov"}, &out); err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(out.Bytes(), []byte("def MOV_")) {
		t.Errorf("expected MOV def:\n%s", out.String())
	}
	if bytes.Contains(out.Bytes(), []byte("def ADD_")) {
		t.Errorf("ADD should be filtered out by -only mov:\n%s", out.String())
	}
}

func TestRunEmitCases(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "insns.json")
	data := `{"instructions":[{"group":"Data Transfer Instructions","format":"mov\tRm,Rn","code":"0110nnnnmmmm0011","SH1":true}]}`
	if err := os.WriteFile(p, []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	if err := run([]string{"-in", p, "-emit", "cases", "-class", "simple"}, &out); err != nil {
		t.Fatal(err)
	}
	lines := strings.Count(strings.TrimSpace(out.String()), "\n") + 1
	if lines != 16 {
		t.Errorf("want 16 case lines, got %d:\n%s", lines, out.String())
	}
	if !strings.Contains(out.String(), "\t") {
		t.Errorf("each line should be asm<TAB>hex:\n%s", out.String())
	}
}

func TestRunClassSimpleFilter(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "insns.json")
	data := `{"instructions":[
	  {"group":"Data Transfer Instructions","format":"mov\tRm,Rn","code":"0110nnnnmmmm0011","SH1":true},
	  {"group":"Data Transfer Instructions","format":"mov.l\t@(disp,Rm),Rn","code":"0101nnnnmmmmdddd","SH1":true},
	  {"group":"Data Transfer Instructions","format":"movi20\t#imm20,Rn","code":"0000nnnniiii0000 iiiiiiiiiiiiiiii","SH2A":true}
	]}`
	if err := os.WriteFile(p, []byte(data), 0o644); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	if err := run([]string{"-in", p, "-emit", "llvm", "-class", "simple"}, &out); err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(out.Bytes(), []byte("def MOV_GPR_GPR")) {
		t.Errorf("mov should be emitted:\n%s", out.String())
	}
	if !bytes.Contains(out.Bytes(), []byte("memdisp_l4")) {
		t.Errorf("memdisp_l4 class should be emitted:\n%s", out.String())
	}
	if bytes.Contains(out.Bytes(), []byte("MOVI20")) {
		t.Errorf("two-word movi20 should be filtered out:\n%s", out.String())
	}
}
