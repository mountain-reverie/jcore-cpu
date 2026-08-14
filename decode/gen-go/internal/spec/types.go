package spec

// Defaults are the file-level defaults applied to every slot in every
// instruction if the slot leaves a field empty.
type Defaults struct {
	PC      string `toml:"pc"`
	IfIssue string `toml:"if_issue"`
	SR      string `toml:"sr"`
}

// Slot is one microcode step. All fields are optional; empty values
// inherit from Defaults. Field names mirror the original spreadsheet
// columns with snake_case naming. Values are always strings — the
// TOML schema stores control-signal names, register names, and numeric
// widths all as quoted strings.
//
// A multi-slot instruction may end with an empty slot (one carrying
// nothing beyond inherited defaults). Per the Clojure generator's
// parser.clj rule, that trailing empty slot is the implicit
// "if_issue=true, dispatch=true" cycle terminator — it must be kept,
// not stripped. Validate enforces empty slots only at the tail.
type Slot map[string]string

// Instr is one logical instruction with one or more slots.
type Instr struct {
	Name       string `toml:"name"`
	Format     string `toml:"format"`
	Opcode     string `toml:"opcode"`
	Opcode2    string `toml:"opcode2,omitempty"` // extension word for SH-2A two-word insns
	Operation  string `toml:"operation"`
	Plane      string `toml:"plane,omitempty"` // "" (default) or "system" (microcode-only, excluded from disassembler)
	TableRef   string `toml:"table_ref,omitempty"`
	Privileged bool   `toml:"privileged,omitempty"` // true => illegal-instruction trap when SR.MD=0
	// SlotIllegal forces this instruction into check_illegal_delay_slot even
	// when it does not assert wrpc_z. The derived rule (see model.BuildBody)
	// catches only instructions that write PC through wrpc_z, which silently
	// misses two ISA-mandated groups:
	//   - the conditional branches BT/BF/BT_S/BF_S, which redirect via
	//     zbus="T(PC)" + if_addy="ZBUS" rather than wrpc_z;
	//   - the PC-relative operand fetches MOVA and MOV.{W,L} @(disp,PC),Rn,
	//     which never write PC at all but read a PC that is indeterminate in
	//     a delay slot.
	// Both are listed as raising a slot illegal instruction exception by the
	// SH ISA (Renesas SH Instruction Set Summary, "Possible Exceptions").
	SlotIllegal bool `toml:"slot_illegal,omitempty"`
	// Patch marks an OVERLAY entry as an attribute patch: it refines the
	// attributes of the same-named base instruction in place instead of
	// replacing it, leaving opcode and microcode untouched. Only meaningful
	// in an overlay directory; see spec.applyPatch and spec/sh4/mov.toml.
	//
	// This is an explicit marker rather than an inferred one ("an entry with
	// no slots") because slotless overlay entries are already a legitimate way
	// to declare a whole instruction — see override_test.go.
	Patch bool   `toml:"patch,omitempty"`
	Slots []Slot `toml:"slots"`
}

// File represents the contents of one TOML file under spec/.
type File struct {
	Defaults Defaults `toml:"defaults"`
	Instrs   []Instr  `toml:"instr"`
}

// Spec is the merged collection loaded from a directory of TOML files.
type Spec struct {
	Defaults Defaults
	Instrs   []Instr
	// Source records the file each instruction came from, for error reporting.
	Source map[string]string // key = Instr.Name → filename
}
