package model

// Package carries a structured representation of every type, record,
// component, and constant in decode_pkg.vhd. It is populated by
// Build and passed to the decode_pkg.vhd template in Task 7.
type Package struct {
	// StaticEnums is every "type X is (A, B, ...)" enumeration in
	// decode_pkg.vhd, EXCEPT immval_t (dynamic, from ImmValLiterals)
	// and system_instr_t (rendered as a literal in the template).
	// Order is alphabetical by enum name, matching the golden file.
	StaticEnums []EnumType

	// ImmValLiterals is the ordered list of immval_t enum literals,
	// derived from CollectImmVals on the production spec.
	// Example: ["IMM_ZERO", "IMM_P1", "IMM_P2", ...].
	ImmValLiterals []string

	// SystemInstrNames is the fixed alphabetical list of system_instr_t
	// literals (rendered literally in the template, not via an EnumType).
	SystemInstrNames []string

	// Records is every "type X is record ... end record;" in decode_pkg.vhd,
	// in the order they appear in the golden file.
	Records []RecordType

	// Components is the three component declarations: decode, decode_core,
	// decode_table. In the order they appear in the golden file.
	Components []ComponentDecl

	// StaticConsts is the four package-level constants that the template
	// emits verbatim: DEC_CORE_RESET, system_instr_codes,
	// system_event_codes, system_event_instrs.
	StaticConsts []ConstantDecl

	// ROM-dependent fields: filled in by Task 9 once ROM addresses are known.
	// Task 7 stubs these with hardcoded golden values in the test.
	DecCoreROMResetAddr string            // full VHDL address literal, e.g. x"e2" (8-bit) or "000100011" (9-bit)
	SystemInstrROMAddrs map[string]string // e.g. {"BREAK": `x"fa"`, ...}
}

// EnumType represents one VHDL enumeration type declaration.
type EnumType struct {
	Name     string   // e.g. "aluinx_sel_t"
	Literals []string // e.g. ["SEL_XBUS", "SEL_FC", "SEL_ROTCL", "SEL_ZERO"]
}

// RecordType represents one VHDL record type declaration.
type RecordType struct {
	Name   string        // e.g. "operation_t"
	Fields []RecordField // in order they appear in the golden file
}

// RecordField is one field (or group of fields sharing the same type)
// in a VHDL record. VHDL allows "a, b : T;" — Names captures both names.
type RecordField struct {
	Names []string // e.g. ["wrmach", "wrmacl"] or ["plane"]
	Type  string   // e.g. "std_logic" or "instruction_plane_t"
}

// ComponentDecl represents one VHDL component declaration.
type ComponentDecl struct {
	Name  string // e.g. "decode"
	Ports []Port // sorted alphabetically by name within each direction group
}

// Port is one port in a component declaration.
type Port struct {
	Name      string // e.g. "clk"
	Direction string // "in" or "out"
	Type      string // e.g. "std_logic" or "std_logic_vector(3 downto 0)"
}

// ConstantDecl is one VHDL constant declaration.
type ConstantDecl struct {
	Name string // e.g. "DEC_CORE_RESET"
	Type string // e.g. "decode_core_reg_t"
	Init string // the aggregate literal initializer, verbatim
}

