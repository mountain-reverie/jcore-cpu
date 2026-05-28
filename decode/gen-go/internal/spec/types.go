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
	Name      string `toml:"name"`
	Format    string `toml:"format"`
	Opcode    string `toml:"opcode"`
	Operation string `toml:"operation"`
	Plane     string `toml:"plane,omitempty"` // "" (default) or "system" (microcode-only, excluded from disassembler)
	TableRef  string `toml:"table_ref,omitempty"`
	Slots     []Slot `toml:"slots"`
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
