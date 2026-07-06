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
   signal dp_tlb_squash : std_logic;  -- datapath tlb_squash, gates MAC accumulate on faulting pass
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
   -- MMU address-translation intermediates (driven by g_mmu only; VHDL-93 forbids
   -- signal declarations inside a generate body, so they live here).
   signal i_va_32         : std_logic_vector(31 downto 0);
   signal d_va_32         : std_logic_vector(31 downto 0);
   signal i_at_translated : std_logic;
   signal d_at_translated : std_logic;
   signal tlb_i_pa        : std_logic_vector(14 downto 0);
   signal tlb_d_pa        : std_logic_vector(14 downto 0);
   signal tlb_i_pa12      : std_logic;
   signal tlb_d_pa12      : std_logic;
   signal tlb_i_page_mask : std_logic_vector(3 downto 0);
   signal tlb_d_page_mask : std_logic_vector(3 downto 0);
   signal tlb_i_c         : std_logic;
   signal tlb_d_c         : std_logic;
   -- TLB exception detection outputs (fed to decode and datapath).
   signal tlb_exc_en   : std_logic;
   signal tlb_exc_kind : tlb_exc_kind_t;
   signal tlb_exc_pend : std_logic;
   signal tlb_fault_va : std_logic_vector(31 downto 0);
   -- D-store-on-bus is itself faulting (drives the external demote-to-read).
   signal d_store_faulting : std_logic;
   signal tlb_exc_expevt : std_logic_vector(11 downto 0);
   -- '1' when the pending TLB fault is an I-fetch fault (IMISS/IPROT). The
   -- datapath uses it to capture the I-side restart PC from the faulting fetch
   -- VA (tlb_fault_va) instead of the D-side ma_pc shadow.
   signal tlb_exc_is_i : std_logic;
   -- Dynamic delay-slot flag (decode->datapath): lets a delay-slot D-side TLB
   -- fault restart at the branch. Phase-aligned to the EX control in decode.
   signal dslot : std_logic;
   -- Per-instruction fetch-PC round-trip (datapath -> decode -> datapath): carries
   -- the faulting instruction's OWN PC EX-aligned so a delay-slot D-fault restarts
   -- at the branch. dp_if_pc = datapath's if_dr-stage PC; dec_ex_if_pc = decode's
   -- EX-aligned copy shadowed at the MA-launch.
   signal dp_if_pc     : std_logic_vector(31 downto 0);
   signal dec_ex_if_pc : std_logic_vector(31 downto 0);
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
      mask_int => mask_int,
      tlb_exc_en   => tlb_exc_en,
      tlb_exc_kind => tlb_exc_kind,
      if_pc        => dp_if_pc,
      delay_slot   => dslot,
      ex_if_pc     => dec_ex_if_pc);
   u_mult : mult port map (clk => clk, rst => rst, slot => slot, a => mac_i, y => mac_o);
      mac_i.wr_m1 <= mac.com1; mac_i.command <= mac.com2;
      mac_i.wr_mach <= mac.wrmach; mac_i.wr_macl <= mac.wrmacl;
      mac_i.acc_squash <= dp_tlb_squash;

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
      sr_o       => dp_sr,
      tlb_squash_o => dp_tlb_squash,
      tlb_exc_pend => tlb_exc_pend,
      tlb_fault_va => tlb_fault_va,
      tlb_exc_expevt => tlb_exc_expevt,
      delay_slot => dslot,
      tlb_exc_is_i => tlb_exc_is_i,
      if_pc => dp_if_pc,
      ex_if_pc => dec_ex_if_pc);

  -- D-store TLB-fault write suppression (J4+MMU_ARCH). A store that misses or
  -- violates the TLB must not mutate memory, but a write acks and commits in the
  -- same cycle the fault is detected combinationally -- one cycle before the
  -- registered TLB exception request can latch. Demote the faulting store to a
  -- harmless READ at the EXTERNAL bus (memory untouched); this also holds the
  -- access in-flight across the exception-latch boundary exactly as a faulting
  -- load does. The internal sig_db_o keeps wr='1' so the TLB still sees a write
  -- and detects the fault. Must be on the external db_o, after the TLB has
  -- consumed sig_db_o; gating the internal db_o on tlb_exc_pend forms a comb loop.
  -- True iff the D-store currently on the bus is ITSELF the faulting access
  -- (its own TLB lookup missed or is protection-violating). This must NOT use
  -- the global tlb_exc_pend: that signal also rises for an I-side fault, and
  -- for the *next* instruction's fault while a prior, already-resolved store is
  -- still completing its write on the bus. Demoting on tlb_exc_pend alone would
  -- collateral-damage such a non-faulting in-flight store (back-to-back fault:
  -- a resumed store followed by another faulting access loses its write). Key
  -- the demote on the D-side's own hit/prot status instead.
  d_store_faulting <= '1' when MMU_ARCH and d_at_translated = '1'
                              and sig_db_o.en = '1' and sig_db_o.wr = '1'
                              and (tlb_d_hit = '0' or tlb_d_prot = '1')
                      else '0';

  g_dstore_squash : if MMU_ARCH generate
    process(sig_db_o, d_store_faulting, d_at_translated, tlb_d_hit,
            tlb_d_pa, tlb_d_pa12, tlb_d_page_mask)
      variable offm   : std_logic_vector(15 downto 0);
      variable ppn_lo : std_logic_vector(15 downto 0);
    begin
      db_o <= sig_db_o;
      if d_store_faulting = '1' then
        db_o.rd <= '1';
        db_o.wr <= '0';
        db_o.we <= "0000";
      end if;
      -- SH P1 untranslated fold on the external data bus (P1 only; P2 holds
      -- the sim result MMIO at 0xBCDE0010 and must pass through unmasked).
      if sig_db_o.a(31 downto 29) = "100" then
        db_o.a(31 downto 29) <= "000";
      elsif d_at_translated = '1' and tlb_d_hit = '1' then
        -- Variable-page relocation (docs/architecture/tlb.md). Per PA bit 12+p:
        -- VA (in-page offset) if p < 2*pm, else PPN (frame). PA[11:0]=VA, [31:28]=0.
        offm   := page_offset_mask(tlb_d_page_mask);
        ppn_lo := tlb_d_pa & tlb_d_pa12;   -- PPN[27:12]: bit15=PPN[27] .. bit0=PPN[12]
        db_o.a(31 downto 28) <= "0000";
        db_o.a(27 downto 12) <= (ppn_lo and not offm) or (sig_db_o.a(27 downto 12) and offm);
      end if;
    end process;
  end generate g_dstore_squash;
  g_no_dstore_squash : if not MMU_ARCH generate
    db_o <= sig_db_o;
  end generate g_no_dstore_squash;

  g_inst_p1_fold : if MMU_ARCH generate
    -- SH P1 (0x8000_0000-0x9FFF_FFFF) is untranslated: PA = VA and 0x1FFFFFFF.
    -- inst_o.a is PA[31:1] (indices preserved 31..1, not reindexed), so P1 is
    -- a(31 downto 29)="100". Fold AFTER i_va_32 has sampled sig_inst_o.a, so
    -- seg_decode still sees the true P1 VA.
    process(sig_inst_o, i_at_translated, tlb_i_hit, tlb_i_pa, tlb_i_pa12, tlb_i_page_mask)
      variable offm   : std_logic_vector(15 downto 0);
      variable ppn_lo : std_logic_vector(15 downto 0);
    begin
      inst_o <= sig_inst_o;
      if sig_inst_o.a(31 downto 29) = "100" then
        inst_o.a(31 downto 29) <= "000";
      elsif i_at_translated = '1' and tlb_i_hit = '1' then
        offm   := page_offset_mask(tlb_i_page_mask);
        ppn_lo := tlb_i_pa & tlb_i_pa12;
        inst_o.a(31 downto 28) <= "0000";
        inst_o.a(27 downto 12) <= (ppn_lo and not offm) or (sig_inst_o.a(27 downto 12) and offm);
      end if;
    end process;
  end generate g_inst_p1_fold;
  g_inst_no_fold : if not MMU_ARCH generate
    inst_o <= sig_inst_o;
  end generate g_inst_no_fold;

  coproc.cpu_data_mux <= coproc_decode.cpu_data_mux when COPRO_DECODE
                         else DBUS;
  coproc.coproc_cmd <= coproc_decode.coproc_cmd when COPRO_DECODE
                         else NOP;

  -- TLB instantiation (MMU_ARCH=true only).
  -- The TLB is combinational for lookups; it is clocked only for TI flush and
  -- LDTLB writes: tlb_wr comes from decoder (sr.tlb_wr); ti is MMUCR bit[2].
  g_mmu : if MMU_ARCH generate
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
        i_pa_tag    => tlb_i_pa,
        i_pa12      => tlb_i_pa12,
        i_page_mask => tlb_i_page_mask,
        i_c         => tlb_i_c,
        i_hit    => tlb_i_hit,
        i_prot   => tlb_i_prot,
        d_va     => d_va_32,
        d_we     => sig_db_o.wr,
        d_pa_tag    => tlb_d_pa,
        d_pa12      => tlb_d_pa12,
        d_page_mask => tlb_d_page_mask,
        d_c         => tlb_d_c,
        d_hit    => tlb_d_hit,
        d_prot   => tlb_d_prot,
        asid     => dp_mmu_regs.asidr(15 downto 0),
        md       => dp_sr.md,
        at       => dp_mmu_regs.mmucr(0),
        tlb_wr   => sr.tlb_wr,
        pteh_vpn => dp_mmu_regs.pteh(31 downto 12),
        ptel     => dp_mmu_regs.ptel,
        asidr    => dp_mmu_regs.asidr(15 downto 0),
        ti       => dp_mmu_regs.mmucr(2));

    mmu_o.i_pa_tag <= tlb_i_pa;
    mmu_o.i_at     <= i_at_translated;
    mmu_o.i_c      <= tlb_i_c;
    mmu_o.d_pa_tag <= tlb_d_pa;
    mmu_o.d_at     <= d_at_translated;
    mmu_o.d_c      <= tlb_d_c;

    -- TLB exception detection: priority I-side > D-side; miss > prot.
    -- tlb_exc_en is combinatorial (no register); it is sampled by decode_core
    -- on each slot and triggers the appropriate system microcode entry.
    -- tlb_exc_pend and tlb_fault_va go to datapath to write TEA/PTEH.
    process(i_at_translated, d_at_translated,
            sig_inst_o, sig_db_o,
            tlb_i_hit, tlb_i_prot, tlb_d_hit, tlb_d_prot,
            i_va_32, d_va_32, dp_sr)
      variable exc_en   : std_logic;
      variable exc_kind : tlb_exc_kind_t;
      variable fva      : std_logic_vector(31 downto 0);
    begin
      exc_en   := '0';
      exc_kind := IMISS;
      fva      := (others => '0');
      -- Block further exceptions while one is being handled. Without this, a
      -- second faulting access (the instruction right after a faulting one, whose
      -- access already launched -- back-to-back D-faults) dispatches a SECOND
      -- exception entry that re-saves SSR<-SR while already in exception mode
      -- (RB=1). The handler's LDTLB.R/RTE then restores RB=1, so the resumed user
      -- code reads bank-1 (uninitialised) registers and corrupts addresses.
      -- SR.RB is this design's handler indicator: user code runs RB=0, exception
      -- entry sets RB=1, and LDTLB.R/RTE restores it -- so RB=1 means "in the
      -- handler". (SR.BL, the architectural block bit, is left set from reset by
      -- the bare-metal guards, so it cannot serve as the gate here.) The lingering
      -- second access then raises no exception while RB=1; it re-faults cleanly
      -- after the handler returns (RB back to 0). (J4+MMU_ARCH.)
      if i_at_translated = '1' and sig_inst_o.en = '1' and dp_sr.rb = '0' then
        if tlb_i_hit = '0' then
          exc_en   := '1';
          exc_kind := IMISS;
          fva      := i_va_32;
        elsif tlb_i_prot = '1' then
          exc_en   := '1';
          exc_kind := IPROT;
          fva      := i_va_32;
        end if;
      end if;
      if exc_en = '0' and d_at_translated = '1' and sig_db_o.en = '1' and dp_sr.rb = '0' then
        if tlb_d_hit = '0' then
          if sig_db_o.wr = '1' then
            exc_en   := '1';
            exc_kind := DMISS_W;
          else
            exc_en   := '1';
            exc_kind := DMISS_R;
          end if;
          fva := d_va_32;
        elsif tlb_d_prot = '1' then
          if sig_db_o.wr = '1' then
            exc_en   := '1';
            exc_kind := DPROT_W;
          else
            exc_en   := '1';
            exc_kind := DPROT_R;
          end if;
          fva := d_va_32;
        end if;
      end if;
      tlb_exc_en   <= exc_en;
      tlb_exc_kind <= exc_kind;
      tlb_exc_pend <= exc_en;
      tlb_fault_va <= fva;
      -- I-fetch faults (IMISS/IPROT) come only from the i_at_translated branch
      -- above; flag them so the datapath captures the I-side restart PC.
      if exc_en = '1' and (exc_kind = IMISS or exc_kind = IPROT) then
        tlb_exc_is_i <= '1';
      else
        tlb_exc_is_i <= '0';
      end if;
    end process;

    -- SH-4 EXPEVT code for the detected fault kind, captured into EXPEVT as a
    -- datapath hardware side-effect (see datapath.vhm). IMISS=0x040 DMISS_R=0x060
    -- DMISS_W=0x080 IPROT=0x0A0 DPROT_R/W=0x0C0.
    with tlb_exc_kind select tlb_exc_expevt <=
      x"040" when IMISS,
      x"060" when DMISS_R,
      x"080" when DMISS_W,
      x"0A0" when IPROT,
      x"0C0" when DPROT_R,
      x"0C0" when DPROT_W;
  end generate g_mmu;

  g_no_mmu : if not MMU_ARCH generate
    mmu_o        <= NULL_MMU_O;
    tlb_exc_en   <= '0';
    tlb_exc_kind <= IMISS;
    tlb_exc_pend <= '0';
    tlb_fault_va <= (others => '0');
    tlb_exc_expevt <= (others => '0');
  end generate g_no_mmu;

end architecture stru;