// newStaticPackage constructs the Package with all static (non-dynamic) fields.
// ImmValLiterals must be populated separately from microcode.CollectImmVals.
//
// Records ordering invariant: decode_core_reg_t MUST be the last element
// of Records. The decode_pkg.vhd.tmpl renders Records[:last] before the
// component declarations and the final Record (decode_core_reg_t) after
// them, because the constant DEC_CORE_RESET references the record type
// and is declared late in the package. Adding records is fine as long
// as decode_core_reg_t remains last; the test
// TestRecordsInvariantDecodeCoreRegLast guards this.
func newStaticPackage() *Package {
	return &Package{
		StaticEnums: []EnumType{
			{Name: "aluinx_sel_t", Literals: []string{"SEL_XBUS", "SEL_FC", "SEL_ROTCL", "SEL_ZERO"}},
			{Name: "aluiny_sel_t", Literals: []string{"SEL_YBUS", "SEL_IMM", "SEL_R0"}},
			{Name: "coproc_cmd_t", Literals: []string{"NOP", "LDS", "STS", "CLDS", "CSTS"}},
			{Name: "cpu_data_mux_t", Literals: []string{"DBUS", "COPROC"}},
			{Name: "cpu_decode_type_t", Literals: []string{"SIMPLE", "DIRECT", "ROM"}},
			{Name: "instruction_plane_t", Literals: []string{"NORMAL_INSTR", "SYSTEM_INSTR"}},
			{Name: "mac_busy_t", Literals: []string{"NOT_BUSY", "EX_NOT_STALL", "WB_NOT_STALL", "EX_BUSY", "WB_BUSY"}},
			{Name: "macin1_sel_t", Literals: []string{"SEL_XBUS", "SEL_ZBUS", "SEL_WBUS"}},
			{Name: "macin2_sel_t", Literals: []string{"SEL_YBUS", "SEL_ZBUS", "SEL_WBUS"}},
			{Name: "mem_addr_sel_t", Literals: []string{"SEL_XBUS", "SEL_YBUS", "SEL_ZBUS"}},
			{Name: "mem_wdata_sel_t", Literals: []string{"SEL_ZBUS", "SEL_YBUS"}},
			{Name: "reg_sel_t", Literals: []string{"SEL_R0", "SEL_R15", "SEL_RA", "SEL_RB"}},
			{Name: "sr_sel_t", Literals: []string{"SEL_PREV", "SEL_WBUS", "SEL_ZBUS", "SEL_DIV0U", "SEL_ARITH", "SEL_LOGIC", "SEL_INT_MASK", "SEL_SET_T", "SEL_EXCEPTION"}},
			{Name: "t_sel_t", Literals: []string{"SEL_CLEAR", "SEL_SET", "SEL_SHIFT", "SEL_CARRY"}},
			{Name: "xbus_sel_t", Literals: []string{"SEL_IMM", "SEL_REG", "SEL_PC"}},
			{Name: "ybus_sel_t", Literals: []string{"SEL_IMM", "SEL_REG", "SEL_MACH", "SEL_MACL", "SEL_PC", "SEL_SR"}},
			{Name: "zbus_sel_t", Literals: []string{"SEL_ARITH", "SEL_LOGIC", "SEL_SHIFT", "SEL_MANIP", "SEL_YBUS", "SEL_WBUS"}},
		},
		SystemInstrNames: []string{
			"BREAK", "ERROR", "GENERAL_ILLEGAL", "INTERRUPT", "RESET_CPU", "SLOT_ILLEGAL",
		},
		Records: []RecordType{
			{
				Name: "operation_t",
				Fields: []RecordField{
					{Names: []string{"plane"}, Type: "instruction_plane_t"},
					{Names: []string{"code"}, Type: "std_logic_vector(15 downto 0)"},
					{Names: []string{"addr"}, Type: "std_logic_vector(7 downto 0)"},
				},
			},
			{
				Name: "alu_ctrl_t",
				Fields: []RecordField{
					{Names: []string{"manip"}, Type: "alumanip_t"},
					{Names: []string{"inx_sel"}, Type: "aluinx_sel_t"},
					{Names: []string{"iny_sel"}, Type: "aluiny_sel_t"},
				},
			},
			{
				Name: "arith_ctrl_t",
				Fields: []RecordField{
					{Names: []string{"func"}, Type: "arith_func_t"},
					{Names: []string{"ci_en"}, Type: "std_logic"},
					{Names: []string{"sr"}, Type: "arith_sr_func_t"},
				},
			},
			{
				Name: "buses_ctrl_t",
				Fields: []RecordField{
					{Names: []string{"x_sel"}, Type: "xbus_sel_t"},
					{Names: []string{"y_sel"}, Type: "ybus_sel_t"},
					{Names: []string{"z_sel"}, Type: "zbus_sel_t"},
					{Names: []string{"imm_val"}, Type: "std_logic_vector(31 downto 0)"},
				},
			},
			{
				Name: "coproc_ctrl_t",
				Fields: []RecordField{
					{Names: []string{"cpu_data_mux"}, Type: "cpu_data_mux_t"},
					{Names: []string{"coproc_cmd"}, Type: "coproc_cmd_t"},
				},
			},
			{
				Name: "func_ctrl_t",
				Fields: []RecordField{
					{Names: []string{"alu"}, Type: "alu_ctrl_t"},
					{Names: []string{"shift"}, Type: "shiftfunc_t"},
					{Names: []string{"arith"}, Type: "arith_ctrl_t"},
					{Names: []string{"logic_func"}, Type: "logic_func_t"},
					{Names: []string{"logic_sr"}, Type: "logic_sr_func_t"},
				},
			},
			{
				Name: "instr_ctrl_t",
				Fields: []RecordField{
					{Names: []string{"issue"}, Type: "std_logic"},
					{Names: []string{"addr_sel"}, Type: "std_logic"},
				},
			},
			{
				Name: "mac_ctrl_t",
				Fields: []RecordField{
					{Names: []string{"com1"}, Type: "std_logic"},
					{Names: []string{"wrmach"}, Type: "std_logic"},
					{Names: []string{"wrmacl"}, Type: "std_logic"},
					{Names: []string{"s_latch"}, Type: "std_logic"},
					{Names: []string{"sel1"}, Type: "macin1_sel_t"},
					{Names: []string{"sel2"}, Type: "macin2_sel_t"},
					{Names: []string{"com2"}, Type: "mult_state_t"},
				},
			},
			{
				Name: "mem_ctrl_t",
				Fields: []RecordField{
					{Names: []string{"issue"}, Type: "std_logic"},
					{Names: []string{"wr"}, Type: "std_logic"},
					{Names: []string{"lock"}, Type: "std_logic"},
					{Names: []string{"size"}, Type: "mem_size_t"},
					{Names: []string{"addr_sel"}, Type: "mem_addr_sel_t"},
					{Names: []string{"wdata_sel"}, Type: "mem_wdata_sel_t"},
				},
			},
			{
				Name: "pc_ctrl_t",
				Fields: []RecordField{
					{Names: []string{"wr_z"}, Type: "std_logic"},
					{Names: []string{"wrpr"}, Type: "std_logic"},
					{Names: []string{"inc"}, Type: "std_logic"},
				},
			},
			{
				Name: "reg_ctrl_t",
				Fields: []RecordField{
					{Names: []string{"num_x"}, Type: "regnum_t"},
					{Names: []string{"num_y"}, Type: "regnum_t"},
					{Names: []string{"num_x_early"}, Type: "regnum_t"},
					{Names: []string{"num_y_early"}, Type: "regnum_t"},
					{Names: []string{"num_z"}, Type: "regnum_t"},
					{Names: []string{"num_w"}, Type: "regnum_t"},
					{Names: []string{"wr_z"}, Type: "std_logic"},
					{Names: []string{"wr_w"}, Type: "std_logic"},
				},
			},
			{
				Name: "sr_ctrl_t",
				Fields: []RecordField{
					{Names: []string{"sel"}, Type: "sr_sel_t"},
					{Names: []string{"t"}, Type: "t_sel_t"},
					{Names: []string{"ilevel"}, Type: "std_logic_vector(3 downto 0)"},
				},
			},
			{
				Name: "pipeline_ex_stall_t",
				Fields: []RecordField{
					{Names: []string{"wrpc_z"}, Type: "std_logic"},
					{Names: []string{"wrsr_z"}, Type: "std_logic"},
					{Names: []string{"ma_issue"}, Type: "std_logic"},
					{Names: []string{"wrpr_pc"}, Type: "std_logic"},
					{Names: []string{"zbus_sel"}, Type: "zbus_sel_t"},
					{Names: []string{"sr_sel"}, Type: "sr_sel_t"},
					{Names: []string{"t_sel"}, Type: "t_sel_t"},
					{Names: []string{"mem_addr_sel"}, Type: "mem_addr_sel_t"},
					{Names: []string{"mem_wdata_sel"}, Type: "mem_wdata_sel_t"},
					{Names: []string{"wrreg_z"}, Type: "std_logic"},
					{Names: []string{"wrmach", "wrmacl"}, Type: "std_logic"},
					{Names: []string{"shiftfunc"}, Type: "shiftfunc_t"},
					{Names: []string{"mulcom1"}, Type: "std_logic"},
					{Names: []string{"mulcom2"}, Type: "mult_state_t"},
					{Names: []string{"macsel1"}, Type: "macin1_sel_t"},
					{Names: []string{"macsel2"}, Type: "macin2_sel_t"},
				},
			},
			{
				Name: "pipeline_ex_t",
				Fields: []RecordField{
					{Names: []string{"imm_val"}, Type: "std_logic_vector(31 downto 0)"},
					{Names: []string{"xbus_sel"}, Type: "xbus_sel_t"},
					{Names: []string{"ybus_sel"}, Type: "ybus_sel_t"},
					{Names: []string{"regnum_z", "regnum_x", "regnum_y"}, Type: "regnum_t"},
					{Names: []string{"alumanip"}, Type: "alumanip_t"},
					{Names: []string{"aluinx_sel"}, Type: "aluinx_sel_t"},
					{Names: []string{"aluiny_sel"}, Type: "aluiny_sel_t"},
					{Names: []string{"arith_func"}, Type: "arith_func_t"},
					{Names: []string{"arith_ci_en"}, Type: "std_logic"},
					{Names: []string{"arith_sr_func"}, Type: "arith_sr_func_t"},
					{Names: []string{"logic_func"}, Type: "logic_func_t"},
					{Names: []string{"logic_sr_func"}, Type: "logic_sr_func_t"},
					{Names: []string{"mac_busy"}, Type: "std_logic"},
					{Names: []string{"ma_wr"}, Type: "std_logic"},
					{Names: []string{"mem_lock"}, Type: "std_logic"},
					{Names: []string{"mem_size"}, Type: "mem_size_t"},
					{Names: []string{"coproc_cmd"}, Type: "coproc_cmd_t"},
				},
			},
			{
				Name: "pipeline_id_t",
				Fields: []RecordField{
					{Names: []string{"incpc"}, Type: "std_logic"},
					{Names: []string{"if_issue"}, Type: "std_logic"},
					{Names: []string{"ifadsel"}, Type: "std_logic"},
				},
			},
			{
				Name: "pipeline_wb_stall_t",
				Fields: []RecordField{
					{Names: []string{"mulcom1"}, Type: "std_logic"},
					{Names: []string{"wrmach", "wrmacl"}, Type: "std_logic"},
					{Names: []string{"wrreg_w", "wrsr_w"}, Type: "std_logic"},
					{Names: []string{"macsel1"}, Type: "macin1_sel_t"},
					{Names: []string{"macsel2"}, Type: "macin2_sel_t"},
					{Names: []string{"mulcom2"}, Type: "mult_state_t"},
					{Names: []string{"cpu_data_mux"}, Type: "cpu_data_mux_t"},
				},
			},
			{
				Name: "pipeline_wb_t",
				Fields: []RecordField{
					{Names: []string{"regnum_w"}, Type: "regnum_t"},
					{Names: []string{"mac_busy"}, Type: "std_logic"},
				},
			},
			{
				Name: "pipeline_t",
				Fields: []RecordField{
					{Names: []string{"ex1"}, Type: "pipeline_ex_t"},
					{Names: []string{"ex1_stall"}, Type: "pipeline_ex_stall_t"},
					{Names: []string{"wb1"}, Type: "pipeline_wb_t"},
					{Names: []string{"wb2"}, Type: "pipeline_wb_t"},
					{Names: []string{"wb3"}, Type: "pipeline_wb_t"},
					{Names: []string{"wb1_stall"}, Type: "pipeline_wb_stall_t"},
					{Names: []string{"wb2_stall"}, Type: "pipeline_wb_stall_t"},
					{Names: []string{"wb3_stall"}, Type: "pipeline_wb_stall_t"},
				},
			},
			{
				Name: "decode_core_reg_t",
				Fields: []RecordField{
					{Names: []string{"maskint"}, Type: "std_logic"},
					{Names: []string{"delay_slot"}, Type: "std_logic"},
					{Names: []string{"id_stall"}, Type: "std_logic"},
					{Names: []string{"instr_seq_zero"}, Type: "std_logic"},
					{Names: []string{"op"}, Type: "operation_t"},
					{Names: []string{"ilevel"}, Type: "std_logic_vector(3 downto 0)"},
				},
			},
		},
		Components: []ComponentDecl{
			{
				Name: "decode",
				Ports: []Port{
					{Name: "clk", Direction: "in", Type: "std_logic"},
					{Name: "enter_debug", Direction: "in", Type: "std_logic"},
					{Name: "event_i", Direction: "in", Type: "cpu_event_i_t"},
					{Name: "ibit", Direction: "in", Type: "std_logic_vector(3 downto 0)"},
					{Name: "if_dr", Direction: "in", Type: "std_logic_vector(15 downto 0)"},
					{Name: "if_dr_next", Direction: "in", Type: "std_logic_vector(15 downto 0)"},
					{Name: "if_stall", Direction: "in", Type: "std_logic"},
					{Name: "illegal_delay_slot", Direction: "in", Type: "std_logic"},
					{Name: "illegal_instr", Direction: "in", Type: "std_logic"},
					{Name: "mac_busy", Direction: "in", Type: "std_logic"},
					{Name: "mask_int", Direction: "in", Type: "std_logic"},
					{Name: "rst", Direction: "in", Type: "std_logic"},
					{Name: "slot", Direction: "in", Type: "std_logic"},
					{Name: "t_bcc", Direction: "in", Type: "std_logic"},
					{Name: "buses", Direction: "out", Type: "buses_ctrl_t"},
					{Name: "copreg", Direction: "out", Type: "std_logic_vector(7 downto 0)"},
					{Name: "coproc", Direction: "out", Type: "coproc_ctrl_t"},
					{Name: "debug", Direction: "out", Type: "std_logic"},
					{Name: "event_ack", Direction: "out", Type: "std_logic"},
					{Name: "func", Direction: "out", Type: "func_ctrl_t"},
					{Name: "instr", Direction: "out", Type: "instr_ctrl_t"},
					{Name: "mac", Direction: "out", Type: "mac_ctrl_t"},
					{Name: "mem", Direction: "out", Type: "mem_ctrl_t"},
					{Name: "pc", Direction: "out", Type: "pc_ctrl_t"},
					{Name: "reg", Direction: "out", Type: "reg_ctrl_t"},
					{Name: "slp", Direction: "out", Type: "std_logic"},
					{Name: "sr", Direction: "out", Type: "sr_ctrl_t"},
				},
			},
			{
				Name: "decode_core",
				Ports: []Port{
					{Name: "clk", Direction: "in", Type: "std_logic"},
					{Name: "debug", Direction: "in", Type: "std_logic"},
					{Name: "delay_jump", Direction: "in", Type: "std_logic"},
					{Name: "dispatch", Direction: "in", Type: "std_logic"},
					{Name: "enter_debug", Direction: "in", Type: "std_logic"},
					{Name: "event_ack_0", Direction: "in", Type: "std_logic"},
					{Name: "event_i", Direction: "in", Type: "cpu_event_i_t"},
					{Name: "ex", Direction: "in", Type: "pipeline_ex_t"},
					{Name: "ex_stall", Direction: "in", Type: "pipeline_ex_stall_t"},
					{Name: "ibit", Direction: "in", Type: "std_logic_vector(3 downto 0)"},
					{Name: "id", Direction: "in", Type: "pipeline_id_t"},
					{Name: "if_dr", Direction: "in", Type: "std_logic_vector(15 downto 0)"},
					{Name: "if_dr_next", Direction: "in", Type: "std_logic_vector(15 downto 0)"},
					{Name: "if_stall", Direction: "in", Type: "std_logic"},
					{Name: "ilevel_cap", Direction: "in", Type: "std_logic"},
					{Name: "illegal_delay_slot", Direction: "in", Type: "std_logic"},
					{Name: "illegal_instr", Direction: "in", Type: "std_logic"},
					{Name: "mac_busy", Direction: "in", Type: "std_logic"},
					{Name: "mac_stall_sense", Direction: "in", Type: "std_logic"},
					{Name: "maskint_next", Direction: "in", Type: "std_logic"},
					{Name: "p", Direction: "in", Type: "pipeline_t"},
					{Name: "rst", Direction: "in", Type: "std_logic"},
					{Name: "slot", Direction: "in", Type: "std_logic"},
					{Name: "t_bcc", Direction: "in", Type: "std_logic"},
					{Name: "event_ack", Direction: "out", Type: "std_logic"},
					{Name: "if_issue", Direction: "out", Type: "std_logic"},
					{Name: "ifadsel", Direction: "out", Type: "std_logic"},
					{Name: "ilevel", Direction: "out", Type: "std_logic_vector(3 downto 0)"},
					{Name: "incpc", Direction: "out", Type: "std_logic"},
					{Name: "next_id_stall", Direction: "out", Type: "std_logic"},
					{Name: "op", Direction: "out", Type: "operation_t"},
				},
			},
			{
				Name: "decode_table",
				Ports: []Port{
					{Name: "clk", Direction: "in", Type: "std_logic"},
					{Name: "next_id_stall", Direction: "in", Type: "std_logic"},
					{Name: "op", Direction: "in", Type: "operation_t"},
					{Name: "t_bcc", Direction: "in", Type: "std_logic"},
					{Name: "debug", Direction: "out", Type: "std_logic"},
					{Name: "delay_jump", Direction: "out", Type: "std_logic"},
					{Name: "dispatch", Direction: "out", Type: "std_logic"},
					{Name: "event_ack_0", Direction: "out", Type: "std_logic"},
					{Name: "ex", Direction: "out", Type: "pipeline_ex_t"},
					{Name: "ex_stall", Direction: "out", Type: "pipeline_ex_stall_t"},
					{Name: "id", Direction: "out", Type: "pipeline_id_t"},
					{Name: "ilevel_cap", Direction: "out", Type: "std_logic"},
					{Name: "mac_s_latch", Direction: "out", Type: "std_logic"},
					{Name: "mac_stall_sense", Direction: "out", Type: "std_logic"},
					{Name: "maskint_next", Direction: "out", Type: "std_logic"},
					{Name: "slp", Direction: "out", Type: "std_logic"},
					{Name: "wb", Direction: "out", Type: "pipeline_wb_t"},
					{Name: "wb_stall", Direction: "out", Type: "pipeline_wb_stall_t"},
				},
			},
		},
		StaticConsts: []ConstantDecl{
			{
				Name: "DEC_CORE_RESET",
				Type: "decode_core_reg_t",
				Init: "(maskint => '0', delay_slot => '0', id_stall => '0', instr_seq_zero => '0', op => (plane => SYSTEM_INSTR, code => x\"0300\", addr => x\"01\"), ilevel => x\"0\")",
			},
			{
				Name: "system_instr_codes",
				Type: "system_instr_code_array",
				Init: "(BREAK => x\"2\", ERROR => x\"1\", GENERAL_ILLEGAL => x\"7\", INTERRUPT => x\"0\", RESET_CPU => x\"3\", SLOT_ILLEGAL => x\"6\")",
			},
			{
				Name: "system_event_codes",
				Type: "system_event_code_array",
				Init: "(INTERRUPT => x\"0\", ERROR => x\"1\", BREAK => x\"2\", RESET_CPU => x\"3\")",
			},
			{
				Name: "system_event_instrs",
				Type: "system_event_instr_array",
				Init: "(INTERRUPT => INTERRUPT, ERROR => ERROR, BREAK => BREAK, RESET_CPU => RESET_CPU)",
			},
		},
	}
}
