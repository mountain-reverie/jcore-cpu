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

// IsSharedJ4Augment reports an instruction that already exists upstream on an
// SH variant (so it is NOT emitted as a gas delta line) but is ALSO
// implemented on J4 (e.g. the reg-reg forms ldc Rm,SSR / stc SSR,Rn shared
// with SH-3/SH-4/SH-4A). Its upstream sh-opc.h arch mask needs augmenting
// with arch_j4_up so the instruction is recognized under the J4 gas target.
//
// The base SH ISA (mov, add, cmp/eq, ...) is tagged SH1+J4 (it runs on every
// SH generation AND on J4) — that is NOT what this reports: those already
// carry the lowest SH arch ("arch_sh_up"/"arch_sh1_up"/"arch_sh2_up"), which
// already dominates arch_j4_up, so augmenting them would be a no-op at best
// and scope creep at worst. What genuinely needs augmenting is any J4
// instruction whose lowest matching SH tag sits ABOVE the SH1/SH2 base line
// (e.g. the SH-3-and-later privileged-mode reg-reg forms SSR/SPC/Rn_BANK,
// but also shared insns like shld/shad tagged SH2A+SH3+SH4+SH4A): those are
// NOT already covered by arch_j4_up's baked-in arch_sh2_up, so gas rejects
// them under the j4 target unless augmented.
func (s Set) IsSharedJ4Augment() bool {
	return s.J4 && s.anySH() && !s.SH1 && !s.SH2
}

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
	case s.J2, s.J1:
		// Shared J-core base ISA: valid on both the J2 and J4 gas
		// targets (e.g. cas.l). arch_j2_up == arch_j2 | arch_j4_up in
		// sh-opc.h, so this is the "lowest" j-core mask, matching the
		// SH "_up" convention above. J1 has no known J1-only insns
		// today (verified against insns.json); fold it in here so a
		// J1 flag never silently regresses to no arch tag.
		return "arch_j2_up"
	case s.J4:
		// J4-only extension (MMU/privileged-mode insns, e.g.
		// ldtlb.rn): valid on the J4 gas target only, NOT J2.
		return "arch_j4_up"
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
