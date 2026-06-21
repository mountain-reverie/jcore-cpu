library ieee;
use ieee.std_logic_1164.all;
use work.cpu2j0_pack.all;
use work.decode_pack.all;
use work.cpu2j0_components_pack.all;
use work.datapath_pack.all;
use work.mult_pkg.all;

entity cpu is
 generic (
   COPRO_DECODE : boolean := true;
   PRIV_ARCH    : boolean := false;
   MMU_ARCH     : boolean := false);  -- MMU control-register file (subordinate to PRIV_ARCH)
 port (
   clk          : in  std_logic;
   rst          : in  std_logic;
   db_o         : out cpu_data_o_t;
   db_lock      : out std_logic;
   db_i         : in  cpu_data_i_t;
   inst_o       : out cpu_instruction_o_t;
   inst_i       : in  cpu_instruction_i_t;
   debug_o      : out cpu_debug_o_t;
   debug_i      : in  cpu_debug_i_t;
   event_o      : out cpu_event_o_t;
   event_i      : in  cpu_event_i_t;
   cop_o        : out cop_o_t;
   cop_i        : in  cop_i_t;
   priv_o       : out cpu_priv_o_t := NULL_PRIV_O;  -- SH-4 EXPEVT/INTEVT/TRA (J4)
   mmu_o        : out cpu_mmu_o_t  := NULL_MMU_O);  -- TLB PA tags for cache wrappers (J4+MMU_ARCH)
end entity cpu;

architecture stru of cpu is
   signal slot, if_stall : std_logic;
   signal mac_i : mult_i_t;
   signal mac_o : mult_o_t;
   signal reg : reg_ctrl_t;
   signal func : func_ctrl_t;
   signal mem : mem_ctrl_t;
   signal instr : instr_ctrl_t;
   signal mac : mac_ctrl_t;
   signal pc : pc_ctrl_t;
   signal buses : buses_ctrl_t;
   signal t_bcc : std_logic;
   signal ibit : std_logic_vector(3 downto 0);
   signal if_dr : std_logic_vector(15 downto 0);
   signal if_dr_next : std_logic_vector(15 downto 0);
   signal enter_debug, debug, mask_int : std_logic;
   signal event_ack    : std_logic;
   signal slp_o        : std_logic;
   signal sr : sr_ctrl_t;
   signal illegal_delay_slot : std_logic;
   signal illegal_instr : std_logic;
   signal coproc : coproc_ctrl_t;
   signal coproc_decode : coproc_ctrl_t;
   signal copreg : std_logic_vector(7 downto 0);
   -- Intermediate bus signals so TLB can read addresses (VHDL-93: out ports unreadable).
   signal sig_db_o   : cpu_data_o_t;
   signal sig_inst_o : cpu_instruction_o_t;
   -- Datapath MMU state exported for TLB (MMU_ARCH only; tied-off otherwise).
   signal dp_mmu_regs : mmu_reg_t;
   signal dp_sr       : sr_t;
   -- TLB output signals (Task 8 will consume hit/prot; mmu_o carries PA tags out).
   signal tlb_i_hit  : std_logic;
   signal tlb_d_hit  : std_logic;
   signal tlb_i_prot : std_logic;
   signal tlb_d_prot : std_logic;
