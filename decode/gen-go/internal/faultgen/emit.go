package faultgen

// emit.go -- the M8 fault-harness emitter. Turns each classified instruction
// into an assembly self-check block that plugs into the static runtime
// (sim/tests/m8_runtime.inc, see its CONTRACT header). EmitCase produces one
// `_m8_case_<id>:` routine plus its dispatch-table entry; EmitImage stitches a
// slice of same-bucket/axis cases into a complete `.S` with `_m8_run_all`.
//
// RANGE SAFETY: the batched image is large, so every case<->helper and
// run_all<->case call goes through a P1-aliased ABSOLUTE address loaded from a
// nearby literal and reached with `jsr @rN` -- never `bsr` (PC-relative, only
// +/-4KB). `_m8_run_all` walks an address TABLE with `mov.l @rN+` (no range
// limit at all) instead of emitting one PC-relative call per case.

import (
	"errors"
	"fmt"
	"strings"
	"text/template"

	"github.com/j-core/jcore-cpu/decode/gen-go/internal/opcode"
)

// Axis selects the fault axis a batch of cases exercises.
type Axis int

const (
	DSide  Axis = iota // data-side load/store faults (DMISS_R / DMISS_W)
	IFetch             // instruction-fetch faults (IMISS at vector +0x400)
)

// Fixed workload page (see runtime header): VA 0x00100000 identity-mapped.
const (
	workloadVA = 0x00100000
	regBase    = 0 // chosen GPR for the memory base / "m" operand
	regOther   = 8 // chosen GPR for the dest / "n" operand
)

// errSkip marks a case the emitter deliberately does not generate (Bespoke, an
// unrepresentable control register, or a memory instruction on the I-fetch
// axis). EmitImage records these in a manifest comment rather than a table
// entry. The returned `block` carries the human-readable reason.
var errSkip = errors.New("faultgen: case skipped")

// IsSkip reports whether err is the emitter's deliberate-skip sentinel.
func IsSkip(err error) bool { return errors.Is(err, errSkip) }

// ---------------------------------------------------------------------------
// Opcode -> .word with concrete registers substituted.
// ---------------------------------------------------------------------------

// fieldShift returns the bit-shift of the nibble holding pattern field `ch`
// ('n','m','d',...). Nibble group g (0=leftmost) occupies bits [15-4g..12-4g],
// so its low bit (shift) is 12-4g. ok is false if the field is absent.
func fieldShift(pattern string, ch byte) (shift uint, ok bool) {
	s := strings.ReplaceAll(strings.TrimSpace(pattern), " ", "")
	if len(s) != 16 {
		return 0, false
	}
	for g := 0; g < 4; g++ {
		if s[g*4] == ch {
			return uint(12 - 4*g), true
		}
	}
	return 0, false
}

// addrFieldChar returns the pattern field ('m' or 'n') that holds the memory
// pointer, derived from the instruction Name: the first Rm/Rn that appears
// after the first '@'. Returns 0 if the name has no @-operand.
func addrFieldChar(name string) byte {
	at := strings.IndexByte(name, '@')
	if at < 0 {
		return 0
	}
	rest := name[at:]
	im := strings.Index(rest, "Rm")
	in := strings.Index(rest, "Rn")
	switch {
	case im >= 0 && (in < 0 || im < in):
		return 'm'
	case in >= 0:
		return 'n'
	}
	return 0
}

// encodeWord assembles the instruction's 16-bit encoding with the base/pointer
// operand forced to regBase (r0) and the other operand to regOther (r8). For a
// non-memory instruction the 'm' field is regBase and 'n' is regOther.
func encodeWord(c Class) (uint16, error) {
	match, _, err := opcode.Parse(c.Instr.Opcode)
	if err != nil {
		return 0, fmt.Errorf("%s: %w", c.Instr.Name, err)
	}
	word := match

	ptr := byte(0)
	if c.Mem != NoMem {
		ptr = addrFieldChar(c.Instr.Name)
	}

	set := func(ch byte, reg uint16) {
		if sh, ok := fieldShift(c.Instr.Opcode, ch); ok {
			word |= reg << sh
		}
	}

	if ptr != 0 {
		// pointer field -> regBase (0, no bits); other field -> regOther.
		other := byte('n')
		if ptr == 'n' {
			other = 'm'
		}
		set(ptr, regBase)
		set(other, regOther)
	} else {
		set('m', regBase)
		set('n', regOther)
	}
	return word, nil
}

