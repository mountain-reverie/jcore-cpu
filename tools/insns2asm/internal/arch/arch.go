// Package arch maps insns.json per-architecture flags to gas arch masks and
// LLVM TableGen predicate names.
package arch

// Set is the architecture availability of one instruction.
type Set struct {
	SH1, SH2, SH2E, SH3, SH3E, SH4, SH4A, SH2A bool
	J1, J2, J4                                  bool
}

func (s Set) anySH() bool {
	return s.SH1 || s.SH2 || s.SH2E || s.SH3 || s.SH3E || s.SH4 || s.SH4A || s.SH2A
}

func (s Set) anyJ() bool { return s.J1 || s.J2 || s.J4 }

// IsJCoreOnly reports an instruction present on J-core but on no SH variant.
func (s Set) IsJCoreOnly() bool { return s.anyJ() && !s.anySH() }

// GASMask returns the upstream-style arch mask for the lowest-numbered SH that
// has the instruction (SH "_up" inclusive masks). J-core-only uses a placeholder.
func (s Set) GASMask() string {
	switch {
	case s.SH1:
		return "arch_sh1_up"
	case s.SH2:
		return "arch_sh2_up"
	case s.SH2E:
		return "arch_sh2e_up"
	case s.SH3:
		return "arch_sh3_up"
	case s.SH3E:
		return "arch_sh3e_up"
	case s.SH2A:
		return "arch_sh2a_nofpu_up"
	case s.SH4:
		return "arch_sh4_up"
	case s.SH4A:
		return "arch_sh4a_up"
	case s.anyJ():
		return "arch_j_core"
	}
	return "arch_sh1_up"
}

// LLVMPredicates returns TableGen predicate names gating the instruction.
func (s Set) LLVMPredicates() []string {
	switch {
	case s.SH1:
		return []string{"HasSH1"}
	case s.SH2:
		return []string{"HasSH2"}
	case s.SH2E:
		return []string{"HasSH2E"}
	case s.SH3:
		return []string{"HasSH3"}
	case s.SH3E:
		return []string{"HasSH3E"}
	case s.SH2A:
		return []string{"HasSH2A"}
	case s.SH4:
		return []string{"HasSH4"}
	case s.SH4A:
		return []string{"HasSH4A"}
	case s.J2:
		return []string{"HasJ2"}
	case s.J1:
		return []string{"HasJ1"}
	case s.J4:
		return []string{"HasJ4"}
	}
	return []string{"HasSH1"}
}
