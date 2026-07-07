package spec

// KnownFields lists every snake_case slot field the validator accepts.
// Names mirror the CSV columns (snake-cased). Add a field here whenever
// you add a column-derived field to the schema.
var KnownFields = map[string]bool{
	// computational
	"xbus": true, "ybus": true, "alu_x": true, "alu_y": true,
	"zbus_sel": true, "zbus": true, "wbus": true,
	"sr": true, "arith": true, "arith_sr": true, "carryin_en": true,
	"logic": true, "logic_sr": true, "shift": true, "manip": true,
	// control flow
	"pc": true, "if_addy": true, "pr": true, "if_issue": true,
	"dispatch": true, "delay_jmp": true, "ilevel_capture": true,
	// memory access
	"ma_op": true, "ma_mask": true, "ma_size": true,
	"ma_data": true, "ma_addy": true, "ma_lock": true,
	// MAC unit
	"latch_s_mac": true, "mac_stage": true, "mac_busy": true,
	"mac_op": true, "mac_stall_sense": true,
	"macin_1": true, "macin_2": true, "mach": true, "macl": true,
	// system
	"debug": true, "event": true, "halt": true,
	"mask_int": true, "coproc_cmd": true, "data_mux": true,
	// MMU
	"tlb_wr": true,
	// SH-2A two-word instructions
	"latch_ext": true, "imm_from_ext": true,
}