// dispScale returns the displacement scale (1/2/4) of the memory-accessing
// slot, read from its alu_y field ("U"=*1, "U*2", "U*4").
func dispScale(c Class) int {
	for _, sl := range c.Instr.Slots {
		if sl["ma_op"] != "WRITE" && sl["ma_op"] != "READ" {
			continue
		}
		switch sl["alu_y"] {
		case "U*4":
			return 4
		case "U*2":
			return 2
		default:
			return 1
		}
	}
	return 1
}

// storeProbeAddr returns the effective address a store writes, so the snapshot
// can probe the actual written word. ok=false (with a human-readable reason for
// the image manifest) means the target cannot be modelled with the emitter's
// fixed register choice and the case must be skipped rather than emit a probe
// that neither leg writes (which would pass vacuously).
func storeProbeAddr(c Class, word uint16, va int) (addr int, reason string, ok bool) {
	switch c.Addr {
	case PreDec:
		// @-Rn: base seeded at VA+8, the store lands at VA+4 (BaseInit=VA+8).
		return va + 4, "", true
	case Plain, PostInc:
		// @Rn (and @Rn+ stores) write at the base before any auto-modify.
		return va, "", true
	case Disp:
		// Indexed @(R0,Rn): the implicit R0 operand is not modelled by the
		// base->r0 / other->r8 substitution (R0 is itself loaded with VA), so
		// the effective address is not probeable here.
		if strings.Contains(c.Instr.Name, "@(R0") {
			return 0, "store effective address not probeable: indexed @(R0,Rn) uses implicit R0 (=VA) not modelled by fixed register choice", false
		}
		// @(disp,Rn): EA = Rn + disp*scale. The disp nibble is the encoded
		// word's low 4 bits; scale comes from alu_y.
		off := int(word&0xF) * dispScale(c)
		if off < 0 || off > 12 {
			return 0, fmt.Sprintf("store effective address not probeable: @(disp,Rn) offset +%d outside seeded window [0,12]", off), false
		}
		return va + off, "", true
	default:
		return va, "", true
	}
}

// ---------------------------------------------------------------------------
// Control-register access (PrivMem bucket).
// ---------------------------------------------------------------------------

type ctrlAccess struct {
	store string // "%s" = GPR; reads the control reg into a GPR
	load  string // "%s" = GPR; writes a GPR into the control reg
	ok    bool
}

// exceptionCritical lists control registers the exception-delivery mechanism
// depends on; the fault harness cannot clobber them across a fault.
var exceptionCritical = map[string]bool{"SR": true, "VBR": true, "SSR": true, "SPC": true}

func ctrlFor(reg string) ctrlAccess {
	switch reg {
	case "PR":
		return ctrlAccess{"sts     pr, %s", "lds     %s, pr", true}
	case "MACH":
		return ctrlAccess{"sts     mach, %s", "lds     %s, mach", true}
	case "MACL":
		return ctrlAccess{"sts     macl, %s", "lds     %s, macl", true}
	case "GBR":
		return ctrlAccess{"stc     gbr, %s", "ldc     %s, gbr", true}
	case "VBR":
		return ctrlAccess{"stc     vbr, %s", "ldc     %s, vbr", true}
	case "SSR":
		return ctrlAccess{"stc     ssr, %s", "ldc     %s, ssr", true}
	case "SPC":
		return ctrlAccess{"stc     spc, %s", "ldc     %s, spc", true}
	}
	// SR (mode-unsafe), T, PC: not represented -> skip.
	return ctrlAccess{ok: false}
}

// ---------------------------------------------------------------------------
// Template data.
// ---------------------------------------------------------------------------

type caseData struct {
	ID       int
	Word     string // e.g. "0x6806"
	Name     string
	BaseInit string // VA loaded into the base reg before the run
	SeedVB   string // second base VA (MAC dual-pointer: Rn page); "" otherwise
	Probe    string // address probed for the written word (Write only)
	IsWrite  bool
	CtrlSave string // formatted store insn (ctrl -> r1)
	CtrlLoad string // formatted load insn  (r1 -> ctrl)
}

// EmitCase returns the assembly for one case routine (`block`) and its
// dispatch-table entry (`dispatch`). id is the stable numeric case ID. On a
// deliberate skip it returns errSkip with `block` holding the reason (use
// IsSkip to test).
func EmitCase(c Class, id int) (block string, dispatch string, err error) {
	return emitCase(c, id, DSide)
}

