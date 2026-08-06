library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu2j0_pack.all;
use work.cpu2j0_components_pack.all;
use work.datapath_pack.all;
use work.decode_pack.all;
entity datapath is
 generic (
   PRIV_ARCH : boolean := false;
   SH2A_ARCH : boolean := false; -- SH-2A extensions (inert plumbing only)
   -- J1 only: drive the register file's early-read addresses and let
   -- architecture(ebr) read on the rising edge (full cycle). false for J2/J4.
   EARLY_REGFILE_READ : boolean := false;
   -- J1/iCESugar prototype only: offload the 32-bit arith_unit add/sub onto
   -- a free iCE40 SB_MAC16 DSP block (core/dsp_arith.vhd) instead of LUT
   -- adder logic. MUST default to false so J2/J4/sim VHDL stays
   -- byte-identical; set true only in the iCESugar J1-DSP board config.
   DSP_ALU : boolean := false );
 port (
       clk : in std_logic;
       rst : in std_logic;
       debug : in std_logic;
       enter_debug : out std_logic;
       slot : out std_logic;
       reg : in reg_ctrl_t;
       func : in func_ctrl_t;
       sr_ctrl : in sr_ctrl_t;
       mac : in mac_ctrl_t;
       mem : in mem_ctrl_t;
       instr : in instr_ctrl_t;
       pc_ctrl : in pc_ctrl_t;
       buses : in buses_ctrl_t;
       coproc : in coproc_ctrl_t;
       db_lock : out std_logic;
       db_o : out cpu_data_o_t;
       db_i : in cpu_data_i_t;
       inst_o : out cpu_instruction_o_t;
       inst_i : in cpu_instruction_i_t;
       debug_o : out cpu_debug_o_t;
       debug_i : in cpu_debug_i_t;
       macin1 : out std_logic_vector(31 downto 0);
       macin2 : out std_logic_vector(31 downto 0);
       mach : in std_logic_vector(31 downto 0);
       macl : in std_logic_vector(31 downto 0);
       -- J1: high while mult(seq) iterates -> stretch the slot so the
       -- frozen pipeline cannot drain a back-to-back MAC.L command into
       -- the busy multiplier. '0' for mult(stru) (J2/J4 unaffected).
       mult_stall : in std_logic;
       mac_s : out std_logic;
       -- SH-2A DIVU/DIVS: divider unit operand/start/result ports (Task 2).
       -- Mirrors macin1/macin2/mach/macl above -- the divider instance
       -- itself lives in cpu.vhd (like u_mult), and div_o.busy is folded
       -- into mult_stall alongside mac_o.slot_stall at the cpu.vhd level
       -- (no extra stall port needed here). '0'/unused on base
       -- (SH2A_ARCH=false), driven by g_div/g_div_off below.
       div_dividend : out std_logic_vector(31 downto 0);
       div_divisor : out std_logic_vector(31 downto 0);
       div_start : out std_logic;
       div_is_signed : out std_logic;
       div_quotient : in std_logic_vector(31 downto 0) := (others => '0');
       t_bcc : out std_logic;
       ibit : out std_logic_vector(3 downto 0);
       if_dr : out std_logic_vector(15 downto 0);
       if_dr_next : out std_logic_vector(15 downto 0);
       if_stall : out std_logic;
       mask_int : out std_logic;
       illegal_delay_slot : out std_logic;
       illegal_instr : out std_logic;
       copreg : in std_logic_vector(7 downto 0);
       cop_i : in cop_i_t;
       cop_o : out cop_o_t;
       priv_o : out cpu_priv_o_t := NULL_PRIV_O; -- SH-4 EXPEVT/INTEVT/TRA (J4)
       mmu_regs_o : out mmu_reg_t := MMU_REG_RESET; -- MMU CSRs for TLB (J4)
       sr_o : out sr_t; -- committed SR for TLB md bit
       -- Accumulate-squash export: the registered tlb_squash (armed on the
       -- first fault cycle, held until handler entry SR.RB='1') gates the MAC
       -- mach/macl accumulate-commit so MAC @Rm+,@Rn+ stays precise across a
       -- D-side TLB fault. '0' when not PRIV_ARCH (J1/J2 bit-identical).
       tlb_squash_o : out std_logic := '0';
       -- TLB fault side-effects: when tlb_exc_pend='1', write TEA, PTEH[31:14]
       -- and EXPEVT (the latter selected from the fault kind by cpu.vhd).
       tlb_exc_pend : in std_logic := '0';
       tlb_fault_va : in std_logic_vector(31 downto 0) := (others => '0');
       tlb_exc_expevt : in std_logic_vector(11 downto 0) := (others => '0');
       -- MMUFSR partial word from cpu.vhd (KIND/PROT/ITLB/WRITE); this
       -- process ORs in VALID (bit12) and USER (bit4, from this.sr.md) at
       -- capture time -- see the capture block below.
       tlb_exc_fsr : in std_logic_vector(12 downto 0) := (others => '0');
       -- Dynamic delay-slot flag of the instruction currently in EX, phase-
       -- aligned to the datapath EX control (registered in decode.vhd in
       -- lockstep with pipeline_r). Shadowed at the MA access-launch point as
       -- ma_dslot so a D-side TLB fault in a branch delay slot restarts at the
       -- BRANCH (re-issues the delay slot), not the delay-slot instruction.
       -- '0' on non-MMU builds (J1/J2 bit-identical).
       delay_slot : in std_logic := '0';
       -- '1' when the pending TLB fault is an I-fetch fault (IMISS/IPROT):
       -- the datapath captures the I-side restart PC from tlb_fault_va (the
       -- faulting fetch VA) with a delay-slot bias, instead of the D-side
       -- ma_pc shadow. '0' -> D-side capture (existing).
       tlb_exc_is_i : in std_logic := '0';
       -- '1' while the OUTSTANDING instruction fetch has a translation fault.
       -- Sampled at inst_i.ack into the per-instruction status vector (if_fault_next);
       -- see if_fault in components_pkg.vhd. '0' on non-MMU builds.
       inst_fault : in std_logic := '0';
       -- Deferred I-fetch fault of the instruction now presented to decode.
       if_fault_o : out std_logic;
       -- '1' iff this fault's VA is an instruction-fetch VA, for EVERY
       -- exc_kind that can raise it (IMISS/IPROT/MULTI_HIT) -- broader
       -- than tlb_exc_is_i, which is deliberately narrowed to IMISS/
       -- IPROT for restart-PC selection only. See cpu.vhd's declaration
       -- comment. Gates whether the D-side access shadow (ma_numz/
       -- ma_base/ma_autoupd) may be trusted for a restore.
       tlb_exc_ifetch : in std_logic := '0';
       -- Per-instruction fetch-PC round-trip (J4+PRIV_ARCH). if_pc = the VA of
       -- the instruction currently in if_dr (its own PC, captured at fetch
       -- before any branch redirect). decode re-registers it EX-aligned and
       -- returns it as ex_if_pc, from which the D-fault restart PC is derived
       -- directly (the ma_if_pc MA-launch shadow is dead state -- see
       -- components_pkg.vhd). '0' on non-MMU builds.
       if_pc : out std_logic_vector(31 downto 0);
       ex_if_pc : in std_logic_vector(31 downto 0) := (others => '0')
      );
end entity datapath;
architecture stru of datapath is
 subtype reg_t is std_logic_vector(31 downto 0);
 signal gpf_zwd, pc, reg_x, reg_y, reg_0, xbus, xbus_mux, ybus, ybus_temp, zbus, wbus : std_logic_vector(31 downto 0);
 -- SH-2A CS (SR bit 2, CLIPS/CLIPU saturation), driven by g_cs/g_cs_off
 -- below (mirrors the xbus g_push/g_push_off mux pattern: driven fully in
 -- exactly one of the two mutually-exclusive generate branches). Tied to
 -- '0' on a non-SH2A build. Deliberately NOT part of sr_t/datapath_reg_t
 -- (see the note on sr_t in core/components_pkg.vhd).
 signal sr_cs : std_logic;
