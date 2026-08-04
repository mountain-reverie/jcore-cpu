package main

import (
	"strings"
	"testing"
)

func TestEmitMake(t *testing.T) {
	got, err := emitMakeFragment("../../../../variants.toml")
	if err != nil {
		t.Fatalf("emitMakeFragment: %v", err)
	}
	for _, want := range []string{
		"CPU_VARIANT_ALL := j1 j2 j2a j4",
		"CPU_VARIANT_j4_GENERICS := PRIV_ARCH=true",
		"CPU_VARIANT_j4_OVERLAY := sh4",
		"CPU_VARIANT_j4_EXTRA_FILES := core/tlb.vhd",
		"CPU_VARIANT_j4_CONFIG_FILE := core/cpu_config.vhd",
		"CPU_VARIANT_j2_OVERLAY :=",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("fragment missing %q\ngot:\n%s", want, got)
		}
	}
	if strings.Contains(got, "MMU_ARCH") {
		t.Error("fragment must not mention MMU_ARCH")
	}
}