func emitCase(c Class, id int, axis Axis) (block string, dispatch string, err error) {
	if c.Bucket == Bespoke {
		return fmt.Sprintf("! case %d skipped: %s is Bespoke (dedicated guard)\n", id, c.Instr.Name),
			"", errSkip
	}

	switch axis {
	case IFetch:
		return emitIFetch(c, id)
	default:
		return emitDSide(c, id)
	}
}

// unmodelledBase reports whether the memory operand's effective address cannot
// be modelled by the emitter's fixed base->r0 / other->r8 register substitution.
// Two cases leak the access to an unmapped address (bus-exception hang):
//   - indexed @(R0,...): the implicit R0 index aliases the modelled base reg
//     (also forced to r0), so EA = R0 + base = 2*VA -- off the mapped page;
//   - GBR-/PC-relative @(disp,GBR)/@(disp,PC): the base is never seeded.
//
// Both legs would fault identically, but the fault is a *bus* error on an
// unbacked address, not the cold-TLB DMISS the harness intends -- so skip.
func unmodelledBase(name string) (reason string, bad bool) {
	at := strings.IndexByte(name, '@')
	if at < 0 {
		return "", false
	}
	mem := name[at:]
	switch {
	case strings.Count(name, "@") > 1:
		return "effective address not modelled: dual memory-pointer instruction (only one base register is seeded)", true
	case strings.Contains(mem, "@(R0,"):
		return "effective address not modelled: indexed @(R0,...) implicit R0 collides with the fixed base register (EA off the mapped page)", true
	case strings.Contains(mem, "GBR)"):
		return "effective address not modelled: GBR-relative base is not seeded by the fixed register choice", true
	case strings.Contains(mem, "PC)"):
		return "effective address not modelled: PC-relative base is not seeded by the fixed register choice", true
	}
	return "", false
}

func emitDSide(c Class, id int) (string, string, error) {
	if c.Mem == NoMem || !c.DFaults {
		return fmt.Sprintf("! case %d skipped: %s has no D-side memory access\n", id, c.Instr.Name),
			"", errSkip
	}
	// MAC.L/MAC.W @Rm+,@Rn+ are dual-pointer post-increments -- the highest-
	// value precise-exception targets (fault-on-second-operand with the first
	// base already auto-incremented). They need BOTH bases seeded+snapshotted,
	// so they bypass unmodelledBase's single-base rejection.
	if strings.HasPrefix(c.Instr.Name, "MAC.") {
		return emitMacD(c, id)
	}
	if reason, bad := unmodelledBase(c.Instr.Name); bad {
		return fmt.Sprintf("! case %d skipped: %s: %s\n", id, c.Instr.Name, reason),
			"", errSkip
	}
	// Control-register memory LOADS (LDC.L/LDS.L @Rm+,ctrl): the auto-modify
	// base GPR is the real precise-exception risk; the control reg is only the
	// data payload. The 'U'-hang (co-sim snapshotting an uninitialised ctrl reg)
	// is resolved by benign-initialising the dest ctrl reg before the case and
	// restoring it after -- see tmplPrivMemD. SR/VBR stay skipped (mode-unsafe).
	if strings.HasPrefix(c.Instr.Name, "LDC.L") || strings.HasPrefix(c.Instr.Name, "LDS.L") {
		return emitCtrlLoadD(c, id)
	}
	word, err := encodeWord(c)
	if err != nil {
		return "", "", err
	}

	base := fmt.Sprintf("0x%08X", workloadVA)
	probeAddr := workloadVA
	if c.Addr == PreDec {
		// Pre-decrement starts above the seeded region and writes/reads below.
		base = fmt.Sprintf("0x%08X", workloadVA+8)
	}
	// For stores the snapshot probe must read the word the store actually
	// writes (the effective address), not the base. A probe of an address that
	// neither leg touches makes SNAP_A==SNAP_B unconditionally -> a vacuously
	// passing oracle. Compute the effective address per store mode, or skip
	// honestly (with a manifest reason) when it cannot be modelled.
	if c.Mem == Write {
		pa, reason, ok := storeProbeAddr(c, word, workloadVA)
		if !ok {
			return fmt.Sprintf("! case %d skipped: %s: %s\n", id, c.Instr.Name, reason),
				"", errSkip
		}
		probeAddr = pa
	}
	probe := fmt.Sprintf("0x%08X", probeAddr)

	d := caseData{
		ID:       id,
		Word:     fmt.Sprintf("0x%04X", word),
		Name:     c.Instr.Name,
		BaseInit: base,
		Probe:    probe,
		IsWrite:  c.Mem == Write,
	}

	tmpl := tmplGeneralD
	if c.Bucket == PrivMem {
		// The PrivMem template zeroes DestCtrl per leg as a benign baseline.
		// That is fatal for the registers the exception-delivery mechanism
		// itself uses: zeroing VBR/SR/SSR/SPC means the cold-TLB fault vectors
		// to garbage instead of the handler (a hang), so skip those here.
		if exceptionCritical[c.DestCtrl] {
			return fmt.Sprintf("! case %d skipped: %s writes exception-critical control reg %q (cannot be clobbered across a fault)\n",
					id, c.Instr.Name, c.DestCtrl),
				"", errSkip
		}
		ca := ctrlFor(c.DestCtrl)
		if !ca.ok {
			return fmt.Sprintf("! case %d skipped: %s writes control reg %q (mode-unsafe / not representable)\n",
					id, c.Instr.Name, c.DestCtrl),
				"", errSkip
		}
		d.CtrlSave = fmt.Sprintf(ca.store, "r1")
		d.CtrlLoad = fmt.Sprintf(ca.load, "r1")
		tmpl = tmplPrivMemD
	}

	return render(tmpl, d)
}

