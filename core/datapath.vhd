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
   MMU_ARCH : boolean := false; -- MMU control-register file (subordinate to PRIV_ARCH)
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
       mmu_regs_o : out mmu_reg_t := MMU_REG_RESET; -- MMU CSRs for TLB (J4+MMU_ARCH)
       sr_o : out sr_t; -- committed SR for TLB md bit
       -- Accumulate-squash export: the registered tlb_squash (armed on the
       -- first fault cycle, held until handler entry SR.RB='1') gates the MAC
       -- mach/macl accumulate-commit so MAC @Rm+,@Rn+ stays precise across a
       -- D-side TLB fault. '0' when not MMU_ARCH (J1/J2 bit-identical).
       tlb_squash_o : out std_logic := '0';
       -- TLB fault side-effects: when tlb_exc_pend='1', write TEA, PTEH[31:14]
       -- and EXPEVT (the latter selected from the fault kind by cpu.vhd).
       tlb_exc_pend : in std_logic := '0';
       tlb_fault_va : in std_logic_vector(31 downto 0) := (others => '0');
       tlb_exc_expevt : in std_logic_vector(11 downto 0) := (others => '0');
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
       -- Per-instruction fetch-PC round-trip (J4+MMU_ARCH). if_pc = the VA of
       -- the instruction currently in if_dr (its own PC, captured at fetch
       -- before any branch redirect). decode re-registers it EX-aligned and
       -- returns it as ex_if_pc, which the datapath shadows at the MA-launch
       -- (ma_if_pc) to derive the D-fault restart PC. '0' on non-MMU builds.
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
 signal mmu_regs : mmu_reg_t; -- SH-4 MMU CSRs (J4+MMU_ARCH); 0 otherwise
 signal mmu_ybus : std_logic_vector(31 downto 0); -- sub-mux for SEL_MMU
 -- Faulting-instruction restart-PC capture (J4+MMU_ARCH): registered copy
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
 -- (J4+MMU_ARCH). On a non-MMU build these are exactly reg.wr_z/reg.wr_w, so
 -- J1/J2 behaviour is byte-identical and tlb_squash prunes away.
 signal reg_wr_z_g, reg_wr_w_g : std_logic;
 signal ybus_override : bus_val_t;
 signal slot_o : std_logic;
 -- Precise auto-increment restore (J4+MMU_ARCH). mem_autoupd marks the current
 -- EX op as a memory base post-increment (@Rn+): a data access whose base
 -- register (xbus = Rn) feeds the address while the z-bus writes Rn+size back.
 -- restore_fire drives the one-shot base restore on the first EX-write slot the
 -- microcode leaves free after the fault (reg.wr_z='0' => not an SPC/SSR save).
 signal mem_autoupd : std_logic;
 signal mem_autoinc1 : std_logic;
 signal mem_predec : std_logic;
 signal restore_fire : std_logic;
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
        -- at indices 24-31; J2 keeps 21 (bit-identical).
        function rf_depth(priv : boolean) return integer is
        begin
          if priv then return 32; else return 21; end if;
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
        constant REGFILE_DEPTH : integer := rf_depth(PRIV_ARCH);
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
 gpf_zwd <= this_r.tlb_restore_val when (MMU_ARCH and restore_fire = '1')
            else pc when pc_ctrl.wrpr = '1' else zbus;
 -- mem_autoupd: marks the memory-access slot of a post-increment load @Rm+.
 -- In j-core a post-increment is a two-slot op: slot0 commits Rm := Rm+size on
 -- the EX z-port (no access), then THIS slot reads memory with the address
 -- recomputed as Rm-size, i.e. ma_addy=ZBUS, arith=SUB, base (Rm) on xbus, a
 -- READ. That arith=SUB + ZBUS-addressed READ is unique to @Rm+ (plain @Rm uses
 -- zbus_sel=Y; @(disp,Rm) and indexed loads use ADD; pre-decrement @-Rn is a
 -- WRITE). The faulting VA equals Rm-size = the original pre-increment base, so
 -- restoring Rm := tlb_fault_va undoes slot0's early bump. MMU_ARCH only.
 mem_autoupd <= '1' when MMU_ARCH and mem.issue = '1' and mem.wr = '0'
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
 -- separately (ma_base = xbus = Rn) for the restore. MMU_ARCH only.
 mem_predec <= '1' when MMU_ARCH and mem.issue = '1' and mem.wr = '1'
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
 mem_autoinc1 <= '1' when MMU_ARCH and mem.issue = '1' and mem.wr = '0'
                          and mem.addr_sel = SEL_XBUS
                          and reg.wr_z = '1' and buses.z_sel = SEL_ARITH
                          and func.arith.func = ADD and num_z_r = num_x_r
                 else '0';
 -- Fire the base restore on the first committed slot after the fault on which
 -- the microcode itself is not driving the z-write port (reg.wr_z='0'): this is
 -- clear of the exception entry's slot0/slot1 SPC(21)/SSR(22) saves, so the two
 -- never collide on the shared EX write port.
 restore_fire <= '1' when MMU_ARCH and this_r.tlb_restore_pend = '1'
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
 num_z_r <= this_r.tlb_fault_zreg when (MMU_ARCH and restore_fire = '1')
            else bank_remap(reg.num_z, sr.md, sr.rb) when PRIV_ARCH else reg.num_z;
 num_w_r <= bank_remap(reg.num_w, sr.md, sr.rb) when PRIV_ARCH else reg.num_w;
 -- Bank-remap the dedicated R0-index read port too (drives dout_0); pass-through
 -- (bank-0 R0) on J2, so mov.l @(R0,Rn) uses the correct R0 under SR.RB=1.
 num_0_r <= bank_remap("00000", sr.md, sr.rb) when PRIV_ARCH else "00000";
 -- Suppress memory-load writeback retirement while a TLB fault is pending
 -- entry, so the load instruction(s) behind the faulting access cannot
 -- corrupt its operands before the precise restart (J4+MMU_ARCH only;
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
 -- NOTE -- MAC.L/W @Rm+,@Rn+ is now PRECISE across a D-side TLB fault at
 -- EVERY fault position. BOTH bases Rm,Rn are precise (mem_autoinc1
 -- restore, 1d5064a, single-increments each on EITHER operand fault). The
 -- remaining defect was the MULTIPLY-ACCUMULATE: the MACH:MACL accumulate
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
 reg_wr_z_g <= ((reg.wr_z and (not this_r.tlb_squash
                               or (num_z_r(4) and not num_z_r(3))))
                or restore_fire) when MMU_ARCH else reg.wr_z;
 reg_wr_w_g <= reg.wr_w and not this_r.tlb_squash when MMU_ARCH else reg.wr_w;
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
 datapath : process(this_r,pc_ctrl,wbus,zbus,sr_ctrl, xbus, ybus, mac,mem, instr, db_i, inst_i, debug, debug_i,reg_wr_data_o, logic_out, arith_out, arith_func, func, sfto, coproc, cop_i, shift_busy, mult_stall, tlb_exc_pend, tlb_fault_va, tlb_exc_expevt, reg, num_x_r, mem_autoupd, mem_autoinc1, mem_predec, restore_fire, delay_slot, tlb_exc_is_i, ex_if_pc)
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
          -- TLB fault hardware side-effects (J4+MMU_ARCH): on the first cycle a
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
          if MMU_ARCH and tlb_exc_pend = '1' and this.tlb_exc_captured = '0' then
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
            this.tlb_exc_captured := '1';
            -- Latch the faulting instruction's restart PC (D-side faults only).
            -- ma_pc still holds the faulting access's launch PC: any following
            -- access launches a slot later, after this first-fault capture. The
            -- SPC adjustment (exceptions.toml D-fault slot 0) subtracts the
            -- constant launch-to-instruction offset. tlb_exc_is_d gates the
            -- xbus=PC substitution to the D-fault entry; I-fetch faults
            -- (EXPEVT 0x040 IMISS / 0x0A0 IPROT) keep the live PC.
            -- ma_pc holds the faulting access launch PC = faulting_instr + 4
            -- (the architectural PC during EX). The D-fault entry slot reads this
            -- via SEL_TLBPC and subtracts alu_y=4; the resume (LDTLB.R/RTE)
            -- re-enters one slot ahead, so the restart PC must be
            -- faulting_instr - 2. Pre-bias by 2 here so tlb_exc_pc - 4 =
            -- faulting_instr - 2. Captured for every fault (I-fetch faults read
            -- SEL_PC, not SEL_TLBPC, so this value is simply unused for them).
            -- Delay-slot D-fault: ma_pc is the BRANCH PC (the fetch PC is held
            -- across the delayed branch), not faulting_instr + 4. Restart must be
            -- the branch (so it re-issues its delay slot), i.e. SPC = branch - 2.
            -- SPC = tlb_exc_pc - 4, so tlb_exc_pc = branch + 2 = ma_pc + 2 here.
            -- (Without this the -2 bias yields SPC = branch - 6, landing three
            -- instructions before the branch -> wrong control flow / fault cascade.)
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
            -- D-side: derive the restart from the instruction's OWN PC (ma_if_pc,
            -- EX-aligned), not the run-ahead this.pc shadow (ma_pc). SPC = TLBPC-4
            -- and the resume re-enters one slot ahead, so SPC lands at tlb_exc_pc-2:
            -- normal load: ma_if_pc = load_PC -> tlb_exc_pc = ma_if_pc+2
            -- -> SPC = load_PC-2 -> re-executes the load.
            -- delay slot : ma_if_pc = delay_slot_PC(=branch+2) -> tlb_exc_pc =
            -- ma_if_pc -> SPC = branch-2 -> re-executes the BRANCH,
            -- which re-issues its delay slot (the load).
            elsif this.ma_dslot = '1' then
              this.tlb_exc_pc := this.ma_if_pc;
            else
              this.tlb_exc_pc := std_logic_vector(unsigned(this.ma_if_pc) + 2);
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
            if MMU_ARCH and this.ma_predec = '1' then
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
          if MMU_ARCH and tlb_exc_pend = '0' then
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
          if MMU_ARCH then
            if this.sr.rb = '1' then
              this.tlb_squash := '0';
            elsif tlb_exc_pend = '1' then
              this.tlb_squash := '1';
            end if;
          end if;
          -- One-shot: once the base restore has been driven onto the EX write
          -- port (restore_fire), disarm so it commits exactly once.
          if MMU_ARCH and restore_fire = '1' then
            this.tlb_restore_pend := '0';
          end if;
          -- Deferred MMUCR.TI (bit 2) self-clear. The P4 MMUCR write below stores
          -- the TI bit set; here -- evaluated against the REGISTERED mmucr at the
          -- top of the process, i.e. one cycle after the write -- it is cleared.
          -- That leaves mmucr(2) registered high for exactly one cycle, which the
          -- TLB's clocked ti port samples to flush all entries. (J4+MMU_ARCH.)
          if MMU_ARCH and this.mmu.mmucr(2) = '1' then
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
            -- Capture this fetch's VA with the instruction word. inst_o.a is the
            -- requested VA[31:1] (the MMU VA->PA fold is in cpu.vhd) and is still
            -- valid here (NULLed just below). Taken before any branch redirect, so
            -- a delay-slot load carries its true PC (=branch+2), not the run-ahead
            -- fetch PC. Rides with if_dr_next -> if_dr -> out to decode.
            if MMU_ARCH then
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
              if MMU_ARCH then
                this.if_pc := this.if_pc_next; -- carry the fetch VA with if_dr
              end if;
              this.illegal_delay_slot := check_illegal_delay_slot(this.if_dr);
              this.illegal_instr := check_illegal_instruction(this.if_dr);
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
            if (mem.issue = '1' and this.data_o.en = '0') or
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
              if MMU_ARCH then
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
                end if;
              end if;
              if MMU_ARCH and seg_v = SEG_P4 then
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
                    when others => this.m_dr_next := (others => '0');
                  end case;
                  this.m_en := '1';
                end if;
              else
                this.data_o := to_data_o(mem, coproc, ma_ad, ma_dw);
                -- Shadow the architectural PC of the instruction launching this
                -- data access (a fixed pipeline point). On a later fault this is
                -- the faulting instruction's PC, independent of how far the fetch
                -- pointer has since advanced. (J4+MMU_ARCH only.)
                if MMU_ARCH then
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
            -- LDC Rm,PTEH/PTEL/ASIDR write path (J4+MMU_ARCH).
            -- When the decoder asserts mmu_reg_wr the zbus carries the source
            -- GPR value; latch it into the addressed MMU CSR flop.
            -- Gated under MMU_ARCH so J1/J2 (MMU_ARCH=false) are byte-unchanged.
            if MMU_ARCH and sr_ctrl.mmu_reg_wr = '1' then
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
 tlb_exc_pc <= this_r.tlb_exc_pc when MMU_ARCH else (others => '0');
 tlb_exc_sr_r <= this_r.tlb_exc_sr;
 sr <= this_r.sr;
 priv_regs <= this_r.priv;
 -- MMU CSR registered copy + ybus sub-mux (J4+MMU_ARCH); constant-0 otherwise
 mmu_regs <= this_r.mmu when MMU_ARCH else MMU_REG_RESET;
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
 -- Export MMU CSRs and committed SR for TLB use in cpu.vhd (MMU_ARCH).
 mmu_regs_o <= mmu_regs;
 sr_o <= sr;
 tlb_squash_o <= this_r.tlb_squash when MMU_ARCH else '0';
 mac_s <= this_r.mac_s;
        db_lock <= this_r.data_o_lock;
        db_o <= this_r.data_o;
        inst_o <= this_r.inst_o;
        if_dr <= this_r.if_dr;
        if_dr_next <= this_r.if_dr_next;
        if_pc <= this_r.if_pc when MMU_ARCH else (others => '0');
        illegal_delay_slot <= this_r.illegal_delay_slot;
        illegal_instr <= this_r.illegal_instr;
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