-- SH-2A MULR MAC save/restore shadow registers (mac_shadow_h/l), driven by
-- g_macsh/g_macsh_off below. Mirrors sr_cs: kept as small SH2A_ARCH-gated
-- standalone registers rather than widening the shared datapath_reg_t
-- ("this"), for the same reason (base J2 techmap perturbation, see the
-- sr_cs note above). Captured on the committed slot (slot_o) when
-- func.alu.manip = MAC_SAVE; restored via manip_sel below (SEL_MANIP).
signal mac_shadow_h, mac_shadow_l : std_logic_vector(31 downto 0);
-- SH2A-gated SEL_MANIP zbus/zbus_mac source: on base this is exactly
-- manip(xbus, ybus, sr.t, func.alu.manip, false), logically byte-identical
-- to the pre-existing inline call (g_msel_off below).
signal manip_sel : std_logic_vector(31 downto 0);
 -- zbus as the multiplier operand mux (macin1/macin2) sees it: identical to
 -- zbus except the SEL_SHIFT (shifter) source is a don't-care (see below).
 signal zbus_mac : std_logic_vector(31 downto 0);
 -- STC SR read value. SH2A builds: to_slv(sr, sr_cs) (CS at bit 2). Base:
 -- plain to_slv(sr) -- BYTE-IDENTICAL to master, so the sr_o read path is
 -- unperturbed (the 2-arg overload's extra r(CS) assignment otherwise
 -- restructures the whole SR vector and depressed base Fmax ~11%).
 signal sr_slv : std_logic_vector(31 downto 0);
 signal sr : sr_t;
 signal priv_regs : priv_reg_t; -- SH-4 EXPEVT/INTEVT/TRA (J4); 0 on J1/J2
 signal mmu_regs : mmu_reg_t; -- SH-4 MMU CSRs (J4); 0 otherwise
 signal mmu_ybus : std_logic_vector(31 downto 0); -- sub-mux for SEL_MMU
 -- Faulting-instruction restart-PC capture (J4): registered copy
 -- routed onto xbus via SEL_TLBPC for the D-fault exception entry.
 signal tlb_exc_pc : std_logic_vector(31 downto 0);
 signal tlb_exc_sr_r : sr_t; -- registered captured user SR (SEL_TLBSR)
 -- regfile addresses after SH-4 bank remapping (pass-through on J2)
 signal num_x_r, num_y_r, num_z_r, num_w_r : regnum_t;
 signal num_0_r : regnum_t;
 signal num_x_early_r, num_y_early_r : regnum_t;
 signal sfto : std_logic;
 signal shift_b : std_logic_vector(5 downto 0);
 signal shift_sel : std_logic;
 signal shift_y : std_logic_vector(31 downto 0);
 signal shift_busy : std_logic; -- always '0' for shifter(comb); drives the
                                 -- pipeline stall when shifter(seq) binds in Step 2b
 -- alu ports
 signal aluiny, aluinx : std_logic_vector(31 downto 0);
 signal reg_wr_data_o : std_logic_vector(31 downto 0);
 -- GPR write-enables, gated low during the precise-exception squash window
 -- (J4). On a non-MMU build these are exactly reg.wr_z/reg.wr_w, so
 -- J1/J2 behaviour is byte-identical and tlb_squash prunes away.
 signal reg_wr_z_g, reg_wr_w_g : std_logic;
 -- NOTE -- the one-shot program-order ("age") grace bit for the w-port
 -- squash (wb_grace) is declared INSIDE g_wb_grace, not here. A signal
 -- declared at architecture scope and merely tied off under
 -- "if not MMU_ARCH generate" still EXISTS on J1/J2: yosys carries it
 -- through flatten as a dangling zero-cell wire, which perturbs abc9's
 -- technology mapping (measured: non-monotonic +/-464 LUT4 swings on J1
 -- with the flop count constant). Keeping it generate-local means the
 -- base variants elaborate with no trace of it at all. Its consumer
 -- reg_wr_w_g is assigned in the two generate branches for the same
 -- reason. Same precedent as the SH2A_ARCH g_push locals.
 -- Shared "the squash arms on this clock edge" predicate (J4+MMU_ARCH),
 -- consumed by BOTH the tlb_squash arming in the process and g_wb_grace.
 -- Constant '0' off MMU_ARCH so J1/J2 prune it. See its assignment below.
 signal squash_arm : std_logic;
 -- Registered "the fault that armed the CURRENT squash window was an
 -- INSTRUCTION-FETCH fault" (J4+MMU_ARCH; constant '0' off MMU_ARCH so J1/J2
 -- prune it, exactly like squash_arm). See the AGE RULE above reg_wr_w_g.
 signal squash_ifetch_r : std_logic;
 signal ybus_override : bus_val_t;
 signal slot_o : std_logic;
 -- Precise auto-increment restore (J4). mem_autoupd marks the current
 -- EX op as a memory base post-increment (@Rn+): a data access whose base
 -- register (xbus = Rn) feeds the address while the z-bus writes Rn+size back.
 -- restore_fire drives the one-shot base restore on the first EX-write slot the
 -- microcode leaves free after the fault (reg.wr_z='0' => not an SPC/SSR save).
 signal mem_autoupd : std_logic;
 signal mem_autoinc1 : std_logic;
 signal mem_predec : std_logic;
 signal restore_fire : std_logic;
 -- SECOND base-restore entry (J4+MMU_ARCH), for the DUAL-base form
 -- MAC.L/W @Rm+,@Rn+. That instruction reads two post-increment operands in
 -- successive EX slots; on a fault at the SECOND read the FIRST read's base
 -- bump has already committed, so the single entry above (which restores the
 -- faulting access's own base) leaves the first base at +size and the
 -- RTE-restart bumps it a second time. This entry carries the first operand's
 -- (base register, pre-increment value) and is fired one eligible slot after
 -- the first entry. Declared INSIDE g_restore2 (not here) and deliberately
 -- NOT new fields in the shared datapath_reg_t "this" record: widening that
 -- record perturbs the base J1/J2 techmap even for arch-gated fields, and so
 -- does an architecture-scope declaration that is merely tied off under
 -- "if not MMU_ARCH generate" -- 38 dangling zero-cell wire bits survive
 -- flatten and steer abc9 (see the wb_grace note above). Their three
 -- consumers (gpf_zwd, num_z_r, reg_wr_z_g) are therefore assigned in the
 -- g_restore2 / g_restore2_off branches too.
 -- ma_launch: "the ma_* access shadow is being written this cycle", i.e. the
 -- data access of an instruction is being handed to the bus. Driven from
 -- INSIDE the datapath process, at the very statement that writes
 -- ma_numz/ma_base/ma_if_pc, so it cannot drift out of step with them. It
 -- cannot be expressed as a concurrent assignment the way squash_arm was
 -- (d8d4682): the process's own launch condition tests this.data_o.en as a
 -- mid-evaluation VARIABLE, which is not the registered value -- the ack
 -- clears it in the same evaluation that launches the next access, so
 -- back-to-back accesses show no 0->1 edge on the registered bit at all.
 -- Assigned only under MMU_ARCH, so J1/J2 see a constant '0'.
 signal ma_launch : std_logic;
 -- Registered tlb_squash, made readable INSIDE the process (this_r is
 -- only usable in the concurrent assignments below). Used to suppress new
 -- memory transactions issued in the fault shadow, symmetrically with the
 -- reg_wr_z_g / reg_wr_w_g writeback gating. Tied '0' off MMU_ARCH so J1/J2
 -- prune it away entirely.
 signal tlb_squash_r : std_logic;
 -- SH2A_ARCH only: signature classification for the restart-safe MOVML.L
 -- Rm,@-R15 push (docs/superpowers/specs/2026-07-09-j2a-restart-safe-push-
 -- design.md §3). push_ptr_init marks the once-per-instruction slot that
 -- computes push_ptr := R15-(m+1)*4 (captured, not written back to R15);
 -- push_ptr_store marks each store-loop slot (R(idx) @ push_ptr+idx*4),
 -- whose xbus address base is substituted with push_ptr. Both signatures
 -- key off the J2A-exclusive IMM_U_H4_2 ("UH*4") immediate operand
 -- (func.alu.iny_sel = SEL_IMM) combined with xbus=R15, no GPR commit
 -- (reg.wr_z='0') and pc HELD (pc_ctrl.inc='0', i.e. not yet the terminal
 -- slot); push_ptr_init is further keyed on the SUB direction (vs ADD for
 -- the store address) and no memory access, push_ptr_store on a WRITE
 -- memory access. Checked against every base+SH2A spec slot (base
 -- MOV.L Rm,@(disp,Rn) with n=15 numerically collides on the immediate
 -- value alone but is single-slot / pc_ctrl.inc='1', so the pc-held
 -- qualifier excludes it; exception-frame pushes and movmu push/pop use
 -- the same UH*4-shaped constant/immediate but always commit R15 in the
 -- same slot, so wr_z='0' excludes them) -- see the design doc + task
 -- report for the full collision analysis.
 --
 -- NOTE: push_ptr_init/push_ptr_store/push_ptr_term are declared LOCAL to the
 -- SH2A_ARCH generate (g_push) below, NOT at architecture scope. Even driven
 -- to a constant '0' and read only inside a non-elaborated generate, their
 -- mere presence as architecture-level signals perturbs the J4 datapath
 -- techmap by ~+196 LUT4 (datapath's assert-derived `keep` prevents the
 -- optimizer from collapsing them). Keeping them generate-local means non-SH2A
 -- variants (J1/J2/J4) carry no push signals at all -> J4 returns to baseline.
        signal div1_arith_func : arith_func_t;
        signal arith_func : arith_func_t;
        signal arith_out : std_logic_vector(32 downto 0);
        signal logic_out : std_logic_vector(31 downto 0);
 signal this_c : datapath_reg_t;
 signal this_r : datapath_reg_t := DATAPATH_RESET;
        -- The functions to_sr and to_slv convert between the sr record and its CPU register representation.
        function to_sr(a : std_logic_vector(31 downto 0)) return sr_t is
          variable r : sr_t;
        begin
          r.m := a(M); r.q := a(Q); r.int_mask := a(I3 downto I0); r.s := a(S); r.t := a(T);
          r.md := a(MD); r.rb := a(RB); r.bl := a(BL);
          return r;
        end to_sr;
        function to_slv(sr : sr_t) return std_logic_vector is
          variable r : std_logic_vector(31 downto 0) := (others => '0');
        begin
          r(M) := sr.m; r(Q) := sr.q; r(I3 downto I0) := sr.int_mask; r(S) := sr.s; r(T) := sr.t;
          -- MD/RB/BL only observable on a privileged-arch (J4) build; a J2 build
          -- (PRIV_ARCH=false) leaves bits 28-30 zero so STC SR is bit-identical.
          if PRIV_ARCH then
            r(MD) := sr.md; r(RB) := sr.rb; r(BL) := sr.bl;
          end if;
          return r;
        end to_slv;
        -- SH-2A CS (SR bit 2, CLIPS/CLIPU saturation) overload: cs lives OUTSIDE
        -- sr_t/datapath_reg_t entirely (see the R1 note on sr_t in
        -- core/components_pkg.vhd) -- it is a small generate-local register
        -- (signal sr_cs, g_cs/g_cs_off below) muxed in here at the one STC SR
        -- read site. On a non-SH2A build sr_cs is tied to '0' (g_cs_off), so
        -- this is bit-identical to plain to_slv(sr).
        function to_slv(sr : sr_t; cs_bit : std_logic) return std_logic_vector is
          variable r : std_logic_vector(31 downto 0);
        begin
          r := to_slv(sr);
          r(CS) := cs_bit;
          return r;
        end to_slv;
        -- Regfile depth: J4 (PRIV_ARCH) needs 8 extra slots for bank-1 R0-R7
        -- at indices 24-31; J2A (SH2A_ARCH) needs index 23 for TBR, so 24;
        -- J2 keeps 21 (bit-identical).
        function rf_depth(priv : boolean; sh2a : boolean) return integer is
        begin
          if priv then return 32; elsif sh2a then return 24; else return 21; end if;
        end function;
        -- SH-4 register banking: when privileged and RB=1, architectural R0-R7
        -- ("00nnn") map to bank-1 ("11nnn"), and R*_BANK operands ("11nnn") map
        -- to bank-0 ("00nnn") -- always the opposite bank. One symmetric swap of
        -- addr(4 downto 3) does both. R8-R15 ("01") and system regs ("10xxx")
        -- are unbanked.
        function bank_remap(a : regnum_t; sr_md, sr_rb : std_logic) return regnum_t is
          variable r : regnum_t := a;
        begin
          if sr_md = '1' and sr_rb = '1' then
            if a(4 downto 3) = "00" then r(4 downto 3) := "11";
            elsif a(4 downto 3) = "11" then r(4 downto 3) := "00";
            end if;
          end if;
          return r;
        end function;
        constant REGFILE_DEPTH : integer := rf_depth(PRIV_ARCH, SH2A_ARCH);
 -- A bit vector from a single bit
 function to_slv(b : std_logic; s : integer) return std_logic_vector is
   variable r : std_logic_vector(s-1 downto 0);
 begin
   r := (others => b);
 return r;
 end to_slv;
        function to_data_o(mem : mem_ctrl_t; coproc : coproc_ctrl_t;
                           addr : std_logic_vector(31 downto 0);
                           data : std_logic_vector(31 downto 0))
        return cpu_data_o_t is
          variable r : cpu_data_o_t := NULL_DATA_O;
        begin
          if mem.issue = '1' then
            r.en := '1';
            r.wr := mem.wr;
            r.rd := not mem.wr;
            r.a := addr;
            -- for writes, prepare we and d signals
            if mem.wr = '1' then
              case mem.size is
                when LONG =>
                  r.d := data; r.we := "1111";
                when WORD =>
                  if addr(1) = '0' then r.we := "1100";
                  else r.we := "0011"; end if;
                  r.d := data(15 downto 0) & data(15 downto 0);
                when BYTE =>
                  -- TODO: Use shift or rotate operator instead of case?
                  case addr(1 downto 0) is
                    when "00" => r.we := "1000";
                    when "01" => r.we := "0100";
                    when "10" => r.we := "0010";
                    when others => r.we := "0001";
                  end case;
                  r.d := data(7 downto 0) & data(7 downto 0) & data(7 downto 0) & data(7 downto 0);
              end case;
            end if;
          elsif coproc.coproc_cmd = LDS then
                  r.d := data;
          end if;
          return r;
        end to_data_o;
        function to_inst_o(instr : instr_ctrl_t; addr : std_logic_vector(31 downto 0);
                           -- default to jump=1 unless caller knows address is incremented PC
                           jp : std_logic := '1')
        return cpu_instruction_o_t is
          variable r : cpu_instruction_o_t := NULL_INST_O;
        begin
          if instr.issue = '1' then
            r.en := '1';
            r.a := addr(31 downto 1);
            r.jp := jp;
          end if;
          return r;
        end to_inst_o;
        function align_read_data(d : std_logic_vector(31 downto 0); bus_o : cpu_data_o_t; size : mem_size_t)
        return std_logic_vector is
          variable r : std_logic_vector(31 downto 0);
        begin
          case size is
            when BYTE =>
              case bus_o.a(1 downto 0) is
                when "00" => r := to_slv(d(31), 24) & d(31 downto 24);
                when "01" => r := to_slv(d(23), 24) & d(23 downto 16);
                when "10" => r := to_slv(d(15), 24) & d(15 downto 8);
                when others => r := to_slv(d( 7), 24) & d( 7 downto 0);
              end case;
            when WORD =>
              case bus_o.a(1) is
                when '0' => r := to_slv(d(31), 16) & d(31 downto 16);
                when others => r := to_slv(d(15), 16) & d(15 downto 0);
              end case;
            when others => r := d;
          end case;
          return r;
        end align_read_data;
 -- J1/iCESugar DSP-ALU prototype (see DSP_ALU generic above and
 -- core/dsp_arith.vhd). Only elaborated when the DSP_ALU generate branch
 -- fires. Deliberately a COMPONENT instantiation (not a direct entity
 -- instantiation): component binding is resolved at ELABORATION time (after
 -- all files are analyzed), so it does not depend on dsp_arith.vhd being
 -- analyzed before this file -- unlike a direct `entity work.dsp_arith(..)`
 -- instantiation, which GHDL resolves at ANALYSIS time and therefore
 -- requires strict file ordering (this bit both targets/boards/icesugar/
 -- synth.sh, which analyzes the whole design in one ghdl invocation, and
 -- sim.sh, which does separate `ghdl -a` calls in filelist.sh's fixed
 -- order). u_dsp_arith is bound explicitly in
 -- synth/cpu_synth_j1_dsp_config.vhd and core/cpu_config.vhd's
 -- cpu_sim_dsp_alu (`for u_dsp_arith : dsp_arith use entity
 -- work.dsp_arith(ice40dsp)`), which also keeps it un-blackboxed under
 -- ghdl --syn-binding (which only blackboxes components left UNBOUND).
 component dsp_arith is
   port (
     clk : in std_logic;
     a : in std_logic_vector(31 downto 0);
     b : in std_logic_vector(31 downto 0);
     is_sub : in std_logic;
     ci : in std_logic;
     result : out std_logic_vector(32 downto 0));
 end component;
begin
 -- Multiplexors for the internal buses
 -- SEL_TLBPC delivers the hardware-captured faulting-instruction PC
 -- (tlb_exc_pc) for the D-side TLB-fault exception entry, so SPC<-TLBPC-adjust
 -- restarts the faulting access even when the frozen fetch PC's lead is
 -- variable (back-to-back faults). The decoder asserts SEL_TLBPC for exactly
 -- the one SPC slot of the D-fault entries (spec/sh4/exceptions.toml), so the
 -- substitution is scoped by the microcode -- no held flag, and every
 -- (possibly stalled, re-evaluated) cycle of that slot sees the same value.
 -- I-fetch faults keep SEL_PC (live PC). tlb_exc_pc is 0 on a non-MMU build
 -- and SEL_TLBPC never appears there, so J1/J2 are unaffected.
 -- push_ptr_store (SH2A_ARCH only, see the signal declaration above):
 -- substitutes the datapath-internal push_ptr as the store address base
 -- for a restart-safe MOVML.L Rm,@-R15 store-loop slot, overriding the
 -- normal xbus mux. Register stores and the (untouched, Task 2) movmu
 -- PR-store never match (they commit R15 in the same slot, wr_z='1');
 -- pop loads are ma_op=READ, so unaffected. Inert on J1/J2/J4.
 with buses.x_sel select xbus_mux <= reg_x when SEL_REG, pc when SEL_PC, tlb_exc_pc when SEL_TLBPC, buses.imm_val when others;
 -- xbus is driven in the g_push/g_push_off generate below. The push logic is a
 -- GENERATE (not a `when SH2A_ARCH and ...` concurrent mux) so on non-SH2A the
 -- push_ptr/push_active reads are removed at elaboration; otherwise the
 -- datapath's assert-derived `keep` blocks yosys from pruning the (reset-only)
 -- push_ptr/push_active record fields + push comparators, spilling ~209 LUT4
 -- into J4 (measured, PR #110 benchmark alert).
 with buses.y_sel select ybus_temp <= reg_y when SEL_REG, pc when SEL_PC, mach when SEL_MACH, macl when SEL_MACL, sr_slv when SEL_SR,
                                      (x"00000" & priv_regs.expevt) when SEL_EXPEVT,
                                      (x"00000" & priv_regs.intevt) when SEL_INTEVT,
                                      (x"00000" & "00" & priv_regs.tra) when SEL_TRA,
                                      mmu_ybus when SEL_MMU,
                                      to_slv(tlb_exc_sr_r) when SEL_TLBSR,
                                      buses.imm_val when others;
 ybus <= ybus_override.d when ybus_override.en = '1' else ybus_temp;
 -- On the precise auto-increment restore cycle the EX write data is the
 -- captured pre-increment base (tlb_restore_val); otherwise the normal z path.
 -- The second (MAC first-operand) entry uses the same port one slot later.
 -- Assigned in the g_restore2 / g_restore2_off branches below, because the
 -- restore2_* operands must not exist at all on J1/J2 (see their note above).
 -- mem_autoupd: marks the memory-access slot of a post-increment load @Rm+.
 -- In j-core a post-increment is a two-slot op: slot0 commits Rm := Rm+size on
 -- the EX z-port (no access), then THIS slot reads memory with the address
 -- recomputed as Rm-size, i.e. ma_addy=ZBUS, arith=SUB, base (Rm) on xbus, a
 -- READ. That arith=SUB + ZBUS-addressed READ is unique to @Rm+ (plain @Rm uses
 -- zbus_sel=Y; @(disp,Rm) and indexed loads use ADD; pre-decrement @-Rn is a
 -- WRITE). The faulting VA equals Rm-size = the original pre-increment base, so
 -- restoring Rm := tlb_fault_va undoes slot0's early bump. J4 only.
 mem_autoupd <= '1' when PRIV_ARCH and mem.issue = '1' and mem.wr = '0'
                         and mem.addr_sel = SEL_ZBUS and func.arith.func = SUB
                else '0';
 -- mem_predec: marks the memory-access slot of a pre-decrement store @-Rn
 -- (MOV.B/W/L Rm,@-Rn, STS.L/STC.L *,@-Rn). Symmetric to mem_autoupd but for
 -- the WRITE direction: a single-slot op whose base Rn is decremented (zbus =
 -- Rn-size, ARITH=SUB) on the EX z-port WHILE the same slot stores to that new
 -- address (ma_addy=ZBUS, a WRITE). The store-address SUB+ZBUS+wr combination
 -- is unique to @-Rn (plain @Rn stores use addr_sel=YBUS/XBUS; @(disp,Rn) and
 -- indexed stores use ADD). Because the faulting VA equals Rn-size (the post-
 -- decrement address) NOT the pre-decrement base, the original base is captured
 -- separately (ma_base = xbus = Rn) for the restore. J4 only.
 mem_predec <= '1' when PRIV_ARCH and mem.issue = '1' and mem.wr = '1'
                        and mem.addr_sel = SEL_ZBUS and func.arith.func = SUB
               else '0';
 -- mem_autoinc1: marks the memory-access slot of a SINGLE-SLOT post-increment
 -- load @Rm+ whose base bump commits IN the same slot as the read. Unlike the
 -- two-slot @Rm+ forms (mem_autoupd, increment deferred to slot1 in the fault
 -- shadow), LDS.L @Rm+,MACH/MACL read @Rm with ma_addy=XBUS while the EX z-port
 -- writes Rm+4 (ARITH/ADD) in the very slot that faults -- one cycle before
 -- tlb_squash can arm, so reg_wr_z_g cannot suppress it and the base would
 -- double-increment after RTE. Detected here (read + concurrent z-write of the
 -- SAME register being addressed) and routed through the base-restore path:
 -- the faulting VA equals the original Rm (ma_addy=XBUS), so restoring
 -- Rm := tlb_fault_va undoes the early bump exactly like mem_autoupd.
 mem_autoinc1 <= '1' when PRIV_ARCH and mem.issue = '1' and mem.wr = '0'
                          and mem.addr_sel = SEL_XBUS
                          and reg.wr_z = '1' and buses.z_sel = SEL_ARITH
                          and func.arith.func = ADD and num_z_r = num_x_r
                 else '0';
 -- Fire the base restore on the first committed slot after the fault on which
 -- the microcode itself is not driving the z-write port (reg.wr_z='0'): this is
 -- clear of the exception entry's slot0/slot1 SPC(21)/SSR(22) saves, so the two
 -- never collide on the shared EX write port.
 restore_fire <= '1' when PRIV_ARCH and this_r.tlb_restore_pend = '1'
                          and reg.wr_z = '0' and slot_o = '1'
                 else '0';
 -- push_ptr_init: the once-per-instruction MOVML.L Rm,@-R15 push slot that
 -- computes push_ptr := R15-(m+1)*4 (SUB, xbus=R15, UH*4 immediate,
 -- pc HELD, no memory access, no GPR commit). See the signal declaration
 -- above for the full collision analysis.
 g_push : if SH2A_ARCH generate
   signal push_ptr_init : std_logic;
   signal push_ptr_store : std_logic;
   signal push_ptr_term : std_logic;
   signal push_ptr_r : std_logic_vector(31 downto 0) := (others => '0');
   signal push_active_r : std_logic := '0';
begin
 -- push_ptr_init: the once-per-instruction MOVML.L Rm,@-R15 push slot that
 -- computes push_ptr := R15-(m+1)*4 (SUB, xbus=R15, UH*4 immediate, pc HELD,
 -- no memory access, no GPR commit).
   push_ptr_init <= '1' when func.alu.iny_sel = SEL_IMM
                           and func.arith.func = SUB and mem.issue = '0'
                           and reg.wr_z = '0' and pc_ctrl.inc = '0'
                           and buses.x_sel = SEL_REG and num_x_r = "01111"
                  else '0';
 -- push_ptr_term: the once-per-instruction MOVML.L Rm,@-R15 terminal slot that
 -- commits R15 := R15-(m+1)*4 (SUB, xbus=R15, UH*4 immediate, no mem, GPR write
 -- of R15). Same shape as push_ptr_init but reg.wr_z='1' (init is '0'); the pop
 -- terminal uses ADD, so SUB+wr_z+R15 is unique to the push terminal.
   push_ptr_term <= '1' when func.alu.iny_sel = SEL_IMM
                           and func.arith.func = SUB and mem.issue = '0'
                           and reg.wr_z = '1'
                           and buses.x_sel = SEL_REG and num_x_r = "01111"
                  else '0';
   process(clk, rst)
   begin
     if rst = '1' then
       push_ptr_r <= (others => '0');
       push_active_r <= '0';
     elsif clk = '1' and clk'event then
       if slot_o = '1' then
         -- Capture push_ptr := R15-(m+1)*4 at the init slot (push_ptr_init is a
         -- signature classification, mirrors mem_predec/restore_fire).
         if push_ptr_init = '1' then
           push_ptr_r <= arith_out(31 downto 0);
         end if;
         -- Track in-flight push: set at init, cleared at the terminal R15
         -- commit; else (a committing slot that is neither init, store, nor
         -- terminal) clear as the abnormal-exit guard -- a push abandoned
         -- mid-store by an exception/interrupt redirect would otherwise leak
         -- push_active_r='1' into the handler and misroute its SP-relative
         -- store. Set wins if init and term somehow coincide.
         if push_ptr_init = '1' then
           push_active_r <= '1';
         elsif push_ptr_term = '1' then
           push_active_r <= '0';
         elsif push_ptr_store = '0' then
           push_active_r <= '0';
         end if;
       end if;
     end if;
   end process;
 -- push_ptr_store: each MOVML.L Rm,@-R15 store-loop slot (R(idx) @ push_ptr+
 -- idx*4: ADD, xbus=R15, UH*4 immediate, memory WRITE, no GPR commit). Qualified
 -- by push_active_r (set at init, cleared at the terminal) instead of
 -- pc_ctrl.inc='0': the address signature alone is identical to an ordinary
 -- MOV.L Rm,@(disp,R15), AND on the LAST store the decode_core loop releases
 -- pc-hold so pc_ctrl.inc glitches to '1'. push_active_r is uniform across all
 -- m+1 stores and is only ever set inside a push, so it excludes ordinary
 -- SP-relative stores.
   push_ptr_store <= '1' when func.alu.iny_sel = SEL_IMM
                            and func.arith.func = ADD and mem.issue = '1'
                            and mem.wr = '1' and reg.wr_z = '0'
                            and push_active_r = '1'
                            and buses.x_sel = SEL_REG and num_x_r = "01111"
                   else '0';
   xbus <= push_ptr_r when push_ptr_store = '1' else xbus_mux;
end generate;
g_push_off : if not SH2A_ARCH generate
   xbus <= xbus_mux;
end generate;
-- SH-2A CS (SR bit 2, CLIPS/CLIPU saturation, sticky-OR). Deliberately kept
-- outside sr_t/datapath_reg_t ("this") -- see the note on sr_t in
-- core/components_pkg.vhd and the push_ptr_init/store/term precedent above:
-- widening the shared register-variable record perturbed the base J2
-- techmap by ~+400 cells even though the added field was SH2A_ARCH-gated.
-- This mirrors g_push/g_push_off's xbus mux instead: sr_cs is a small
-- standalone register, muxed into the STC SR read value via to_slv(sr,cs).
-- Updated on the committed slot (slot_o), same cadence as "this": LDC Rm,SR
-- (sr_ctrl.sel=SEL_WBUS/SEL_ZBUS) loads bit CS verbatim; CLIPS/CLIPU (which
-- use sr_ctrl.sel=SEL_PREV) OR in the saturation instead.
g_cs : if SH2A_ARCH generate
  process(clk, rst)
  begin
    if rst = '1' then
      sr_cs <= '0';
    elsif clk = '1' and clk'event then
      if slot_o = '1' then
        if sr_ctrl.sel = SEL_WBUS then
          sr_cs <= wbus(CS);
        elsif sr_ctrl.sel = SEL_ZBUS then
          sr_cs <= zbus(CS);
        elsif func.alu.manip = CLIP_SB or func.alu.manip = CLIP_SW or
              func.alu.manip = CLIP_UB or func.alu.manip = CLIP_UW then
          sr_cs <= sr_cs or clip_saturated(xbus, func.alu.manip);
        end if;
      end if;
    end if;
  end process;
  sr_slv <= to_slv(sr, sr_cs);
end generate;
g_cs_off : if not SH2A_ARCH generate
  sr_cs <= '0';
  sr_slv <= to_slv(sr); -- byte-identical to master's STC SR read
end generate;
-- SH-2A MULR MAC save/restore shadow registers. mulr R0,Rn computes
-- R0*Rn->Rn using the multiplier, which uses MACH:MACL as its own working
-- accumulator -- so mulr must save MAC to these shadow registers before the
-- multiply and restore it afterward. Captured on the committed slot
-- (slot_o), same cadence as sr_cs above, when func.alu.manip = MAC_SAVE.
-- Restore is routed separately via manip_sel (SEL_MANIP mux) below.
g_macsh : if SH2A_ARCH generate
  process(clk, rst)
  begin
    if rst = '1' then
      mac_shadow_h <= (others => '0');
      mac_shadow_l <= (others => '0');
    elsif clk = '1' and clk'event then
      if slot_o = '1' and func.alu.manip = MAC_SAVE then
        mac_shadow_h <= mach;
        mac_shadow_l <= macl;
      end if;
    end if;
  end process;
end generate;
g_macsh_off : if not SH2A_ARCH generate
  mac_shadow_h <= (others => '0');
  mac_shadow_l <= (others => '0');
end generate;
-- SH-2A DIVU/DIVS operand/start routing (Task 2). The divider unit itself
-- lives in cpu.vhd (like u_mult); this just drives its inputs from the
-- xbus/ybus register reads already set up by the instruction's slot0
-- (xbus=Rn dividend, ybus=R0 divisor) and pulses start for exactly the one
-- cycle slot0 is committed (slot_o='1'), same cadence as sr_cs/mac_shadow
-- above. func.alu.manip = DIV_START_U/DIV_START_S is a decode-time marker
-- only slot0 of DIVU/DIVS ever emits; is_signed picks DIVS vs DIVU.
g_div : if SH2A_ARCH generate
  div_dividend <= xbus;
  div_divisor <= ybus;
  div_start <= slot_o when (func.alu.manip = DIV_START_U or
                                 func.alu.manip = DIV_START_S) else '0';
  div_is_signed <= '1' when func.alu.manip = DIV_START_S else '0';
end generate;
g_div_off : if not SH2A_ARCH generate
  div_dividend <= (others => '0');
  div_divisor <= (others => '0');
  div_start <= '0';
  div_is_signed <= '0';
end generate;
 -- SH-4 register-bank remap on the four address ports; pass-through on J2.
 num_x_r <= bank_remap(reg.num_x, sr.md, sr.rb) when PRIV_ARCH else reg.num_x;
 num_y_r <= bank_remap(reg.num_y, sr.md, sr.rb) when PRIV_ARCH else reg.num_y;
 -- num_z_r is assigned in the g_restore2 / g_restore2_off branches below
 -- (it selects the restore2_* entry, which must not exist on J1/J2).
 num_w_r <= bank_remap(reg.num_w, sr.md, sr.rb) when PRIV_ARCH else reg.num_w;
 -- Bank-remap the dedicated R0-index read port too (drives dout_0); pass-through
 -- (bank-0 R0) on J2, so mov.l @(R0,Rn) uses the correct R0 under SR.RB=1.
 num_0_r <= bank_remap("00000", sr.md, sr.rb) when PRIV_ARCH else "00000";
 -- Suppress memory-load writeback retirement while a TLB fault is pending
 -- entry, so the load instruction(s) behind the faulting access cannot
 -- corrupt its operands before the precise restart (J4 only;
 -- pass-through otherwise). BOTH ports are gated:
 -- * we_wb (writeback): plain MOV @Rm+ et al. retire their loaded value
 -- here a slot late, in the fault shadow -- suppressed. Faulting @-Rn
 -- pre-decrement STORES (STS.L/STC.L/MOV.L Rm,@-Rn) carry the SYMMETRIC
 -- base-decrement hazard and are now handled by the restore path too
 -- (mem_predec / ma_base: the captured pre-decrement base is rewritten to
 -- Rn on the fault, so the RTE-restart decrements exactly once). The store
 -- itself issues no GPR writeback, so only the base restore is needed here.
 -- * we_ex (EX z-port): the co-located single-base LDS.L/LDC.L/MAC @Rm+
 -- forms place their base post-increment (ADD, z-port) in slot1, AFTER the
 -- faulting slot0 read -- i.e. IN the fault shadow. tlb_squash must also
 -- gate this z-write, else the base double-increments after RTE
 -- re-executes both slots.
 -- NOTE -- MAC.L/W @Rm+,@Rn+ is a DUAL-base form and needs TWO restore
 -- entries, not one. Its two post-increment operand reads issue in
 -- successive EX slots; on a fault at the SECOND read the FIRST read's
 -- base bump has ALREADY committed while the second's is correctly
 -- squashed, so the single mem_autoinc1 entry (1d5064a) restored the
 -- faulting access's own base -- which needed no restoring -- and left the
 -- first base at +size, which the RTE-restart then bumped again to +2*size.
 -- An earlier revision of this comment claimed both bases were already
 -- precise; that was true only ACCIDENTALLY, because the then-broken
 -- D-side restart PC landed four bytes early and re-executed the
 -- constant-pool loads that happened to reload both bases. Correcting the
 -- restart PC (ex_if_pc derivation, above) unmasked it. The restore now
 -- carries a SECOND entry (g_restore2 / restore2_fire below): the MAC
 -- first-operand read's ACCESS LAUNCH latches its (base register,
 -- pre-increment base = xbus) -- the same pipeline point at which
 -- ma_numz/ma_base are shadowed, which is what makes it correct when the
 -- fault surfaces a slot later -- a fault on the MAC second-operand
 -- access arms it, and it commits
 -- on the first eligible EX-write slot AFTER the first entry has fired --
 -- both entries use the reg.wr_z='0' rule, so neither can collide with the
 -- exception entry's SPC/SSR saves on the shared EX write port.
 -- The other defect of this instruction was the MULTIPLY-ACCUMULATE: the MACH:MACL accumulate
 -- (mult.vhd, wr_mach/wr_macl via code.mach_en) re-applied on every
 -- fault-restart and was neither squashed nor rolled back. Measured for
 -- 0xA11C0001^2 = P, pre-fix: 0 faults (warm) -> 1*P; one operand cold ->
 -- 2*P; both cold -> 3*P, i.e. one extra accumulate per faulting operand
 -- read. FIX (M8 4th class): tlb_squash is exported as tlb_squash_o and
 -- feeds mult's acc_squash; the mult latches it for the in-flight MAC
 -- sequence (the pulse drops ~1 cycle before the MACL1/MACL2 commit) so the
 -- faulting pass commits NOTHING and the clean restart accumulates exactly
 -- once -> 1*P at every position. REGRESSION-LOCKED: the m8_dside MAC.L/W
 -- cases now run all three fault positions (operand-1-only, operand-2-only,
 -- both-cold) as separate precise self-checks, and m8_macseq proves a clean
 -- MAC after a faulting MAC accumulates exactly once (acc_sq re-samples at
 -- dispatch; the squash does not linger). MAC arithmetic on a clean op is
 -- unaffected -- the squash never arms without a fault (m8_macarith).
 -- The ONLY legitimate shadow z-writes are the exception-entry
 -- system-register saves SPC(21)/SSR(22) -- regfile "10xxx" -- which are
 -- exempted so RTE still restores the correct SR/PC. The precise
 -- auto-increment restore (restore_fire, 1d5064a) overrides on top and is
 -- never squashed (it IS the corrective base write).
 -- exemption = num_z_r(4 downto 3) = "10" (system regs 16-23: SPC=21,SSR=22),
 -- expressed bit-wise to stay in std_logic for the squash term.
 -- CAVEAT -- this is COARSE: "10" exempts the entire reg-16..23 block, not just
 -- SPC(21)/SSR(22). A shadow instruction writing any reg 16-23 via the EX
 -- z-port (e.g. a trailing LDC Rm,<sysreg>) would be wrongly exempted and
 -- commit non-precisely. Accepted -- strictly better than the pre-fix (no
 -- we_ex squash at all) and the exposure window is only 1-2 slots.
 -- reg_wr_z_g is assigned in the g_restore2 / g_restore2_off branches below
 -- (it ORs in restore2_fire, which must not exist on J1/J2).
 -- PROGRAM-ORDER RULE for the w-port squash (J4+PRIV_ARCH).
 --
 -- Precise-exception semantics: instructions OLDER than the faulting access
 -- must COMMIT; only YOUNGER ones may be discarded. The squash above is a
 -- pure time-window test with no age term, so on its own it also discards
 -- the retirement of the instruction that was already presenting its w-port
 -- writeback when the fault armed -- an instruction that is necessarily
 -- older. (Observed on mmustr2.S: mov.l c_sval2,r11 presents we_wb=1,
 -- w_addr_wb=0xb at 460000000 fs, tlb_squash arms at 470000000 fs and forces
 -- we_wb to 0, and the commit edge lands at 480000000 fs -- R11 is never
 -- written.) The z-port needs no such term: it retires IN-slot, so its
 -- shadow correctly starts immediately. Only the w-port is offset, retiring
 -- a slot late by construction (see the comment above reg_wr_z_g).
 --
 -- WHY ONE BIT IS ENOUGH -- do NOT "simplify" this back into a time window,
 -- and do not reach for a per-instruction age tag. Only ONE memory
 -- transaction can be outstanding: a new one starts only when
 -- this.data_o.en = '0' (see "start new memory transactions" below) and the
 -- pipeline does not advance while one is in flight (the slot-advance
 -- condition requires this.data_o.en = '0' as well). A fault therefore always
 -- arises from an access that began AFTER the previous access acked, so
 -- (a) any w-port writeback pending when the squash arms is necessarily
 -- OLDER than the faulting access, and
 -- (b) the faulting instruction contributes no w-port writeback of its own
 -- (a faulting load returns no data; a store writes no GPR).
 -- Hence exactly one post-arm w-port commit must be admitted, and a single
 -- one-shot bit expresses that exactly.
 --
 -- The bit is set at the arming edge iff a w-port writeback is pending and
 -- is not already committing on that same edge (slot_o = '1' means it
 -- commits now, ungated, because tlb_squash only becomes visible next
 -- cycle -- no grace needed). It is cleared on the first slot boundary
 -- thereafter, which IS that writeback's commit edge; while the slot is
 -- stretched (slot_o = '0') the pipeline is frozen, so reg.wr_w/num_w_r are
 -- held and the bit correctly persists.
 --
 -- AGE RULE. The squash window discards the work of instructions the restart
 -- WILL RE-EXECUTE. It is a pure time test with no age term, so on its own it
 -- also discards instructions that are architecturally OLDER than the fault
 -- and will never re-run -- their writes are then lost forever (Defect 6).
 -- The exemptions below supply the missing age information. The fault SIDE is
 -- what decides it, and exactly rather than approximately:
 -- * D-SIDE fault: the faulting access belongs to an instruction the restart
 -- re-executes (itself, or the branch when it sits in a delay slot), so
 -- its writeback and anything younger MUST be suppressed.
 -- * I-SIDE fault (IMISS/IPROT/MULTI_HIT): the instruction at the faulting
 -- VA never entered the pipeline, so nothing younger is in flight and
 -- EVERY write present in the window is older and must commit.
 -- squash_ifetch_r carries that side; see its declaration near squash_arm.
 g_wb_grace : if PRIV_ARCH generate
   -- Generate-local so J1/J2 elaborate with no trace of it (see the note at
   -- the declaration site above for why "tied off at architecture scope" is
   -- not good enough).
   signal wb_grace : std_logic;
 begin
   process(clk, rst)
   begin
     if rst = '1' then
       wb_grace <= '0';
     elsif clk = '1' and clk'event then
       if tlb_squash_r = '0' and squash_arm = '1' then
         -- squash arms on this edge -- squash_arm is the SHARED predicate
         -- also consumed by the tlb_squash arming in the process, so the
         -- two can no longer drift apart (see squash_arm's declaration).
         wb_grace <= reg.wr_w and not slot_o;
       elsif slot_o = '1' then
         wb_grace <= '0';
       end if;
     end if;
   end process;
   -- UNION of two exemptions, not one:
   -- wb_grace D-side. The w-port retires a slot LATE, so on a D-side
   -- fault a writeback OLDER than the faulting access is
   -- still in flight when the window arms. One bit suffices
   -- (only one memory transaction outstanding -- see above).
   -- mmustr2 is the guard for this term.
   -- squash_ifetch_r I-side. The instruction at a faulting FETCH VA never
   -- entered the pipeline, so NOTHING younger is in flight:
   -- every writeback in the window is older and must commit,
   -- not just the one pending at the arming edge. This is
   -- the term wb_grace never had -- the gap its own comment
   -- documented -- and being non-one-shot it also lifts the
   -- old "depth > 1 is uncovered" cap on that side.
   reg_wr_w_g <= reg.wr_w and (not this_r.tlb_squash
                               or wb_grace or squash_ifetch_r);
 end generate;
 g_wb_grace_off : if not PRIV_ARCH generate
   reg_wr_w_g <= reg.wr_w;
 end generate;
 -- SECOND base-restore entry for the DUAL-base MAC.L/W @Rm+,@Rn+ (see the
 -- NOTE above reg_wr_z_g). The microcode is, per decode/gen-go/spec:
 -- slot0: READ @Rn (ma_addy=XBUS, ARITH ADD), Rn := Rn+size on the z-port,
 -- pc = HOLD
 -- slot1: READ @Rm (ma_addy=XBUS, ARITH ADD), Rm := Rm+size on the z-port
 -- Both slots therefore match mem_autoinc1 (single-slot @Rm+: the base bump
 -- commits in the very slot that reads), and they are CONSECUTIVE slots of ONE
 -- instruction.
 --
 -- CRITICAL ALIGNMENT (measured on the m8_macseq VCD, and the reason two
 -- earlier shapes of this detector were wrong): the entry must be keyed to the
 -- ACCESS-LAUNCH pipeline point, exactly like this.ma_numz/ma_base/ma_autoupd
 -- are, NOT to the EX slot presented when the fault arrives. A D-side fault is
 -- reported one or more cycles AFTER its access launched, by which time the
 -- pipeline is already presenting the NEXT slot -- so on a fault taken on MAC
 -- slot0's access, slot1 is the slot on screen and any "is the current slot the
 -- second operand?" test mis-fires. (Keying off the mac_ctrl_t fields
 -- macin_1/macin_2/latch_s_mac is wrong for a second reason: those are
 -- WB-stage aligned, and mac.sel1=SEL_WBUS never coincides with the
 -- mem_autoinc1 EX slot it belongs to.)
 --
 -- So: the entry is keyed to ma_launch, which the datapath process asserts at
 -- the very statement that writes this.ma_numz/ma_base/ma_if_pc (see the
 -- ma_launch declaration for why it is exported from inside the process rather
 -- than reconstructed outside it). At each launch the shadow of the PREVIOUS
 -- access shifts in:
 -- op1_reg_r/op1_val_r <- this_r.ma_numz / ma_base, which still hold
 -- the previous access's base register and its PRE-increment value (ma_base
 -- is xbus, the register read of the access slot, sampled before that
 -- slot's own z-write commits) -- they are overwritten by this same edge.
 -- ainc_pre_r <- whether that previous access was an mem_autoinc1 read.
 -- The arm then also requires prev_ok: the two accesses were issued by the
 -- same instruction, decided by comparing ex_if_pc one cycle after each launch
 -- (epc_r / prev_ok_r / the prev_ok bypass, below).
 --
 -- Only MAC.L/W and RTE issue two mem_autoinc1 accesses under one ex_if_pc;
 -- every other post-increment form (LDS.L/LDC.L @Rm+, MOV.* @Rm+) issues at
 -- most one per instruction, so back-to-back
 -- LDS.L @Rm+,MACH / LDS.L @Rm+,MACL cannot pair up. RTE qualifying is
 -- correct, not a false positive -- its two @R15+ pops carry the identical
 -- hazard, and a fault on the second one must undo the first pop's R15 bump
 -- for the restart to be precise. (In practice RTE runs with SR.RB=1, which
 -- squash_arm already excludes, so the path is unexercised.)
 --
 -- pc_ctrl.inc is NOT usable as the "does this slot end the instruction?"
 -- term, which is what an earlier shape of this detector tried. TWO separate
 -- reasons, neither of them a spec/decoder discrepancy:
 -- 1. MAC.L and MAC.W are ASYMMETRIC in the spec. MAC.L is HOLD/HOLD/INC
 -- over three slots; MAC.W is HOLD/INC over two, so MAC.W's SECOND
 -- operand read IS its terminal slot. A "previous slot was non-terminal"
 -- test therefore fixes MAC.L (case 1008) and can never fix MAC.W
 -- (case 1009). decode_table_simple.vhd agrees with the spec exactly:
 -- under -- MAC.W @Rm+, @Rn+ [400F], slot x"0" has no id.incpc while
 -- slot x"1" has id.incpc <= '1' and dispatch <= '1'.
 -- 2. pc_ctrl.inc originates as the decoder's id.incpc and is ID-STAGE
 -- aligned, so it is no more EX-aligned with the memory slot than the
 -- mac_ctrl_t fields rejected above are. While MAC.W slot0's access is
 -- stalled in EX, ID is already presenting slot1, which legitimately
 -- asserts incpc -- which is what the earlier measurement of inc='1'
 -- "on MAC.W slot0" actually was. Same alignment trap, third instance.
 -- ex_if_pc, by contrast, is the EX-aligned per-instruction fetch PC, and was
 -- measured constant (0x80000b58) across MAC.W's two operand slots, its fault
 -- and its restart, and distinct for every neighbouring instruction. That is
 -- why it, and not any slot-terminality signal, is the discriminator here.
 g_restore2 : if MMU_ARCH generate
   -- "the previous access was issued by the same instruction as this one".
   -- Broken out so it is directly observable in a waveform.
   signal same_insn : std_logic;
   -- same_insn with the one-cycle bypass applied -- see prev_ok_r below.
   signal prev_ok : std_logic;
   signal launch_d_r : std_logic := '0';
   signal ainc_r : std_logic := '0';
   signal ainc_pre_r : std_logic := '0';
   signal prev_ok_r : std_logic := '0';
   signal epc_r : std_logic_vector(31 downto 0) := (others => '0');
   signal op1_reg_r : std_logic_vector(4 downto 0) := (others => '0');
   signal op1_val_r : std_logic_vector(31 downto 0) := (others => '0');
   signal pend2_r : std_logic := '0';
   -- The entry itself. Generate-local so it leaves no dangling wire bits on
   -- J1/J2 (see the note at the declaration site above).
   signal restore2_fire : std_logic;
   signal restore2_reg : std_logic_vector(4 downto 0);
   signal restore2_val : std_logic_vector(31 downto 0);
 begin
   -- The three consumers live here rather than at architecture scope so that
   -- the restore2_* operands can be generate-local.
   gpf_zwd <= this_r.tlb_restore_val when restore_fire = '1'
              else restore2_val when restore2_fire = '1'
              else pc when pc_ctrl.wrpr = '1' else zbus;
   num_z_r <= this_r.tlb_fault_zreg when restore_fire = '1'
              else restore2_reg when restore2_fire = '1'
              else bank_remap(reg.num_z, sr.md, sr.rb) when PRIV_ARCH
              else reg.num_z;
   -- Same age rule as the w-port, minus the wb_grace term: the z-port retires
   -- IN-slot, so its shadow starts immediately and there is no late-retiring
   -- older write to rescue -- squash_ifetch_r is the whole rule here. It
   -- replaces z_grace (`tlb_exc_ifetch and not delay_slot'); the
   -- `not delay_slot' half is dropped because its own COVERAGE WARNING
   -- recorded that removing it changed no guard's verdict, and on an I-side
   -- delay-slot FETCH fault the branch that does re-run has at most BSR/JSR's
   -- PR write, recomputed from the same PC and hence idempotent.
   -- The num_z_r "10xxx" term stays: the exception entry's own SPC/SSR saves
   -- must commit regardless of fault side.
   reg_wr_z_g <= (reg.wr_z and (not this_r.tlb_squash or squash_ifetch_r
                                or (num_z_r(4) and not num_z_r(3))))
                 or restore_fire or restore2_fire;
   -- epc_r holds the SETTLED ex_if_pc of the most recent access, so on the
   -- launch_d cycle of access k this compares instruction(k) against
   -- instruction(k-1). One cycle later epc_r has moved on and prev_ok_r
   -- carries the result, hence the bypass below.
   same_insn <= '1' when ex_if_pc = epc_r else '0';
   -- The fault is reported at the earliest ONE cycle after the launch, which
   -- is exactly the launch_d cycle (measured: m8_macseq, launch 7040ns, arm
   -- 7050ns). On that cycle prev_ok_r has not been clocked yet, so the arm
   -- must see the combinational comparison instead. This bypass is what lets
   -- the result be kept as ONE bit rather than a second 32-bit shadow of the
   -- previous access's PC.
   prev_ok <= same_insn when launch_d_r = '1' else prev_ok_r;
   -- WHY epc_r EXISTS AND ma_if_pc CANNOT REPLACE IT. datapath_reg_t already
   -- carries ma_if_pc, an access-launch-aligned shadow of ex_if_pc that this
   -- task left with no readers, and it looks like exactly the register needed
   -- here. It is not. ma_if_pc stores the LAUNCH-TIME ex_if_pc, and the
   -- launch-time value is precisely the one that is unusable: the comment on
   -- the D-fault restart PC above already records that "how far ex_if_pc has
   -- advanced by then depends on the addressing mode", and it is worse than
   -- biased at an instruction handover. MEASURED (m8_macseq, the RTE-restart
   -- launch at 7020ns): the launch-time value was 0x8000066e -- still the
   -- handler -- while the launch belonged to the MAC at 0x800006d2. Keying on
   -- it reproduces exactly the mispairing that left case 1009 failing. The
   -- SETTLED (launch + 1) sample is required, and the process cannot produce
   -- one without a new one-bit delay field in datapath_reg_t, i.e. widening
   -- the shared record -- which is exactly what this block exists to avoid.
   -- Collapsing epc_r to a one-bit "an instruction boundary passed since the
   -- previous launch" predicate was also considered: the only EX-aligned
   -- boundary event available is a CHANGE in ex_if_pc, detecting which needs
   -- ex_if_pc registered anyway, so it costs 32 + 2 bits instead of 32 + 1.
   -- 74 flops (op1_val_r 32, epc_r 32, op1_reg_r 5, and 5 control bits) is
   -- therefore the floor for this mechanism given the available signals.
   -- Fire on the first committed slot after the FIRST entry has retired
   -- (this_r.tlb_restore_pend = '0') on which the microcode is not
   -- itself driving the z-write port -- identical to restore_fire's rule, so
   -- this second commit is equally clear of the exception entry's
   -- slot0/slot1 SPC(21)/SSR(22) saves (those carry reg.wr_z='1').
   restore2_fire <= '1' when pend2_r = '1'
                             and this_r.tlb_restore_pend = '0'
                             and reg.wr_z = '0' and slot_o = '1'
                    else '0';
   restore2_reg <= op1_reg_r;
   restore2_val <= op1_val_r;
   process(clk, rst)
   begin
     if rst = '1' then
       op1_reg_r <= (others => '0');
       op1_val_r <= (others => '0');
       ainc_r <= '0';
       ainc_pre_r <= '0';
       prev_ok_r <= '0';
       epc_r <= (others => '0');
       launch_d_r <= '0';
       pend2_r <= '0';
     elsif clk = '1' and clk'event then
       if ma_launch = '1' then
         -- Shift the previous access's shadow in before the process
         -- overwrites it on this same edge (signal semantics: every read
         -- below sees the pre-edge value).
         op1_reg_r <= this_r.ma_numz;
         op1_val_r <= this_r.ma_base;
         ainc_pre_r <= ainc_r;
         ainc_r <= mem_autoinc1;
       end if;
       -- ex_if_pc is sampled ONE CYCLE AFTER the launch, not at it. Measured
       -- (m8_macseq VCD, the RTE-restart launch at 7020ns): on the cycle a new
       -- instruction takes over, ex_if_pc is still transitioning at that edge,
       -- so a flop clocked by ma_launch captures the PREVIOUS instruction's PC
       -- while the launch belongs to the new one. Sampling both accesses one
       -- cycle late compares like with like: the two MAC operand accesses then
       -- yield the same value, whereas two back-to-back single-access
       -- instructions (LDS.L @Rm+,MACH ; LDS.L @Rm+,MACL) yield different ones.
       -- Accesses are never closer than two cycles apart, so this never races
       -- the next launch.
       launch_d_r <= ma_launch;
       if launch_d_r = '1' then
         prev_ok_r <= same_insn;
         epc_r <= ex_if_pc;
       end if;
       -- Arm on the SHARED squash-arming edge (the first fault cycle) when the
       -- FAULTING access is a post-increment whose instruction already
       -- committed an earlier operand's base bump. D-side faults only:
       -- ma_numz/ma_base/ma_autoupd are stale on an I-fetch fault.
       if tlb_squash_r = '0' and squash_arm = '1' then
         pend2_r <= ainc_pre_r and prev_ok and this_r.ma_autoupd
                    and (not tlb_exc_ifetch);
       elsif restore2_fire = '1' then
         pend2_r <= '0';
       end if;
     end if;
   end process;
 end generate;
 g_restore2_off : if not MMU_ARCH generate
   gpf_zwd <= pc when pc_ctrl.wrpr = '1' else zbus;
   num_z_r <= bank_remap(reg.num_z, sr.md, sr.rb) when PRIV_ARCH
                 else reg.num_z;
   reg_wr_z_g <= reg.wr_z;
 end generate;
 -- J1 early-read addresses (architecture(ebr) reads on rising edge); zero on J2/J4.
 num_x_early_r <= reg.num_x_early when EARLY_REGFILE_READ else (others => '0');
 num_y_early_r <= reg.num_y_early when EARLY_REGFILE_READ else (others => '0');
 u_regfile : register_file
          generic map (ADDR_WIDTH => 5,
                       NUM_REGS => REGFILE_DEPTH,
                       REG_WIDTH => 32,
                       BANKED => PRIV_ARCH)
          port map(clk => clk, rst => rst, ce => slot_o, addr_ra => num_x_r, dout_a => reg_x,
                   addr_ra_early => num_x_early_r,
                   addr_rb_early => num_y_early_r,
                   addr_rb => num_y_r, dout_b => reg_y, dout_0 => reg_0,
                   addr_r0 => num_0_r,
                   we_wb => reg_wr_w_g, w_addr_wb => num_w_r, din_wb => wbus,
                   we_ex => reg_wr_z_g, w_addr_ex => num_z_r, din_ex => gpf_zwd,
                   wr_data_o => reg_wr_data_o);
-- setup arithmetic inputs function
 with func.alu.inx_sel select
   aluinx <= xbus(31 downto 2) & "00" when SEL_FC,
             xbus(30 downto 0) & sr.t when SEL_ROTCL, -- used for DIV1
                    (others => '0') when SEL_ZERO,
                    xbus when others;
 with func.alu.iny_sel select
   aluiny <= buses.imm_val when SEL_IMM,
             reg_0 when SEL_R0,
      ybus when others;
        -- DIV1 decides the arith function at runtime based on m=q. Override
        -- the arith func set by decoder when DIV1.
        div1_arith_func <= SUB when sr.m = sr.q else ADD;
        arith_func <= div1_arith_func when func.arith.sr = DIV1 else func.arith.func;
        -- J1/iCESugar DSP-ALU prototype: when DSP_ALU is set, offload the
        -- arith_unit add/sub computation onto an SB_MAC16 DSP block
        -- (core/dsp_arith.vhd) instead of LUT adder logic. Bit-for-bit
        -- equivalence with arith_unit is proven by
        -- components/cpu/tests/dsp_arith_tap.vhd. Default (DSP_ALU=false)
        -- keeps the original arith_unit call unchanged, so J2/J4/sim VHDL
        -- is byte-identical to before this prototype.
        dsp_alu_gen: if DSP_ALU generate
          signal dsp_arith_result : std_logic_vector(32 downto 0);
          signal dsp_is_sub : std_logic;
          signal dsp_ci : std_logic;
        begin
          dsp_is_sub <= '1' when arith_func = SUB else '0';
          dsp_ci <= func.arith.ci_en and sr.t;
          u_dsp_arith : dsp_arith
            port map (
              clk => clk,
              a => aluinx,
              b => aluiny,
              is_sub => dsp_is_sub,
              ci => dsp_ci,
              result => dsp_arith_result);
          arith_out <= dsp_arith_result;
        end generate dsp_alu_gen;
        no_dsp_alu_gen: if not DSP_ALU generate
          arith_out <= arith_unit(aluinx, aluiny, arith_func, func.arith.ci_en and sr.t);
        end generate no_dsp_alu_gen;
        logic_out <= logic_unit(aluinx, aluiny, func.logic_func);
        -- SH-2A MULR restore-route: manip_sel is the SEL_MANIP zbus/zbus_mac
        -- source. On restore (MAC_RESTORE_L/H) it drives the corresponding
        -- MAC shadow register instead of manip(...)'s result; the restore
        -- slot itself sets mac.sel2=SEL_ZBUS/mac.wrmacl (resp.
        -- mac.sel1/wrmach) so MACL/MACH := shadow via the existing MAC write
        -- path (see mach/macl accumulate-commit note above). On base,
        -- g_msel_off makes manip_sel exactly manip(xbus, ybus, sr.t,
        -- func.alu.manip, false) -- logically byte-identical to master.
        g_msel : if SH2A_ARCH generate
          manip_sel <= mac_shadow_l when func.alu.manip = MAC_RESTORE_L else
                       mac_shadow_h when func.alu.manip = MAC_RESTORE_H else
                       div_quotient when func.alu.manip = DIV_READ else
                       manip(xbus, ybus, sr.t, func.alu.manip, true);
        end generate;
        g_msel_off : if not SH2A_ARCH generate
          manip_sel <= manip(xbus, ybus, sr.t, func.alu.manip, false);
        end generate;
        -- manip()'s "t" (sr.t) parameter feeds the SH-2A BST #imm3,Rn
        -- BITSET alumanip_t case (single-cycle variable-position T-bit
        -- insert; see core/components_pkg.vhd manip() and
        -- decode/gen-go/spec/sh2a/bit.toml). Reuses the existing
        -- zbus_sel=SEL_MANIP path -- no zbus_sel_t enum widening, so base
        -- J1/J2/J4 decode_pkg.vhd output is unaffected.
        with buses.z_sel select zbus <=
          arith_out(31 downto 0) when SEL_ARITH,
          logic_out when SEL_LOGIC,
          shift_y when SEL_SHIFT,
          manip_sel when SEL_MANIP,
          ybus when SEL_YBUS,
          wbus when SEL_WBUS;
        -- The multiplier operand mux (macin1/macin2) reads zbus only on
        -- SEL_ZBUS, and no instruction ever co-asserts mac.sel=SEL_ZBUS with
        -- z_sel=SEL_SHIFT: the only ZBUS-sourced multiplier reads are CLRMAC
        -- (z_sel=SEL_LOGIC) and LDS Rm,MAC{H,L} (z_sel=SEL_YBUS); shift ops leave
        -- mac.sel at its WBUS default. So the shifter output can never reach the
        -- multiplier input in a single cycle. Feeding macin a zbus *view* with
        -- the SEL_SHIFT source replaced by a don't-care is therefore exactly
        -- equivalent, and it removes a large FALSE timing path
        -- (regfile->shifter->zbus->macin->mult.rin) that otherwise dominates the
        -- reported iCE40 Fmax. Keeping the other five sources (rather than a lean
        -- 2-way logic_out/ybus mux) lets the ECP5 abc9 timing-driven flow keep the
        -- multiplier-input path fast -- the lean form pulls the late logic_out
        -- signal into the mult cone and regresses the ECP5 representative Fmax.
        -- Logically identical for every variant.
        with buses.z_sel select zbus_mac <=
          arith_out(31 downto 0) when SEL_ARITH,
          logic_out when SEL_LOGIC,
          (others => '-') when SEL_SHIFT,
          manip_sel when SEL_MANIP,
          ybus when SEL_YBUS,
          wbus when SEL_WBUS;
 -- Shifter: shift_b is {direction, magnitude[4:0]} = ybus(31) & ybus(4..0).
 -- shift_sel ('1' when this EX op is a shift) gates shifter(seq)'s accept;
 -- shifter(seq) busy stretches the slot below (multi-cycle hold). `start`
 -- (=slot_o) is unused by both architectures today (reserved). shift_y feeds
 -- zbus on SEL_SHIFT; t_out is the shifted-out bit captured into sr.t (was
 -- sfto) -- only single-bit shifts set sr.t, so it matters only for cnt<=1.
 shift_b <= ybus(31) & ybus(4 downto 0);
 shift_sel <= '1' when buses.z_sel = SEL_SHIFT else '0';
 u_shifter : shifter port map (
   clk => clk, rst => rst, start => slot_o, sel => shift_sel,
   a => xbus, b => shift_b,
   t_in => sr.t, op => func.shift,
   y => shift_y, t_out => sfto, busy => shift_busy);
 with mac.sel1 select macin1 <= xbus when SEL_XBUS, zbus_mac when SEL_ZBUS, wbus when others;
 with mac.sel2 select macin2 <= ybus when SEL_YBUS, zbus_mac when SEL_ZBUS, wbus when others;
 ibit <= sr.int_mask;
 datapath : process(this_r,pc_ctrl,wbus,zbus,sr_ctrl, xbus, ybus, mac,mem, instr, db_i, inst_i, debug, debug_i,reg_wr_data_o, logic_out, arith_out, arith_func, func, sfto, coproc, cop_i, shift_busy, mult_stall, tlb_exc_pend, squash_arm, tlb_fault_va, tlb_exc_expevt, tlb_exc_fsr, reg, num_x_r, mem_autoupd, mem_autoinc1, mem_predec, restore_fire, delay_slot, inst_fault, tlb_exc_is_i, tlb_exc_ifetch, ex_if_pc)
   variable this : datapath_reg_t;
          variable if_ad : std_logic_vector(31 downto 0);
          variable ma_ad, ma_dw : std_logic_vector(31 downto 0);
          variable seg_v : segment_t;
          variable p4_sel_v : p4_sel_t;
          -- TSB pointer-assist hash (M5): computed on the first fault cycle.
          variable v_vpn : unsigned(31 downto 0);
          variable v_hash : unsigned(31 downto 0);
          variable v_mask : unsigned(31 downto 0);
          variable v_idx : unsigned(31 downto 0);
          variable v_shift : integer range 0 to 31;
          variable v_size : integer range 0 to 31;
          variable next_state : debug_state_t;
          variable slot_inst_en : std_logic;
        begin
           this := this_r;
          this.debug_o.ack := '0';
          -- Default for the access-launch export (see the ma_launch declaration);
          -- overridden to '1' at the single statement that writes the ma_* shadow.
          ma_launch <= '0';
          -- TLB fault hardware side-effects (J4): on the first cycle a
          -- fault is detected (tlb_exc_pend='1') capture TEA and PTEH[31:14] from
          -- the faulting VA. Done at the top of the process (not gated by a slot
          -- boundary) so the capture window cannot be missed. EXPEVT is NOT
          -- captured here (it would not persist past the handler prologue) -- it
          -- is latched via a slot-gated sr="EXPEVT" microcode write in the TLB
          -- exception microcode. S-I5 invariant: MULTI_HIT sets tlb_exc_pend
          -- (so TEA/PTEH are still captured here for postmortem) but decode_core.vhm
          -- dispatches it to system_op(GENERAL_ILLEGAL), never to a TLB_* system_op,
          -- so this TLB-exception-microcode EXPEVT write never fires for it; EXPEVT=0x180
          -- comes solely from the General-Illegal microcode's own write. The two
          -- writes are mutually exclusive by system_op dispatch (one op/cycle), so
          -- there is no race.
          -- Capture only on the FIRST cycle of a fault episode (tlb_exc_captured
          -- still '0'). The D-side holds the faulting access steady, but the
          -- I-fetch stream advances a word while an IMISS persists, so capturing
          -- every cycle would latch the second fetch's VA (e.g. 0x1002) instead
          -- of the faulting instruction's VA (0x1000). The flag clears as soon as
          -- tlb_exc_pend deasserts, re-arming for the next fault.
          if PRIV_ARCH and tlb_exc_pend = '1' and this.tlb_exc_captured = '0' then
            this.mmu.tea := tlb_fault_va;
            -- PTEH captures the 4 KB-granular VPN on a miss: VA[31:12]. 4 KB is
            -- the finest supported page size (PageMask 0); the actual page size
            -- is unknown at miss time and is resolved by software at LDTLB, which
            -- masks coarser if needed. A coarser capture (e.g. 16 KB, VA[31:14])
            -- aliases pages differing only in VA[13:12], so the walker installs
            -- the wrong page and the access re-faults forever; the TSB tag match
            -- also needs the full 4 KB VPN.
            this.mmu.pteh(31 downto 12) := tlb_fault_va(31 downto 12);
            this.mmu.pteh(11 downto 0) := (others => '0');
            -- MMUFSR (hardware-spec.md §2.11): latch cpu.vhd's KIND/PROT/ITLB/
            -- WRITE word, OR in VALID (bit12, always set -- capture only runs
            -- on a real fault) and USER (bit4). USER must come from
            -- this.sr.md sampled HERE (SSR is not written yet at capture
            -- time, and tlb_exc_sr is a different, non-synchronized path) --
            -- same precedent as this.tlb_exc_sr := this.sr; above. MULTI_HIT
            -- (tlb_exc_fsr(11 downto 8) = "0111") leaves the entire low byte
            -- (including USER) at 0, per spec.
            this.mmu.fsr := (others => '0');
            this.mmu.fsr(12) := '1';
            this.mmu.fsr(11 downto 5) := tlb_exc_fsr(11 downto 5);
            if tlb_exc_fsr(11 downto 8) /= "0111" then
              this.mmu.fsr(4) := not this.sr.md;
            end if;
            this.mmu.fsr(3 downto 0) := tlb_exc_fsr(3 downto 0);
            this.tlb_exc_captured := '1';
            -- Latch the faulting instruction's restart PC (D-side faults only).
            -- tlb_exc_is_d gates the xbus=PC substitution to the D-fault entry;
            -- I-fetch faults (EXPEVT 0x040 IMISS / 0x0A0 IPROT) keep the live PC.
            -- The D-fault entry slot reads tlb_exc_pc via SEL_TLBPC and subtracts
            -- alu_y=4, so SPC = tlb_exc_pc - 4. The resume (LDTLB.R/RTE) re-enters
            -- exactly AT SPC -- NOT one slot ahead, as earlier revisions of this
            -- comment assumed; that mistaken belief was one of the two compounding
            -- -2 terms that put the D-side restart four bytes early. Captured for
            -- every fault (I-fetch faults read SEL_PC, not SEL_TLBPC, so this
            -- value is simply unused for them). See the D-side arm below for the
            -- measured derivation from the live ex_if_pc.
            -- I-fetch faults (IMISS/IPROT): the D-side ma_pc shadow is stale, but
            -- tlb_fault_va IS the faulting FETCH VA at this first-fault cycle
            -- (0x1000 in the delay-slot case). Normal I-fault -> restart = fetch VA
            -- (re-fetch). Delay-slot I-fault -> the live fetch PC has already been
            -- redirected to the branch TARGET by exception-entry time, so the old
            -- SEL_PC (this.pc - 2) landed past the branch; capture branch = fetch
            -- VA - 2 instead so the branch re-runs and re-issues the delay slot.
            -- IMISS/IPROT entry reads this via SEL_TLBPC with alu_y=0.
            if tlb_exc_is_i = '1' then
              if delay_slot = '1' then
                this.tlb_exc_pc := std_logic_vector(unsigned(tlb_fault_va) - 2);
              else
                this.tlb_exc_pc := tlb_fault_va;
              end if;
            -- D-side: derive the restart from the instruction's OWN PC via the
            -- LIVE ex_if_pc -- not the run-ahead this.pc shadow (ma_pc) and not
            -- the MA-launch shadow (ma_if_pc), which is now unused here.
            -- MEASURED from cosim VCDs (sim/tests/mmupcprobe.S, a single PLAIN
            -- faulting load at 0x104e; and mmurestartpc.S, a single @Rn+ load at
            -- 0x1054):
            -- * the resume (LDTLB.R/RTE) re-enters exactly AT SPC, NOT one
            -- slot ahead as the old comment assumed: after the handler,
            -- ex_if_pc went 0x104a, 0x104c, 0x104e, i.e. straight to
            -- SPC = tlb_exc_pc - 4 = 0x104a.
            -- * the SHADOWED this.ma_if_pc is NOT a usable base: it is sampled
            -- at the data-access launch slot, and how far ex_if_pc has
            -- advanced by then depends on the addressing mode. For the plain
            -- load it held 0x104c (= faulting_PC - 2); for the @Rn+ load,
            -- whose access launches a slot later, it held 0x1054
            -- (= faulting_PC). No constant bias can correct both.
            -- * the LIVE ex_if_pc, at this first-fault capture cycle, IS the
            -- faulting instruction's own PC in BOTH cases (0x104e / 0x1054).
            -- So derive the restart from the live ex_if_pc. The D-fault entry
            -- computes SPC = tlb_exc_pc - 4 (exceptions.toml, alu_y=4 SUB) and
            -- the resume lands on SPC, hence:
            -- normal : tlb_exc_pc = ex_if_pc + 4 -> SPC = faulting_PC ->
            -- re-executes exactly the faulting instruction.
            -- dslot : ex_if_pc = delay_slot_PC (= branch+2), and the restart
            -- must be the BRANCH so it re-issues its delay slot, so
            -- tlb_exc_pc = ex_if_pc + 2 -> SPC = branch_PC.
            -- ma_dslot (shadowed at the access slot) still selects the arm; only
            -- the PC source changes. The I-side arm above is untouched: IMISS/
            -- IPROT read this via SEL_TLBPC with alu_y=0, carrying no -4 term.
            elsif this.ma_dslot = '1' then
              this.tlb_exc_pc := std_logic_vector(unsigned(ex_if_pc) + 2);
            else
              this.tlb_exc_pc := std_logic_vector(unsigned(ex_if_pc) + 4);
            end if;
            -- Capture the user SR for the D-fault entry's SSR save (read via
            -- SEL_TLBSR), stable across the stalled entry slot's re-evaluations.
            this.tlb_exc_sr := this.sr;
            -- Latch the faulting @Rn+ load's base register and its pre-increment
            -- base (= the faulting VA, the un-incremented Rn). tlb_restore_pend is
            -- armed only for a genuine post-increment (ma_autoupd) so plain loads,
            -- displacement loads and ALU EX writes are never restored.
            this.tlb_fault_zreg := this.ma_numz;
            -- @Rn+ loads restore the pre-increment base = faulting VA; @-Rn
            -- pre-decrement stores restore the captured pre-decrement base
            -- (ma_base) since their faulting VA is the ALREADY-decremented
            -- address. Both retarget the same shadowed base register (ma_numz).
            --
            -- Gated on tlb_exc_ifetch='0': arm the restore for D-SIDE faults
            -- ONLY. ma_numz / ma_autoupd / ma_predec are written only at the
            -- memory-access pipeline point and are never cleared on a non-memory
            -- instruction, so on ANY instruction-fetch fault (IMISS/IPROT/
            -- MULTI_HIT) they still hold the last post-increment load's base
            -- register and a stale ma_autoupd='1'. Un-gated, that armed a bogus
            -- restore and restore_fire wrote the I-side faulting FETCH VA into
            -- that GPR. Both branches must be gated: a pre-decrement store
            -- shadow is equally stale on an I-side fault.
            --
            -- MUST use tlb_exc_ifetch here, NOT tlb_exc_is_i: tlb_exc_is_i is
            -- deliberately narrowed to IMISS/IPROT (it exists only to pick the
            -- restart-PC derivation, see the comment above). An I-side
            -- MULTI_HIT has tlb_exc_is_i='0' -- reusing it here left MULTI_HIT
            -- taking the D-side arm below and clobbering a GPR from a stale
            -- shadow (the bug this comment used to describe as fixed).
            if tlb_exc_ifetch = '1' then
              this.tlb_restore_val := tlb_fault_va;
              this.tlb_restore_pend := '0';
            elsif PRIV_ARCH and this.ma_predec = '1' then
              this.tlb_restore_val := this.ma_base;
              this.tlb_restore_pend := '1';
            else
              this.tlb_restore_val := tlb_fault_va;
              this.tlb_restore_pend := this.ma_autoupd;
            end if;
            -- TSB pointer assist (hardware-spec §2.8): compute the address of
            -- the TSB slot for the faulting VPN and latch it into TSBPTR (read-
            -- only via STC TSBPTR / MMIO 0xFF00001C).
            -- vpn = faulting_VA[31:12] (4 KB page number)
            -- hash = HASH_MODE=1 ? vpn xor (vpn >> HASH_SHIFT) : vpn
            -- mask = (1 << TSB_SIZE_LOG) - 1
            -- TSBPTR = (TSBBR and not 0xF) or ((hash and mask) << 4)
            -- TSBBR[N+3:4] are reserved-0 so clearing the low nibble and ORing
            -- the 16-byte-scaled index suffices (no variable base mask needed).
            v_vpn := x"000" & unsigned(tlb_fault_va(31 downto 12));
            v_shift := to_integer(unsigned(this.mmu.tsbcfg(7 downto 4)));
            v_size := to_integer(unsigned(this.mmu.tsbbr(3 downto 0)));
            if this.mmu.tsbcfg(3 downto 0) = x"1" then
              v_hash := v_vpn xor shift_right(v_vpn, v_shift);
            else
              v_hash := v_vpn;
            end if;
            v_mask := shift_left(to_unsigned(1, 32), v_size) - 1;
            v_idx := (v_hash and v_mask);
            this.mmu.tsbptr :=
              (this.mmu.tsbbr and x"FFFFFFF0")
              or std_logic_vector(shift_left(v_idx, 4));
            -- EXPEVT is NOT written here: the fault cause is latched via a
            -- slot-gated sr="EXPEVT" microcode write in the TLB exception
            -- handler microcode (exceptions.toml), mirroring TRAPA/Error, so
            -- it persists past the handler prologue. (TEA/PTEH stay here:
            -- they are VA-dependent and consumed before any slot boundary.)
          end if;
          if PRIV_ARCH and tlb_exc_pend = '0' then
            this.tlb_exc_captured := '0';
          end if;
          -- Precise-exception squash window. Arm on the first fault cycle; hold
          -- until the handler is entered (SR.RB=1, this design's "in handler"
          -- indicator). Across this window every retiring instruction was issued
          -- AFTER the faulting access (the fault redirect lands a slot late), so
          -- their GPR writebacks are suppressed (see the we gating at the
          -- register_file instantiation) to keep the faulting access's operands
          -- intact for the restart. RB=1 gates tlb_exc_pend off in cpu.vhd, so a
          -- fault never arms this while already in the handler.
          if PRIV_ARCH then
            if this.sr.rb = '1' then
              this.tlb_squash := '0';
            elsif squash_arm = '1' then
              -- squash_arm is the SHARED arming predicate; g_wb_grace consumes
              -- the identical signal. Do not re-inline tlb_exc_pend here.
              this.tlb_squash := '1';
            end if;
          end if;
          -- One-shot: once the base restore has been driven onto the EX write
          -- port (restore_fire), disarm so it commits exactly once.
          if PRIV_ARCH and restore_fire = '1' then
            this.tlb_restore_pend := '0';
          end if;
          -- Deferred MMUCR.TI (bit 2) self-clear. The P4 MMUCR write below stores
          -- the TI bit set; here -- evaluated against the REGISTERED mmucr at the
          -- top of the process, i.e. one cycle after the write -- it is cleared.
          -- That leaves mmucr(2) registered high for exactly one cycle, which the
          -- TLB's clocked ti port samples to flush all entries. (J4.)
          if PRIV_ARCH and this.mmu.mmucr(2) = '1' then
            this.mmu.mmucr(2) := '0';
          end if;
          next_state := this.debug_state;
          if this.old_debug = '0' and debug = '1' and -- debug input rose
                                                      -- meaning BREAK
                                                      -- instruction ran
            (this.debug_state = RUN or this.debug_state = AWAIT_BREAK) then
            next_state := AWAIT_IF;
            -- stop requesting debug mode once we're in debug mode
            this.enter_debug := (others => '0');
          elsif this.debug_state = RUN and debug_i.en = '1' and debug_i.cmd = BREAK then
            -- schedule entering debug mode
            -- TODO: we could probably set enter_debug(0) = '1' to
            -- immediately enter, but need to be careful that mask_int is
            -- set early enough to avoid an interrupt during debugging.
            this.enter_debug(this.enter_debug'left) := '1';
            next_state := AWAIT_BREAK;
          end if;
          this.old_debug := debug;
          -- check if data bus transaction finished
          if this.data_o.en = '1' and db_i.ack = '1' then
            -- FIXME: Drop en, unless keep_cyc='1'
            this.m_dr_next := align_read_data(db_i.d, this.data_o, this.data_o_size);
            -- SH2A_ARCH only: MOVU.B/MOVU.W zero-extend override, applied at the
            -- call site (not inside align_read_data) so the base build's
            -- align_read_data stays byte-identical to master. Dead-code-
            -- eliminated on base (SH2A_ARCH=false, data_o_unsigned const-'0').
            if SH2A_ARCH and this.data_o_unsigned = '1' then
              case this.data_o_size is
                when BYTE => this.m_dr_next(31 downto 8) := (others => '0');
                when WORD => this.m_dr_next(31 downto 16) := (others => '0');
                when others => null;
              end case;
            end if;
            this.m_en := '1';
            this.data_o := NULL_DATA_O;
          end if;
          -- Snapshot inst_o.en for the slot decision below, taken BEFORE the
          -- debug-command block can rewrite inst_o from `instr` (to_inst_o sets
          -- en := instr.issue). That debug write only happens when
          -- debug_state = READY, in which case slot is forced to 0 anyway, so
          -- using the snapshot is behaviorally identical -- but it keeps
          -- instr.issue out of slot_o's logic cone (breaks a false comb loop).
          slot_inst_en := this.inst_o.en;
          -- check if instruction bus transaction finished
          if this.inst_o.en = '1' and inst_i.ack = '1' then
            this.if_dr_next := inst_i.d;
            -- Retiming: evaluate the opcode-derived illegal checks here, in the
            -- same cycle/enable as if_dr_next, instead of combinationally from
            -- if_dr at the if_en transfer below. This mirrors if_dr_next's
            -- write-enable exactly so illegal_instr_next/illegal_delay_slot_next
            -- stay in lockstep with if_dr_next through any stall. The PRIV_ARCH
            -- term is NOT computed here -- it depends on this.sr.md at the LATER
            -- if_en transfer point, which can differ from this cycle's sr.md if
            -- SR changes while if_dr_next sits waiting to be transferred.
            this.illegal_delay_slot_next := check_illegal_delay_slot(inst_i.d);
            this.illegal_instr_next := check_illegal_instruction(inst_i.d);
            -- Record (do not raise) an I-fetch translation fault, in lockstep with
            -- if_dr_next / if_pc_next. See if_fault in components_pkg.vhd.
            if MMU_ARCH then
              this.if_fault_next := inst_fault;
            end if;
            -- Capture this fetch's VA with the instruction word. inst_o.a is the
            -- requested VA[31:1] (the MMU VA->PA fold is in cpu.vhd) and is still
            -- valid here (NULLed just below). Taken before any branch redirect, so
            -- a delay-slot load carries its true PC (=branch+2), not the run-ahead
            -- fetch PC. Rides with if_dr_next -> if_dr -> out to decode.
            if PRIV_ARCH then
              this.if_pc_next := this.inst_o.a & '0';
            end if;
            this.if_en := '1';
            this.inst_o := NULL_INST_O;
            slot_inst_en := '0';
          elsif this.debug_state = READY and debug_i.en = '1' then
            -- handle debug command
            case debug_i.cmd is
              when BREAK =>
                -- A BREAK cmd when already in the READY state does nothing
                this.debug_o.ack := '1';
              when INSERT =>
                -- use the instruction from the debug register
                this.if_dr_next := debug_i.ir;
                -- Mirror if_dr_next's enable exactly (see the inst_i.ack branch
                -- above): the debug-inserted instruction also needs its illegal
                -- checks computed alongside if_dr_next here.
                this.illegal_delay_slot_next := check_illegal_delay_slot(debug_i.ir);
                this.illegal_instr_next := check_illegal_instruction(debug_i.ir);
                this.if_en := '1';
                this.stop_pc_inc := '1';
                -- latch the y-bus override into start of pipeline
                this.ybus_override(this.ybus_override'left) := ( en => debug_i.d_en, d => debug_i.d );
                -- await instruction fetch before processing next debug command
                next_state := AWAIT_IF;
              when STEP =>
                -- fetch a real instruction to execute next
                this.inst_o := to_inst_o(instr, this.pc);
                -- leave debug mode but schedule an enter_debug to get back into debug mode
                this.enter_debug(this.enter_debug'left) := '1';
                next_state := AWAIT_BREAK;
              when CONTINUE =>
                -- fetch a real instruction to execute next
                this.inst_o := to_inst_o(instr, this.pc);
                this.enter_debug(this.enter_debug'left) := '0';
                next_state := RUN;
            end case;
          end if;
          if this.stop_pc_inc = '1' then
            this.pc_inc := this.pc;
          end if;
          if this.slot = '1' then
            -- Shift enter_debug pipeline along. The left-most bit is duplicated.
            -- The right-most bit becomes the enter_debug output.
            this.enter_debug := this.enter_debug(this.enter_debug'left) &
                                this.enter_debug(this.enter_debug'left downto 1);
          end if;
          -- A busy sequential shifter (J1) stretches the slot, freezing the
          -- whole pipeline (incl. this shift in EX) until it finishes. The
          -- shifter steps on the clock, so it advances while slot_o is held
          -- low; comb shifter ties shift_busy='0' (no effect on J2/J4).
          if this.data_o.en = '0' and slot_inst_en = '0' and this.debug_state /= READY and shift_busy = '0' and mult_stall = '0' then
            -- present data read by completed transactions
            if this.m_en = '1' then
              this.m_dr := this.m_dr_next;
              this.m_en := '0';
            elsif coproc.cpu_data_mux /= DBUS then
              this.m_dr := cop_i.d;
            end if;
            if this.if_en = '1' then
              this.if_dr := this.if_dr_next;
              if PRIV_ARCH then
                this.if_pc := this.if_pc_next; -- carry the fetch VA with if_dr
              end if;
              -- Retimed: the opcode-derived part of these was already computed
              -- (in lockstep with if_dr_next, same enable) when if_dr_next was
              -- written; just transfer it alongside if_dr here.
              this.illegal_delay_slot := this.illegal_delay_slot_next;
              this.illegal_instr := this.illegal_instr_next;
              if MMU_ARCH then
                this.if_fault := this.if_fault_next;
              end if;
              if PRIV_ARCH then
                this.illegal_instr := this.illegal_instr or
                  (privileged(this.if_dr) and not this.sr.md);
              end if;
              this.if_en := '0';
            end if;
            this.slot := '1';
          else
            -- Slot is output as a combinatorial signal. Other blocks use it to
            -- determine if a rising clock edge is the start of a new CPU slot
            -- or whether the current slot is stretched into the next cycle.
            this.slot := '0';
          end if;
          if this.slot = '1' then
            -- start new memory transactions
            -- Age rule (see reg_wr_w_g): block a pending access only when the
            -- window was armed by a D-SIDE fault. On an I-fetch fault nothing
            -- younger than the faulting fetch is in flight, so an access pending
            -- here belongs to an OLDER instruction the restart will not re-run;
            -- blocking it loses the access outright.
            if (mem.issue = '1' and this.data_o.en = '0'
                and (tlb_squash_r = '0' or squash_ifetch_r = '1')) or
               (coproc.coproc_cmd = LDS) then
              -- start new data request
              case mem.addr_sel is
                when SEL_XBUS => ma_ad := xbus;
                when SEL_YBUS => ma_ad := ybus;
                when SEL_ZBUS => ma_ad := zbus;
              end case;
              case mem.wdata_sel is
                when SEL_YBUS => ma_dw := ybus;
                when SEL_ZBUS => ma_dw := zbus;
              end case;
              this.data_o_size := mem.size;
              -- SH2A_ARCH only: capture mem_unsigned alongside data_o_size so
              -- align_read_data (called later, on bus ack) knows whether this
              -- load is a MOVU.B/MOVU.W zero-extend. Base builds always see
              -- mem.mem_unsigned='0' here (never driven non-default outside
              -- the SH-2A overlay), so this field is constant-'0' and pruned.
              if SH2A_ARCH then
                this.data_o_unsigned := mem.mem_unsigned;
              end if;
              -- P4 MMU register access (MMUCR=0xFF000010, TTB=0xFF000008, TEA=0xFF00000C)
              -- handled entirely within the datapath: no bus transaction is issued and
              -- the read result is injected directly into the wbus pipeline.
              if PRIV_ARCH then
                seg_v := seg_decode(ma_ad);
                -- Default p4_sel_v every visit so it is never read holding a
                -- value from a prior process iteration: an unconditional read-
                -- before-write on a process variable synthesises to a
                -- combinational feedback loop (yosys check -assert) on
                -- datapath.p4_sel_v. P4_NONE is the "no MMU register at this P4
                -- address" sentinel (falls into the case `others` branch);
                -- PTEH/PTEL/ASIDR are never P4-MMIO selected (handled via LDC).
                p4_sel_v := P4_NONE;
                if ma_ad(7 downto 0) = x"08" then p4_sel_v := P4_TTB;
                elsif ma_ad(7 downto 0) = x"0C" then p4_sel_v := P4_TEA;
                elsif ma_ad(7 downto 0) = x"10" then p4_sel_v := P4_MMUCR;
                elsif ma_ad(7 downto 0) = x"14" then p4_sel_v := P4_TSBBR;
                elsif ma_ad(7 downto 0) = x"18" then p4_sel_v := P4_TSBCFG;
                elsif ma_ad(7 downto 0) = x"1C" then p4_sel_v := P4_TSBPTR;
                elsif ma_ad(7 downto 0) = x"28" then p4_sel_v := P4_MMUFSR;
                end if;
              end if;
              if PRIV_ARCH and seg_v = SEG_P4 then
                if mem.wr = '1' then
                  case p4_sel_v is
                    when P4_MMUCR =>
                      -- Write the full value INCLUDING the TI bit (bit 2). It is
                      -- self-cleared one cycle later (see the deferred clear near
                      -- the top of this process) so it is registered high for
                      -- exactly one cycle -- long enough for the TLB's clocked
                      -- ti flush to fire. Clearing it here (same evaluation as the
                      -- write) would mean the registered bit is NEVER high and the
                      -- flush never happens.
                      this.mmu.mmucr := ma_dw;
                    when P4_TTB => this.mmu.ttb := ma_dw;
                    when P4_TEA => this.mmu.tea := ma_dw;
                    when P4_TSBBR => this.mmu.tsbbr := ma_dw;
                    when P4_TSBCFG => this.mmu.tsbcfg := ma_dw;
                    -- P4_TSBPTR is read-only: a write is silently ignored.
                    when others => null;
                  end case;
                else
                  case p4_sel_v is
                    when P4_MMUCR => this.m_dr_next := this.mmu.mmucr;
                    when P4_TTB => this.m_dr_next := this.mmu.ttb;
                    when P4_TEA => this.m_dr_next := this.mmu.tea;
                    when P4_TSBBR => this.m_dr_next := this.mmu.tsbbr;
                    when P4_TSBCFG => this.m_dr_next := this.mmu.tsbcfg;
                    when P4_TSBPTR => this.m_dr_next := this.mmu.tsbptr;
                    when P4_MMUFSR => this.m_dr_next := this.mmu.fsr;
                    when others => this.m_dr_next := (others => '0');
                  end case;
                  this.m_en := '1';
                end if;
              else
                this.data_o := to_data_o(mem, coproc, ma_ad, ma_dw);
                -- Shadow the architectural PC of the instruction launching this
                -- data access (a fixed pipeline point). On a later fault this is
                -- the faulting instruction's PC, independent of how far the fetch
                -- pointer has since advanced. (J4+PRIV_ARCH only.)
                if PRIV_ARCH then
                  -- Export the launch itself (see the ma_launch declaration):
                  -- g_restore2's second base-restore entry keys off exactly this
                  -- pipeline point, so it is published from here rather than
                  -- reconstructed outside the process.
                  ma_launch <= '1';
                  this.ma_pc := this.pc;
                  -- Shadow the (bank-remapped) base register (Rm = num_x in the
                  -- @Rm+ access slot) and the post-increment marker of the
                  -- instruction launching this access, at the same fixed pipeline
                  -- point as ma_pc, so a later fault can restore the pre-increment
                  -- base of the faulting @Rm+ load.
                  this.ma_numz := num_x_r;
                  -- mem_autoinc1 (single-slot @Rm+ MACH/MACL load) restores the
                  -- same way as mem_autoupd: faulting VA = original Rm.
                  this.ma_autoupd := mem_autoupd or mem_autoinc1;
                  -- @-Rn pre-decrement store: also shadow the marker and the
                  -- ORIGINAL pre-decrement base (xbus = Rn, read this slot before
                  -- the decrement z-write commits). On a fault this restores Rn so
                  -- the RTE-restart re-applies the decrement exactly once.
                  this.ma_predec := mem_predec;
                  this.ma_base := xbus;
                  -- Shadow the delay-slot condition of the access-launching
                  -- instruction (same fixed pipeline point as ma_pc) so a later
                  -- D-fault selects the branch-restart bias below.
                  this.ma_dslot := delay_slot;
                  -- Shadow the access-launching instruction's OWN PC (EX-aligned
                  -- ex_if_pc from decode) so the D-fault restart is derived from
                  -- the instruction's PC, not the run-ahead this.pc (ma_pc). For a
                  -- delay-slot load ex_if_pc = delay_slot_PC (= branch+2) whereas
                  -- ma_pc is the branch target.
                  -- DEAD STATE: no readers left. See components_pkg.vhd.
                  this.ma_if_pc := ex_if_pc;
                end if;
              end if;
            end if;
            if instr.issue = '1' then
              if this.debug_state = RUN or this.debug_state = AWAIT_BREAK then
                if this.inst_o.en = '0' then
                  -- start new instruction request
                  if instr.addr_sel = '0' then if_ad := this.pc_inc;
                  else if_ad := zbus;
                  end if;
                  this.inst_o := to_inst_o(instr, if_ad, instr.addr_sel);
                end if;
              elsif this.debug_state = AWAIT_IF or next_state = AWAIT_IF then
                -- In debug mode, an instruction fetch issue is our signal to
                -- pause the CPU. Later we will either allow the instruction
                -- fetch from memory to proceed or we'll insert an instruction.
                -- Also check for next_state=AWAIT_IF to skip AWAIT_IF state
                -- when decoder is already requesting an instruction.
                next_state := READY;
                -- Move y-bus override through its pipeline to use in EX
                -- stage. Currently the pipeline is short such that the INSERT
                -- value used in an instruction has to come in the subsequent
                -- INSERT command. Will likely increase pipeline size.
                for i in 1 to this.ybus_override'left loop
                  this.ybus_override(i-1) := this.ybus_override(i);
                end loop;
                this.ybus_override(this.ybus_override'left) := BUS_VAL_RESET;
              end if;
            end if;
            -- update PC
            if pc_ctrl.wr_z = '1' then this.pc := zbus;
            elsif pc_ctrl.inc = '1' then this.pc := this.pc_inc; end if;
            -- NOTE: SH2A restart-safe MOVML.L Rm,@-R15 push scratch state
            -- (push_ptr/push_active capture + in-flight tracking) is registered
            -- in the SH2A_ARCH generate g_push below (NOT in this shared
            -- process / the shared datapath_reg_t record), so non-SH2A variants
            -- carry zero push state and the J4 combinational spillover is gone.
            -- update SR
            case sr_ctrl.sel is
              when SEL_PREV =>
                -- leave sr unchanged
              when SEL_WBUS =>
                this.sr := to_sr(wbus);
              when SEL_ZBUS =>
                this.sr := to_sr(zbus);
              when SEL_DIV0U =>
                this.sr.m := '0';
                this.sr.q := '0';
                this.sr.t := '0';
              when SEL_ARITH =>
                this.sr := arith_update_sr(
                  this.sr,
                  -- although it feels like aluinx and aluiny have the proper
                  -- MSB bits here, for DIV1 aluinx has already been shifted
                  -- left one and the MSB we want is lost. Use xbus instead
                  -- (and use ybus for symmetry).
                  -- aluinx(aluinx'left),
                  -- aluiny(aluiny'left),
                  xbus(xbus'left),
                  ybus(ybus'left),
                  arith_out(31 downto 0),
                  arith_out(arith_out'left),
                  arith_func,
                  func.arith.sr);
              when SEL_LOGIC =>
                this.sr := logic_update_sr(this.sr, logic_out, func.logic_sr);
              when SEL_INT_MASK =>
                this.sr.int_mask := sr_ctrl.ilevel;
              when SEL_SET_T =>
                -- leave most of sr unchanged, but set the T bit
                case sr_ctrl.t is
                  when SEL_CLEAR =>
                    this.sr.t := '0';
                  when SEL_SET =>
                    this.sr.t := '1';
                  when SEL_SHIFT =>
                    this.sr.t := sfto;
                  when SEL_CARRY =>
                    this.sr.t := arith_out(arith_out'left);
                end case;
              when SEL_EXCEPTION =>
                -- SH-4 exception entry (J4): enter privileged mode, bank 1,
                -- block further exceptions. IMASK is left unchanged for general
                -- exceptions (BL=1 masks during the handler); interrupts set
                -- IMASK via a separate SEL_INT_MASK slot. The old SR is captured
                -- to SSR in the same slot via the ybus read, which uses the
                -- registered (pre-update) SR.
                this.sr.md := '1';
                this.sr.rb := '1';
                this.sr.bl := '1';
              when SEL_EXPEVT =>
                -- SH-4 cause capture (J4): latch the slot immediate (the
                -- exception code) into EXPEVT. J1/J2 never select these
                -- selectors; the PRIV_ARCH guard makes that explicit so the
                -- priv register and its fan-out are pruned entirely on a
                -- non-PRIV_ARCH build (no leaked FFs/LUTs into J1/J2).
                if PRIV_ARCH then this.priv.expevt := buses.imm_val(11 downto 0); end if;
              when SEL_INTEVT =>
                if PRIV_ARCH then this.priv.intevt := buses.imm_val(11 downto 0); end if;
              when SEL_TRA =>
                if PRIV_ARCH then this.priv.tra := buses.imm_val(9 downto 0); end if;
            end case;
            -- SH-2A CS (CLIPS/CLIPU saturation, sticky) is NOT set here: it
            -- lives outside sr_t/this.sr entirely -- see the g_cs generate
            -- below and the note on sr_t in core/components_pkg.vhd.
            -- LDC Rm,PTEH/PTEL/ASIDR write path (J4).
            -- When the decoder asserts mmu_reg_wr the zbus carries the source
            -- GPR value; latch it into the addressed MMU CSR flop.
            -- Gated under PRIV_ARCH so J1/J2 (PRIV_ARCH=false) are byte-unchanged.
            if PRIV_ARCH and sr_ctrl.mmu_reg_wr = '1' then
              case sr_ctrl.mmu_reg_sel is
                when SEL_PTEH => this.mmu.pteh := zbus;
                when SEL_PTEL => this.mmu.ptel := zbus;
                when SEL_ASIDR => this.mmu.asidr := zbus;
                when others => null; -- SEL_MMUCR/TTB/TEA handled via P4 MMIO
              end case;
            end if;
            if mac.s_latch = '1' then this.mac_s := this.sr.s; end if;
            this.data_o_lock := mem.lock;
          end if;
          this.pc_inc := std_logic_vector(unsigned(this.pc)+2);
          -- all debug commands are ACKed when either the RUN or READY state are
          -- reached.
          if (next_state = RUN or next_state = READY) then
            if this.debug_o.ack = '0' and debug_i.en = '1' then
              if debug_i.cmd = INSERT then
                -- latch the value being written to the register file for the debug
                -- output.
                this.debug_o.d := reg_wr_data_o;
              else
                -- latch the PC value to simplify debugging and profiling.
                -- Without this multiple inserts, including a JSR and RTS are
                -- needed to get the PC.
                this.debug_o.d := this.pc;
              end if;
            end if;
            this.debug_o.ack := debug_i.en;
            this.stop_pc_inc := '0';
          end if;
          this.debug_state := next_state;
          if this.debug_state = READY then
            this.debug_o.rdy := '1';
          else
            this.debug_o.rdy := '0';
          end if;
          this_c <= this;
 end process;
 datapath_r0 : process(clk, rst)
 begin
    if rst='1' then
       this_r <= DATAPATH_RESET;
    elsif clk='1' and clk'event then
       this_r <= this_c;
    end if;
 end process;
 pc <= this_r.pc;
 tlb_exc_pc <= this_r.tlb_exc_pc when PRIV_ARCH else (others => '0');
 tlb_exc_sr_r <= this_r.tlb_exc_sr;
 sr <= this_r.sr;
 priv_regs <= this_r.priv;
 -- MMU CSR registered copy + ybus sub-mux (J4); constant-0 otherwise
 mmu_regs <= this_r.mmu when PRIV_ARCH else MMU_REG_RESET;
 mmu_ybus <= mmu_regs.ptel when buses.mmu_reg_sel = SEL_PTEL else
             mmu_regs.asidr when buses.mmu_reg_sel = SEL_ASIDR else
             mmu_regs.mmucr when buses.mmu_reg_sel = SEL_MMUCR else
             mmu_regs.ttb when buses.mmu_reg_sel = SEL_TTB else
             mmu_regs.tea when buses.mmu_reg_sel = SEL_TEA else
             mmu_regs.tsbptr when buses.mmu_reg_sel = SEL_TSBPTR else
             mmu_regs.pteh;
 -- Export the SH-4 cause registers (J4). Constant-0 on a non-PRIV_ARCH build
 -- so J1/J2 boards see a tied-off port.
 priv_o.expevt <= priv_regs.expevt when PRIV_ARCH else (others => '0');
 priv_o.intevt <= priv_regs.intevt when PRIV_ARCH else (others => '0');
 priv_o.tra <= priv_regs.tra when PRIV_ARCH else (others => '0');
 -- Export MMU CSRs and committed SR for TLB use in cpu.vhd (PRIV_ARCH).
 mmu_regs_o <= mmu_regs;
 sr_o <= sr;
 tlb_squash_r <= this_r.tlb_squash when PRIV_ARCH else '0';
 -- SINGLE SOURCE OF TRUTH for "the precise-exception squash arms on this
 -- clock edge" (J4+PRIV_ARCH). TWO sites must agree on this predicate: the
 -- process branch that sets this.tlb_squash, and g_wb_grace (which must
 -- sample the pending w-port writeback on the SAME edge, so it cannot wait
 -- for tlb_squash_r -- that is already a cycle too late). Keeping them as
 -- two hand-written copies is a silent-regression hazard, so there is one
 -- signal, consumed by both.
 -- TESTABILITY GUARANTEE (measured, not assumed): sim/tests/mmustr2 FAILS
 -- if g_wb_grace stops arming. Verified by mutation -- replacing the
 -- wb_grace <= reg.wr_w and not slot_o arming with wb_grace <= '0' turns
 -- mmustr2 RED (it stores U). This held only once the D-side restart PC
 -- was corrected to derive from ex_if_pc: while the restart was four bytes
 -- early, re-execution re-created the very writeback the age-blind squash
 -- destroyed, which is what made the grace bit observably neutral and left
 -- it with no failing test behind it. So a desynchronising edit here is now
 -- caught by the suite -- do NOT dismiss an mmustr2 failure as unrelated to
 -- a change in this predicate; it is the guard for it.
 -- * tlb_exc_pend is combinational on the D-side request (cpu.vhd: it
 -- asserts while sig_db_o.en = '1', i.e. before any ack), so the arm is
 -- coincident with the faulting access, not a cycle behind it.
 -- * sr.rb = '0' is the "not already in the handler" guard, matching the
 -- process's own if this.sr.rb = '1' then ... elsif ... structure. It
 -- uses the COMMITTED SR (this_r.sr) rather than the process's
 -- mid-cycle this.sr, so both consumers see one value; where the two
 -- could differ the committed value is the conservative one (it can
 -- only suppress an arm, never create a spurious one).
 squash_arm <= '1' when PRIV_ARCH and tlb_exc_pend = '1' and sr.rb = '0'
               else '0';
 -- Latched on the FIRST arming edge only (tlb_squash_r = '0'), exactly as
 -- g_wb_grace latches: squash_arm can re-assert while the window is already
 -- open, and sampling every cycle would let a later fault's side overwrite
 -- the side of the fault that actually opened this window. No clear needed --
 -- every consumer qualifies it with tlb_squash.
 g_squash_ifetch : if MMU_ARCH generate
   process(clk, rst)
   begin
     if rst = '1' then
       squash_ifetch_r <= '0';
     elsif clk = '1' and clk'event then
       if tlb_squash_r = '0' and squash_arm = '1' then
         squash_ifetch_r <= tlb_exc_ifetch;
       end if;
     end if;
   end process;
 end generate;
 g_squash_ifetch_off : if not MMU_ARCH generate
   squash_ifetch_r <= '0';
 end generate;
 tlb_squash_o <= tlb_squash_r;
 mac_s <= this_r.mac_s;
        db_lock <= this_r.data_o_lock;
        db_o <= this_r.data_o;
        inst_o <= this_r.inst_o;
        if_dr <= this_r.if_dr;
        if_dr_next <= this_r.if_dr_next;
        if_pc <= this_r.if_pc when PRIV_ARCH else (others => '0');
        illegal_delay_slot <= this_r.illegal_delay_slot;
        illegal_instr <= this_r.illegal_instr;
        if_fault_o <= this_r.if_fault when MMU_ARCH else '0';
        cop_o.rna <= copreg(7 downto 4);
        cop_o.rnb <= copreg(3 downto 0);
        cop_o.op <= "11101" when coproc.coproc_cmd = LDS else
                    "11111" when coproc.coproc_cmd = STS else
                    "10001" when coproc.coproc_cmd = CLDS else
                    "10000" when coproc.coproc_cmd = CSTS else
                    "00000";
        cop_o.en <= '0' when coproc.coproc_cmd = NOP else '1';
        cop_o.stallcp <= not slot_o;
        cop_o.d <= this_r.data_o.d;
        wbus <= this_r.m_dr;
        slot_o <= this_c.slot;
        -- Need to output T combinatorially so that decoder can make
        -- conditional branch decisions
        t_bcc <= this_c.sr.t;
        enter_debug <= this_r.enter_debug(0);
        mask_int <= '0' when this_r.debug_state = RUN and this_r.enter_debug = (this_r.enter_debug'range => '0') else '1';
        debug_o <= this_c.debug_o;
        ybus_override <= this_r.ybus_override(0);
        if_stall <= '0';
        slot <= slot_o;
end architecture stru;