// ctrlLoadDest returns the destination control register of an LDC.L/LDS.L
// post-increment load, parsed from the instruction name ("LDC.L @Rm+, GBR" ->
// "GBR").
func ctrlLoadDest(name string) string {
	i := strings.LastIndex(name, ",")
	if i < 0 {
		return ""
	}
	return strings.TrimSpace(name[i+1:])
}

// emitCtrlLoadD emits a control-register post-increment load (LDC.L/LDS.L
// @Rm+,ctrl). The dest ctrl reg is benign-initialised before the run (so the
// co-sim never snapshots 'U'), read back via the matching STC/STS for the
// snapshot, and restored to its baseline after the case. The snapshot captures
// {base GPR, ctrl value}; both legs are byte-identical save cold-vs-warm TLB.
func emitCtrlLoadD(c Class, id int) (string, string, error) {
	reg := ctrlLoadDest(c.Instr.Name)
	if exceptionCritical[reg] {
		return fmt.Sprintf("! case %d skipped: %s: mode-unsafe (SR/VBR govern execution/vectoring); the @Rm+ base auto-modify path is already covered by the GBR/MACH/MACL/PR siblings, so no precise-exception coverage is lost\n",
				id, c.Instr.Name),
			"", errSkip
	}
	ca := ctrlFor(reg)
	if !ca.ok {
		return fmt.Sprintf("! case %d skipped: %s: control reg %q not representable for snapshot/restore\n",
				id, c.Instr.Name, reg),
			"", errSkip
	}
	word, err := encodeWord(c)
	if err != nil {
		return "", "", err
	}
	d := caseData{
		ID:       id,
		Word:     fmt.Sprintf("0x%04X", word),
		Name:     c.Instr.Name,
		CtrlSave: fmt.Sprintf(ca.store, "r1"),
		CtrlLoad: fmt.Sprintf(ca.load, "r1"),
	}
	return render(tmplPrivMemD, d)
}

// emitMacD emits a MAC.L/MAC.W @Rm+,@Rn+ dual-pointer case. Rm->r0 seeded at
// page A (workloadVA), Rn->r8 seeded at page B (workloadVA+0x1000, a second
// mapped page added to the runtime) so the two operands fault on DISTINCT cold
// pages -- exercising fault-on-the-second-operand with the first base already
// auto-incremented. Snapshots {r0, r8, MACH, MACL}; MAC is cleared (clrmac)
// each leg so the accumulator start is identical. Both legs differ only in
// cold-vs-warm TLB.
func emitMacD(c Class, id int) (string, string, error) {
	word, err := encodeWord(c)
	if err != nil {
		return "", "", err
	}
	d := caseData{
		ID:       id,
		Word:     fmt.Sprintf("0x%04X", word),
		Name:     c.Instr.Name,
		BaseInit: fmt.Sprintf("0x%08X", workloadVA),        // page A (Rm)
		SeedVB:   fmt.Sprintf("0x%08X", workloadVA+0x1000), // page B (Rn)
	}
	return render(tmplMacD, d)
}

func emitIFetch(c Class, id int) (string, string, error) {
	if c.Bucket == Bespoke || !c.IFaults {
		return fmt.Sprintf("! case %d skipped: %s excluded from I-fetch axis\n", id, c.Instr.Name),
			"", errSkip
	}
	if c.Mem != NoMem {
		// One translated page only: code and data would alias. Emit nothing
		// and let Task 4 provide a second mapped page if needed.
		return fmt.Sprintf("! case %d skipped: %s accesses memory; I-fetch needs a separate code page (Task 4)\n",
				id, c.Instr.Name),
			"", errSkip
	}
	word, err := encodeWord(c)
	if err != nil {
		return "", "", err
	}
	d := caseData{
		ID:   id,
		Word: fmt.Sprintf("0x%04X", word),
		Name: c.Instr.Name,
	}
	return render(tmplIFetch, d)
}