begin

   event_o.ack  <= event_ack;
   event_o.lvl  <= ibit;
   event_o.slp  <= slp_o;
   event_o.dbg  <= debug;

   u_decode: decode
     port map (clk => clk, rst => rst, slot => slot,
      enter_debug => enter_debug, debug => debug,
      if_dr => if_dr, if_dr_next => if_dr_next, if_stall => if_stall,
      illegal_delay_slot => illegal_delay_slot,
      illegal_instr => illegal_instr,
      mac_busy => mac_o.busy,
      reg => reg, func => func, sr => sr, mac => mac, mem => mem, instr => instr, pc => pc,
      buses => buses,
      coproc => coproc_decode, copreg => copreg,
      t_bcc => t_bcc,
      event_i => event_i, event_ack => event_ack,
      ibit => ibit,
      slp => slp_o,
      mask_int => mask_int);
   u_mult : mult port map (clk => clk, rst => rst, slot => slot, a => mac_i, y => mac_o);
      mac_i.wr_m1 <= mac.com1; mac_i.command <= mac.com2;
      mac_i.wr_mach <= mac.wrmach; mac_i.wr_macl <= mac.wrmacl;

   u_datapath : datapath generic map (PRIV_ARCH => PRIV_ARCH, MMU_ARCH => MMU_ARCH) port map (clk => clk, rst => rst, slot => slot,
      debug => debug, enter_debug => enter_debug,
      db_lock => db_lock, db_o => sig_db_o, db_i => db_i, inst_o => sig_inst_o, inst_i => inst_i,
      debug_o => debug_o, debug_i => debug_i,
      reg => reg, func => func, sr_ctrl => sr, mac => mac, mem => mem, pc_ctrl => pc,
      buses => buses, coproc => coproc, instr => instr,
      macin1 => mac_i.in1, macin2 => mac_i.in2, mach => mac_o.mach, macl => mac_o.macl,
      mult_stall => mac_o.slot_stall,
      mac_s => mac_i.s,
      t_bcc => t_bcc, ibit => ibit, if_dr => if_dr, if_dr_next => if_dr_next, if_stall => if_stall,
      mask_int => mask_int,
      illegal_delay_slot => illegal_delay_slot,
      illegal_instr => illegal_instr,
      copreg => copreg,
      cop_i => cop_i, cop_o => cop_o,
      priv_o => priv_o,
      mmu_regs_o => dp_mmu_regs,
      sr_o       => dp_sr);

  db_o   <= sig_db_o;
  inst_o <= sig_inst_o;

  coproc.cpu_data_mux <= coproc_decode.cpu_data_mux when COPRO_DECODE
                         else DBUS;
  coproc.coproc_cmd <= coproc_decode.coproc_cmd when COPRO_DECODE
                         else NOP;

  -- TLB instantiation (MMU_ARCH=true only).
  -- The TLB is combinational for lookups; it is clocked only for TI flush and
  -- LDTLB writes (both driven from Task 7). For now tlb_wr and ti are '0'.
  g_mmu : if MMU_ARCH generate
    signal i_va_32   : std_logic_vector(31 downto 0);
    signal d_va_32   : std_logic_vector(31 downto 0);
    signal i_at_translated : std_logic;
    signal d_at_translated : std_logic;
    signal tlb_i_pa  : std_logic_vector(18 downto 0);
    signal tlb_d_pa  : std_logic_vector(18 downto 0);
  begin
    -- Reconstruct 32-bit VAs from the registered bus outputs.
    -- inst_o.a is PA[31:1]; bit 0 is always 0 for instruction fetch.
    -- db_o.a is the full 32-bit data VA.
    i_va_32 <= sig_inst_o.a & '0';
    d_va_32 <= sig_db_o.a;

    -- AT-translated: address translation is active for P0 and P3 segments.
    -- P1/P2 are fixed-translate (no TLB); P4 is kernel-only MMIO.
    i_at_translated <= dp_mmu_regs.mmucr(0) when
                       (seg_decode(i_va_32) = SEG_P0 or seg_decode(i_va_32) = SEG_P3)
                       else '0';
    d_at_translated <= dp_mmu_regs.mmucr(0) when
                       (seg_decode(d_va_32) = SEG_P0 or seg_decode(d_va_32) = SEG_P3)
                       else '0';

    u_tlb : entity work.tlb
      port map (
        clk      => clk,
        i_va     => i_va_32,
        i_pa_tag => tlb_i_pa,
        i_hit    => tlb_i_hit,
        i_prot   => tlb_i_prot,
        d_va     => d_va_32,
        d_we     => sig_db_o.wr,
        d_pa_tag => tlb_d_pa,
        d_hit    => tlb_d_hit,
        d_prot   => tlb_d_prot,
        asid     => dp_mmu_regs.asidr(15 downto 0),
        md       => dp_sr.md,
        at       => dp_mmu_regs.mmucr(0),
        tlb_wr   => '0',
        pteh_vpn => dp_mmu_regs.pteh(31 downto 12),
        ptel     => dp_mmu_regs.ptel,
        asidr    => dp_mmu_regs.asidr(15 downto 0),
        ti       => '0');

    mmu_o.i_pa_tag <= tlb_i_pa;
    mmu_o.i_at     <= i_at_translated;
    mmu_o.d_pa_tag <= tlb_d_pa;
    mmu_o.d_at     <= d_at_translated;
  end generate g_mmu;

  g_no_mmu : if not MMU_ARCH generate
    mmu_o <= NULL_MMU_O;
  end generate g_no_mmu;

end architecture stru;