func render(t *template.Template, d caseData) (string, string, error) {
	var b strings.Builder
	if err := t.Execute(&b, d); err != nil {
		return "", "", err
	}
	dispatch := fmt.Sprintf("        .long   0x80000000 + _m8_case_%d\n", d.ID)
	return b.String(), dispatch, nil
}

// EmitImage returns a complete `.S` for a slice of classes sharing one
// bucket/axis: the runtime include, every emittable case routine, the
// `_m8_run_all` table-walk dispatcher, and a manifest comment listing skips.
func EmitImage(classes []Class, axis Axis) (string, error) {
	var blocks, dispatch, manifest strings.Builder
	n := 0
	for _, c := range classes {
		id := n + 1
		block, disp, err := emitCase(c, id, axis)
		if IsSkip(err) {
			manifest.WriteString(block)
			continue
		}
		if err != nil {
			return "", err
		}
		blocks.WriteString(block)
		blocks.WriteString("\n")
		dispatch.WriteString(disp)
		n++
	}

	var b strings.Builder
	fmt.Fprintf(&b, "! GENERATED by faultgen (M8). Axis=%s. Do not edit.\n", axisName(axis))
	b.WriteString("! Manifest of excluded (skipped) instructions:\n")
	if manifest.Len() == 0 {
		b.WriteString("!   (none)\n")
	} else {
		b.WriteString(manifest.String())
	}
	if axis == IFetch && n > 0 {
		// The I-fetch axis self-modifies the workload code page and relies on
		// icache coherence that is NOT yet provided. The emitted cases are
		// provisional; surface that here so a spurious Result is traceable.
		b.WriteString("! PROVISIONAL: I-fetch axis cases self-modify the code page and assume\n")
		b.WriteString("!   icache coherence not yet provided -- icache-coherence unvalidated,\n")
		b.WriteString("!   Task 4 to finish. A spurious Result on an I-fetch case may be a\n")
		b.WriteString("!   harness gap rather than a real CPU divergence.\n")
	}
	b.WriteString(`#include "m8_runtime.inc"` + "\n\n")
	b.WriteString("#if CONFIG_MMU_ARCH && CONFIG_PRIV_ARCH\n")
	b.WriteString("        .text\n")
	b.WriteString(blocks.String())

	// Table-walk dispatcher: r13=count, r14=table ptr; mov.l @r14+ has no
	// PC-relative range limit (unlike a per-case bsr/mov.l call).
	b.WriteString("ENTRY(_m8_run_all)\n")
	b.WriteString("        sts.l   pr, @-r15\n")
	b.WriteString("        mov.l   m8_tab_p, r14\n")
	b.WriteString("        mov.l   m8_count, r13\n")
	b.WriteString("1:      mov.l   @r14+, r3\n")
	b.WriteString("        jsr     @r3\n")
	b.WriteString("        nop\n")
	b.WriteString("        dt      r13\n")
	b.WriteString("        bf      1b\n")
	b.WriteString("        lds.l   @r15+, pr\n")
	b.WriteString("        rts\n")
	b.WriteString("        nop\n")
	b.WriteString("        .align 2\n")
	fmt.Fprintf(&b, "m8_count:  .long %d\n", n)
	b.WriteString("m8_tab_p:  .long 0x80000000 + m8_tab\n")
	b.WriteString("m8_tab:\n")
	b.WriteString(dispatch.String())
	b.WriteString("#endif\n")
	return b.String(), nil
}

// ManifestEntry records one instruction's place in an axis image. ID is the
// 1-based emitted case ID *within that axis* -- the exact number EmitImage
// assigns and the value the co-sim reports as Result=<ID>. ID is 0 and Emitted
// false for instructions the emitter skipped (SkipReason holds the human text).
type ManifestEntry struct {
	ID         int
	Name       string
	Bucket     Bucket
	Emitted    bool
	SkipReason string
}

// ImageManifest mirrors EmitImage's case-numbering loop so an external manifest
// can map a co-sim Result=<ID> back to its instruction. It MUST stay in lockstep
// with EmitImage (same iteration order, same id := n+1 / n++ accounting).
func ImageManifest(classes []Class, axis Axis) []ManifestEntry {
	var out []ManifestEntry
	n := 0
	for _, c := range classes {
		id := n + 1
		block, _, err := emitCase(c, id, axis)
		if err != nil { // IsSkip or a hard error: not emitted into the image
			out = append(out, ManifestEntry{
				Name:       c.Instr.Name,
				Bucket:     c.Bucket,
				SkipReason: skipReason(block, err),
			})
			continue
		}
		out = append(out, ManifestEntry{ID: id, Name: c.Instr.Name, Bucket: c.Bucket, Emitted: true})
		n++
	}
	return out
}

// skipReason extracts a one-line reason from an emitCase skip block ("! case N
// skipped: <reason>\n") or falls back to a hard error string.
func skipReason(block string, err error) string {
	s := strings.TrimSpace(block)
	s = strings.TrimPrefix(s, "!")
	s = strings.TrimSpace(s)
	if i := strings.Index(s, "skipped: "); i >= 0 {
		return strings.TrimSpace(s[i+len("skipped: "):])
	}
	if s != "" {
		return s
	}
	if err != nil {
		return err.Error()
	}
	return "skipped"
}

func axisName(a Axis) string {
	if a == IFetch {
		return "IFetch"
	}
	return "DSide"
}

// ---------------------------------------------------------------------------
// Templates. One per (bucket, axis). All calls use jsr-via-P1-alias literals.
// ---------------------------------------------------------------------------

var (
	tmplGeneralD = template.Must(template.New("genD").Parse(generalDText))
	tmplPrivMemD = template.Must(template.New("privD").Parse(privMemDText))
	tmplMacD     = template.Must(template.New("macD").Parse(macDText))
	tmplIFetch   = template.Must(template.New("ifetch").Parse(iFetchText))
)

// General D-side: snapshot {base reg, dest reg | written word}.
const generalDText = `        .balign 4
_m8_case_{{.ID}}:                       ! {{.Name}}  (General, D-side)
        sts.l   pr, @-r15
        ! ---- faulting leg (cold TLB) ----
        mov.l   c{{.ID}}_seedva, r0
        mov.l   c{{.ID}}_seed, r1
        mov.l   r1, @r0
        mov.l   r1, @(4,r0)
        mov.l   r1, @(8,r0)
        mov.l   r1, @(12,r0)
        mov.l   c{{.ID}}_flush, r3
        jsr     @r3
        nop
        mov.l   c{{.ID}}_va, r0
{{if .IsWrite}}        mov.l   c{{.ID}}_pay, r8
{{else}}        mov     #0, r8
{{end}}        .word   {{.Word}}                ! instruction under test
        mov.l   c{{.ID}}_snapa, r2
        mov.l   r0, @r2
{{if .IsWrite}}        mov.l   c{{.ID}}_probe, r3
        mov.l   @r3, r1
        mov.l   r1, @(4,r2)
{{else}}        mov.l   r8, @(4,r2)
{{end}}        ! ---- control leg (warm TLB) ----
        mov.l   c{{.ID}}_seedva, r0
        mov.l   c{{.ID}}_seed, r1
        mov.l   r1, @r0
        mov.l   r1, @(4,r0)
        mov.l   r1, @(8,r0)
        mov.l   r1, @(12,r0)
        mov.l   c{{.ID}}_va, r0
{{if .IsWrite}}        mov.l   c{{.ID}}_pay, r8
{{else}}        mov     #0, r8
{{end}}        .word   {{.Word}}
        mov.l   c{{.ID}}_snapb, r2
        mov.l   r0, @r2
{{if .IsWrite}}        mov.l   c{{.ID}}_probe, r3
        mov.l   @r3, r1
        mov.l   r1, @(4,r2)
{{else}}        mov.l   r8, @(4,r2)
{{end}}        ! ---- compare ----
        mov     #8, r4
        mov.l   c{{.ID}}_id, r5
        mov.l   c{{.ID}}_cmp, r3
        jsr     @r3
        nop
        lds.l   @r15+, pr
        rts
        nop
        .align 2
c{{.ID}}_va:     .long {{.BaseInit}}
c{{.ID}}_seedva: .long 0x00100000
c{{.ID}}_probe:  .long {{.Probe}}
c{{.ID}}_seed:   .long 0xA11C0001
c{{.ID}}_pay:    .long 0x57013333
c{{.ID}}_snapa:  .long SNAP_A
c{{.ID}}_snapb:  .long SNAP_B
c{{.ID}}_id:     .long {{.ID}}
c{{.ID}}_cmp:    .long 0x80000000 + _m8_cmp
c{{.ID}}_flush:  .long 0x80000000 + _m8_flush
`

// PrivMem D-side: as General plus the DestCtrl register. Original control reg
// is saved on entry and restored on exit; each leg sets it to a benign 0 so
// the only difference is cold-vs-warm TLB. Snapshot {base reg, ctrl value}.
const privMemDText = `        .balign 4
_m8_case_{{.ID}}:                       ! {{.Name}}  (PrivMem, D-side)
        sts.l   pr, @-r15
        mov     #0, r1
        {{.CtrlLoad}}            ! benign-init ctrl (never read 'U' on save)
        {{.CtrlSave}}            ! save baseline ctrl -> r1
        mov.l   c{{.ID}}_ctlsv, r2
        mov.l   r1, @r2
        ! ---- faulting leg (cold TLB) ----
        mov.l   c{{.ID}}_seedva, r0
        mov.l   c{{.ID}}_seed, r1
        mov.l   r1, @r0
        mov.l   r1, @(4,r0)
        mov.l   r1, @(8,r0)
        mov.l   r1, @(12,r0)
        mov.l   c{{.ID}}_flush, r3
        jsr     @r3
        nop
        mov.l   c{{.ID}}_va, r0
        mov     #0, r1
        {{.CtrlLoad}}            ! benign ctrl = 0
        .word   {{.Word}}                ! instruction under test
        {{.CtrlSave}}            ! read resulting ctrl
        mov.l   c{{.ID}}_snapa, r2
        mov.l   r0, @r2
        mov.l   r1, @(4,r2)
        ! ---- control leg (warm TLB) ----
        mov.l   c{{.ID}}_seedva, r0
        mov.l   c{{.ID}}_seed, r1
        mov.l   r1, @r0
        mov.l   r1, @(4,r0)
        mov.l   r1, @(8,r0)
        mov.l   r1, @(12,r0)
        mov.l   c{{.ID}}_va, r0
        mov     #0, r1
        {{.CtrlLoad}}
        .word   {{.Word}}
        {{.CtrlSave}}
        mov.l   c{{.ID}}_snapb, r2
        mov.l   r0, @r2
        mov.l   r1, @(4,r2)
        ! ---- restore original ctrl + compare ----
        mov.l   c{{.ID}}_ctlsv, r2
        mov.l   @r2, r1
        {{.CtrlLoad}}
        mov     #8, r4
        mov.l   c{{.ID}}_id, r5
        mov.l   c{{.ID}}_cmp, r3
        jsr     @r3
        nop
        lds.l   @r15+, pr
        rts
        nop
        .align 2
c{{.ID}}_va:     .long 0x00100000
c{{.ID}}_seedva: .long 0x00100000
c{{.ID}}_seed:   .long 0xA11C0001
c{{.ID}}_ctlsv:  .long 0x80003200
c{{.ID}}_snapa:  .long SNAP_A
c{{.ID}}_snapb:  .long SNAP_B
c{{.ID}}_id:     .long {{.ID}}
c{{.ID}}_cmp:    .long 0x80000000 + _m8_cmp
c{{.ID}}_flush:  .long 0x80000000 + _m8_flush
`

// MAC dual-base D-side: seed+snapshot BOTH bases (r0=Rm page A, r8=Rn page B,
// two distinct mapped pages so the second operand faults cold after the first
// base has auto-incremented) plus MACH+MACL. clrmac per leg fixes the
// accumulator start. Snapshot {r0, r8, MACH, MACL} = 16 bytes.
const macDText = `        .balign 4
_m8_case_{{.ID}}:                       ! {{.Name}}  (MAC dual-base, D-side)
        sts.l   pr, @-r15
        ! ---- faulting leg (cold TLB) ----
        mov.l   c{{.ID}}_seedva, r0     ! page A (Rm)
        mov.l   c{{.ID}}_seed, r1
        mov.l   r1, @r0
        mov.l   r1, @(4,r0)
        mov.l   c{{.ID}}_seedvb, r0     ! page B (Rn)
        mov.l   r1, @r0
        mov.l   r1, @(4,r0)
        mov.l   c{{.ID}}_flush, r3
        jsr     @r3
        nop
        clrmac
        mov.l   c{{.ID}}_seedva, r0     ! Rm base
        mov.l   c{{.ID}}_seedvb, r8     ! Rn base
        .word   {{.Word}}                ! instruction under test
        mov.l   c{{.ID}}_snapa, r2
        mov.l   r0, @r2
        mov.l   r8, @(4,r2)
        sts     mach, r1
        mov.l   r1, @(8,r2)
        sts     macl, r1
        mov.l   r1, @(12,r2)
        ! ---- control leg (warm TLB) ----
        mov.l   c{{.ID}}_seedva, r0
        mov.l   c{{.ID}}_seed, r1
        mov.l   r1, @r0
        mov.l   r1, @(4,r0)
        mov.l   c{{.ID}}_seedvb, r0
        mov.l   r1, @r0
        mov.l   r1, @(4,r0)
        clrmac
        mov.l   c{{.ID}}_seedva, r0
        mov.l   c{{.ID}}_seedvb, r8
        .word   {{.Word}}
        mov.l   c{{.ID}}_snapb, r2
        mov.l   r0, @r2
        mov.l   r8, @(4,r2)
        sts     mach, r1
        mov.l   r1, @(8,r2)
        sts     macl, r1
        mov.l   r1, @(12,r2)
        ! ---- compare ----
        mov     #16, r4
        mov.l   c{{.ID}}_id, r5
        mov.l   c{{.ID}}_cmp, r3
        jsr     @r3
        nop
        lds.l   @r15+, pr
        rts
        nop
        .align 2
c{{.ID}}_seedva: .long {{.BaseInit}}
c{{.ID}}_seedvb: .long {{.SeedVB}}
c{{.ID}}_seed:   .long 0xA11C0001
c{{.ID}}_snapa:  .long SNAP_A
c{{.ID}}_snapb:  .long SNAP_B
c{{.ID}}_id:     .long {{.ID}}
c{{.ID}}_cmp:    .long 0x80000000 + _m8_cmp
c{{.ID}}_flush:  .long 0x80000000 + _m8_flush
`

// I-fetch (non-memory instructions only): assemble [instr][jmp @r12][nop] into
// the translated workload page, jump there cold (IMISS) then warm. Snapshot the
// dest GPR (r8). NOTE: relies on Task 4 supplying icache coherence for the
// written stub; flagged in the image manifest.
const iFetchText = `        .balign 4
_m8_case_{{.ID}}:                       ! {{.Name}}  (Any, I-fetch)
        sts.l   pr, @-r15
        ! assemble stub at the workload code page: instr ; jmp @r12 ; nop
        mov.l   c{{.ID}}_codeva, r5
        mov.w   c{{.ID}}_instrw, r6
        mov.w   r6, @r5
        mov.w   c{{.ID}}_jmp12, r6
        mov.w   r6, @(2,r5)
        mov.w   c{{.ID}}_nopw, r6
        mov.w   r6, @(4,r5)
        ! ---- faulting leg (cold I-fetch) ----
        mov.l   c{{.ID}}_flush, r3
        jsr     @r3
        nop
        mov     #16, r0
        mov     #32, r8
        mov.l   c{{.ID}}_iret_a, r12
        mov.l   c{{.ID}}_codeva, r5
        jmp     @r5                     ! IMISS cold, restarts, then jmp @r12
        nop
c{{.ID}}_ireta:
        mov.l   c{{.ID}}_snapa, r2
        mov.l   r8, @r2
        ! ---- control leg (warm I-fetch) ----
        mov     #16, r0
        mov     #32, r8
        mov.l   c{{.ID}}_iret_b, r12
        mov.l   c{{.ID}}_codeva, r5
        jmp     @r5
        nop
c{{.ID}}_iretb:
        mov.l   c{{.ID}}_snapb, r2
        mov.l   r8, @r2
        ! ---- compare ----
        mov     #4, r4
        mov.l   c{{.ID}}_id, r5
        mov.l   c{{.ID}}_cmp, r3
        jsr     @r3
        nop
        lds.l   @r15+, pr
        rts
        nop
        .align 2
c{{.ID}}_codeva: .long 0x00100000
c{{.ID}}_instrw: .word {{.Word}}
c{{.ID}}_jmp12:  .word 0x4C2B            ! jmp @r12
c{{.ID}}_nopw:   .word 0x0009            ! nop
        .align 2
c{{.ID}}_iret_a: .long 0x80000000 + c{{.ID}}_ireta
c{{.ID}}_iret_b: .long 0x80000000 + c{{.ID}}_iretb
c{{.ID}}_snapa:  .long SNAP_A
c{{.ID}}_snapb:  .long SNAP_B
c{{.ID}}_id:     .long {{.ID}}
c{{.ID}}_cmp:    .long 0x80000000 + _m8_cmp
c{{.ID}}_flush:  .long 0x80000000 + _m8_flush
`
