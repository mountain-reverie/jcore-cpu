library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.cpu2j0_pack.all;
  use work.decode_pack.all;
  use work.cpu2j0_components_pack.all;
  use work.datapath_pack.all;
  use work.mult_pkg.all;
  use work.divider_pkg.all;

entity cpu is
  generic (
    copro_decode : boolean := true;
    priv_arch    : boolean := false;
    sh2a_arch    : boolean := false; -- SH-2A extensions (inert plumbing only)
    -- Elaboration tag: distinguishes two cpu instances that share this entity/
    -- arch/generics but whose nested register-file architecture is bound
    -- differently per instance by the enclosing cpus configuration (e.g. core0=
    -- register_file(ebr), core1=register_file(two_bank)). Without a differing
    -- generic the ghdl->yosys frontend hashes both to one module name and errors
    -- with "Re-definition of module". No functional effect.
    core_id : integer := 0
  );
  port (
    clk     : in    std_logic;
    rst     : in    std_logic;
    db_o    : out   cpu_data_o_t;
    db_lock : out   std_logic;
    db_i    : in    cpu_data_i_t;
    inst_o  : out   cpu_instruction_o_t;
    inst_i  : in    cpu_instruction_i_t;
    debug_o : out   cpu_debug_o_t;
    debug_i : in    cpu_debug_i_t;
    event_o : out   cpu_event_o_t;
    event_i : in    cpu_event_i_t;
    cop_o   : out   cop_o_t;
    cop_i   : in    cop_i_t;
    priv_o  : out   cpu_priv_o_t := NULL_PRIV_O; -- SH-4 EXPEVT/INTEVT/TRA (J4)
    mmu_o   : out   cpu_mmu_o_t  := NULL_MMU_O   -- TLB PA tags for cache wrappers (J4)
  );
end entity cpu;

architecture stru of cpu is

  signal slot, if_stall : std_logic;
  signal mac_i          : mult_i_t;
  signal mac_o          : mult_o_t;
  signal dp_tlb_squash  : std_logic; -- datapath tlb_squash, gates MAC accumulate on faulting pass
  -- SH-2A DIVU/DIVS divider unit (Task 2). div_i/div_o mirror mac_i/mac_o;
  -- combined_mac_busy/combined_mult_stall fold div_o.busy into the same
  -- stall paths mac_o.busy/mac_o.slot_stall already feed (decode mac_stall
  -- and datapath mult_stall respectively), SH2A_ARCH-gated so base J1/J2/J4
  -- see exactly mac_o.busy/mac_o.slot_stall as before.
  signal div_i               : divider_i_t;
  signal div_o               : divider_o_t;
  signal combined_mac_busy   : std_logic;
  signal combined_mult_stall : std_logic;
  signal reg                 : reg_ctrl_t;
  signal func                : func_ctrl_t;
  signal mem                 : mem_ctrl_t;
  signal instr               : instr_ctrl_t;
  signal mac                 : mac_ctrl_t;
  signal pc                  : pc_ctrl_t;
  signal buses               : buses_ctrl_t;
  signal t_bcc               : std_logic;
  signal ibit                : std_logic_vector(3 downto 0);
  signal if_dr               : std_logic_vector(15 downto 0);
  signal if_dr_next          : std_logic_vector(15 downto 0);
  signal enter_debug         : std_logic;
  signal debug               : std_logic;
  signal mask_int            : std_logic;
  signal event_ack           : std_logic;
  signal slp_o               : std_logic;
  signal sr                  : sr_ctrl_t;
  signal illegal_delay_slot  : std_logic;
  signal illegal_instr       : std_logic;
  signal coproc              : coproc_ctrl_t;
  signal coproc_decode       : coproc_ctrl_t;
  signal copreg              : std_logic_vector(7 downto 0);
  -- Intermediate bus signals so TLB can read addresses (VHDL-93: out ports unreadable).
  signal sig_db_o   : cpu_data_o_t;
  signal sig_inst_o : cpu_instruction_o_t;
  -- Datapath MMU state exported for TLB (PRIV_ARCH only; tied-off otherwise).
  signal dp_mmu_regs : mmu_reg_t;
  signal dp_sr       : sr_t;
  -- TLB output signals (Task 8 will consume hit/prot; mmu_o carries PA tags out).
  signal tlb_i_hit      : std_logic;
  signal tlb_d_hit      : std_logic;
  signal tlb_i_prot     : std_logic;
  signal tlb_d_prot     : std_logic;
  signal tlb_i_multihit : std_logic; -- S-I5: >1 usable I-side match (fatal)
  signal tlb_d_multihit : std_logic; -- S-I5: >1 usable D-side match (fatal)
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
  -- Cacheability actually handed to the D-cache wrapper. Readable internally
  -- (mmu_o is an out port, and VHDL-93 forbids reading it) so the R1 assert
  -- below can check it.
  signal mmu_d_at_i : std_logic;
  signal mmu_d_c_i  : std_logic;
  -- TLB exception detection outputs (fed to decode and datapath).
  signal tlb_exc_en   : std_logic;
  signal tlb_exc_kind : tlb_exc_kind_t;
  signal tlb_exc_pend : std_logic;
  -- '1' while the outstanding instruction fetch has a translation fault. Feeds
  -- the datapath's per-instruction status vector (if_fault). Narrowed to
  -- IMISS/IPROT -- the kinds that are actually deferred.
  -- inst_fault_prot: kind of that fault ('1' = IPROT, '0' = IMISS), recorded
  -- alongside it. dp_if_fault/dp_if_fault_prot: the same pair once it has landed
  -- with the instruction in if_dr -- decode raises TLB_IMISS/TLB_IPROT from them
  -- at that instruction's dispatch boundary (fault-on-use). dec_id_dslot: decode's
  -- ID-aligned delay-slot flag, returned to the datapath so its deferred capture
  -- can apply the -2 restart bias. See if_fault in components_pkg.vhd.
  signal inst_fault         : std_logic;
  signal inst_fault_prot    : std_logic;
  signal dp_if_fault        : std_logic;
  signal dp_if_fault_prot   : std_logic;
  signal dec_id_dslot       : std_logic;
  signal dec_texc_defer_cap : std_logic;
  signal tlb_fault_va       : std_logic_vector(31 downto 0);
  -- D-store-on-bus is itself faulting (drives the external demote-to-read).
  signal d_store_faulting : std_logic;
  -- P4 privilege violation, from the datapath: a user-mode (SR.MD='0') data
  -- access to the supervisor-only P4 control-register segment was refused.
  -- Registered in the datapath and therefore already one cycle behind the
  -- access -- the same pipeline point at which a D-side TLB fault is detected
  -- here (this process reads sig_db_o, the registered bus request). The
  -- faulting VA is not a separate wire: the datapath parks it in TEA at the
  -- refusal and it is read back below out of dp_mmu_regs. See the p4_viol_o
  -- port declaration in core/datapath.vhm.
  signal dp_p4_viol     : std_logic;
  signal dp_p4_viol_wr  : std_logic;
  signal tlb_exc_expevt : std_logic_vector(11 downto 0);
  -- MMUFSR composition (KIND/USER/PROT/ITLB/WRITE nibble+bits, no VALID --
  -- datapath ORs in VALID on capture). tlb_exc_kind is not a datapath port,
  -- so cpu.vhd composes this word here and passes it in, mirroring
  -- tlb_exc_expevt.
  signal tlb_exc_fsr : std_logic_vector(12 downto 0);
  -- '1' when the pending TLB fault is an I-fetch fault (IMISS/IPROT). The
  -- datapath uses it to capture the I-side restart PC from the faulting fetch
  -- VA (tlb_fault_va) instead of the D-side ex_if_pc derivation.
  signal tlb_exc_is_i : std_logic;
  -- '1' whenever the pending TLB fault's VA (tlb_fault_va) is an
  -- INSTRUCTION-FETCH VA -- i.e. it came from the i_at_translated branch
  -- below, for ANY exc_kind raised there (IMISS, IPROT, or MULTI_HIT).
  -- This is intentionally BROADER than tlb_exc_is_i: tlb_exc_is_i exists
  -- only to select the I-side restart-PC derivation, and is correctly
  -- narrowed to IMISS/IPROT there (MULTI_HIT dispatches through the
  -- General Illegal register-model exception, not the TLB restart-PC
  -- path -- see the comment below). tlb_exc_ifetch instead answers "is
  -- ma_numz/ma_base/ma_autoupd -- the D-side access shadow -- stale for
  -- THIS fault", which is true for every I-side fault kind, MULTI_HIT
  -- included: those shadows are never cleared on an instruction that
  -- issues no data access, so an I-side MULTI_HIT on an instruction
  -- following a genuine @Rn+/@-Rn access sees the PREVIOUS instruction's
  -- stale shadow. Used by the datapath to gate tlb_restore_pend/pend2_r
  -- arming and z_grace. Do not reuse tlb_exc_is_i for that purpose (that
  -- conflation was the bug: an I-side MULTI_HIT armed a D-side restore
  -- from a stale shadow because tlb_exc_is_i='0' for it).
  signal tlb_exc_ifetch : std_logic;
  -- Data-bus input as seen by the datapath. ack is withheld while the hardware
  -- TSB walker owns the external bus, so the faulting access is held stable and
  -- replays once the translation is installed.
  signal dp_db_i : cpu_data_i_t;
  -- Instruction-bus input as seen by the datapath. ack is withheld while an
  -- I-SIDE walk is armed or running, so the faulting fetch is held in flight
  -- (datapath.vhm's transfer is gated on `inst_o.en = '1' and inst_i.ack = '1'`,
  -- and it re-presents the same inst_o until it sees one) and replays against
  -- the installed translation afterwards. Without this the fetch completed
  -- against the UNTRANSLATED VA during the suppression window and junk
  -- executed. Exact mirror of dp_db_i.ack on the data side.
  signal dp_inst_i : cpu_instruction_i_t;
  -- Hardware TSB walker (core/tlb_walk.vhd) interface.
  signal walk_busy : std_logic;
  signal walk_arm  : std_logic;
  -- Per-side miss-exception suppression. See tlb_walk.vhd's `arm` comment.
  signal walk_supp_i  : std_logic;
  signal walk_supp_d  : std_logic;
  signal walk_own     : std_logic;
  signal walk_bus_ack : std_logic;
  signal walk_req     : std_logic;
  signal walk_va      : std_logic_vector(31 downto 0);
  signal walk_va_r    : std_logic_vector(31 downto 0);
  signal walk_d_miss  : std_logic;
  signal walk_i_miss  : std_logic;
  signal d_fault_held : std_logic;
  -- UNGATED restatement of the I-side miss condition, and "an I-side walk is
  -- being armed this cycle", used ONLY by the older-instruction-first ordering
  -- assertion below. Deliberately NOT derived from walk_i_miss: an assertion
  -- written in terms of the gated signal is tautological and cannot fire when
  -- the gate is removed.
  signal walk_i_miss_raw : std_logic;
  signal walk_i_arm_raw  : std_logic;
  signal walk_install    : std_logic;
  signal walk_ptel       : std_logic_vector(31 downto 0);
  signal walk_bus_a      : std_logic_vector(31 downto 0);
  signal walk_bus_en     : std_logic;
  -- '1' while the walk in progress is an I-SIDE walk. Registered at the arming
  -- cycle, when walk_i_miss/walk_d_miss are live and mutually exclusive.
  signal walk_side_i    : std_logic;
  signal walk_cnt_walks : unsigned(15 downto 0);
  signal walk_cnt_hits  : unsigned(15 downto 0);
  -- TLB install-port write enables, one PER ARRAY: the hardware walker is the
  -- sole installer and installs only into the side that faulted.
  signal itlb_wr : std_logic;
  signal dtlb_wr : std_logic;
  -- I->D shadow fill (see p_tlb_shadow). The install data is latched here for
  -- the cycle after an ITLB install rather than re-read from the walker.
  signal dtlb_spec   : std_logic;
  signal dtlb_vpn    : std_logic_vector(31 downto 12);
  signal dtlb_ptel   : std_logic_vector(31 downto 0);
  signal dtlb_asid   : std_logic_vector(15 downto 0);
  signal shadow_wr   : std_logic;
  signal shadow_vpn  : std_logic_vector(31 downto 12);
  signal shadow_ptel : std_logic_vector(31 downto 0);
  signal shadow_asid : std_logic_vector(15 downto 0);
  -- Install counters (anti-vacuity, non-architectural; P4 TLBINST at
  -- 0xFF000058). They count ACTUAL slot writes, which is why they are driven
  -- from each array's `wrote` pulse and not from itlb_wr/dtlb_wr: a
  -- speculative shadow install that finds the page already resident asserts
  -- dtlb_wr and writes nothing, and telling those two cases apart is exactly
  -- what guard mmudshadow needs to observe.
  signal itlb_wrote  : std_logic;
  signal dtlb_wrote  : std_logic;
  signal cnt_itlb_wr : unsigned(15 downto 0) := (others => '0');
  signal cnt_dtlb_wr : unsigned(15 downto 0) := (others => '0');
  signal tlb_ptel_mx : std_logic_vector(31 downto 0);
  signal tlb_vpn_mx  : std_logic_vector(19 downto 0);
  -- Dynamic delay-slot flag (decode->datapath): lets a delay-slot D-side TLB
  -- fault restart at the branch. Phase-aligned to the EX control in decode.
  signal dslot : std_logic;
  -- Per-instruction fetch-PC round-trip (datapath -> decode -> datapath): carries
  -- the faulting instruction's OWN PC EX-aligned so a delay-slot D-fault restarts
  -- at the branch. dp_if_pc = datapath's if_dr-stage PC; dec_ex_if_pc = decode's
  -- EX-aligned copy shadowed at the MA-launch.
  signal dp_if_pc     : std_logic_vector(31 downto 0);
  signal dec_ex_if_pc : std_logic_vector(31 downto 0);

  -- S-I4: double-fault (any non-TLB exception taken while SR.RB=1, i.e. the
  -- exception context -- SPC/SSR -- is already live/un-restored from a prior
  -- exception) must NOT re-run the register-model SPC<-PC/SSR<-SR save: that
  -- would silently clobber the still-unsaved context of the first exception.
  -- TLB faults are already suppressed while dp_sr.rb='1' (above, tlb_exc_en
  -- process). Non-TLB exception entry (Interrupt/Error/General-Illegal/
  -- Slot-Illegal/TRAPA) is dispatched purely from the event_i the decoder
  -- sees, so gating it here -- by substituting a synthesized RESET_CPU event
  -- for decode's event_i input whenever RB=1 and an exception condition is
  -- live -- reuses the EXISTING "Reset CPU" register-model-free entry (reads
  -- PC/R15 from the reset vector at address 0, touches no SPC/SSR/EXPEVT;
  -- see system.toml "Reset CPU") as the defined non-recoverable outcome, with
  -- ZERO changes to decode_core/the generated decoder (PRIV_ARCH-gated; J1/J2
  -- byte-identical, and the sole cpu.vhd-local signal below elaborates away
  -- when PRIV_ARCH=false). Covers: (a) a real external Interrupt/Error event_i
  -- arriving while RB=1 (the canonical SH-4 double-fault), and (b) a nested
  -- General-Illegal-Instruction fault taken from inside a handler (RB=1) --
  -- the scenario mmudblflt.S exercises. Residual (documented, not gated):
  -- Slot-Illegal-in-a-delay-slot and a deliberately-executed nested TRAPA
  -- while RB=1 are not intercepted by this cpu.vhd-local gate (both would
  -- need decode_core.vhm's next_op mux itself to know about RB); left for a
  -- follow-on since they are far rarer double-fault triggers than an
  -- asynchronous Interrupt/Error or a nested illegal decode.
  signal event_i_gated : cpu_event_i_t;

begin

  event_o.ack <= event_ack;
  event_o.lvl <= ibit;
  event_o.slp <= slp_o;
  event_o.dbg <= debug;

  -- S-I4 double-fault gate: see event_i_gated declaration above.

  g_dblflt : if PRIV_ARCH generate

    process (event_i, illegal_instr, if_dr, dp_sr) is
    begin

      event_i_gated <= event_i;

      if (dp_sr.rb = '1') then
        if (event_i.en = '1' and (event_i.cmd = INTERRUPT or event_i.cmd = ERROR)) then
          -- Real async/error event arriving while the exception context is
          -- already live: the canonical SH-4 double fault.
          event_i_gated.cmd <= RESET_CPU;
          event_i_gated.vec <= (others => '0');
        elsif (illegal_instr = '1') then
          -- Nested General-Illegal-Instruction fault taken from inside a
          -- handler: synthesize the same defined-reset outcome.
          event_i_gated.en  <= '1';
          event_i_gated.cmd <= RESET_CPU;
          event_i_gated.vec <= (others => '0');
        elsif (if_dr(15 downto 8) = x"C3") then
          -- S-I4b: a deliberately-executed nested TRAPA (opcode 0xC3nn) while
          -- RB=1. TRAPA is a normal_op, not an illegal_instr / next_op
          -- exception arm, so the illegal_instr term above cannot see it. Its
          -- register-model entry would re-save SPC/SSR over the first
          -- exception's live context. Inject RESET_CPU at this dispatch point
          -- (before the entry commits, exactly like the illegal_instr case) so
          -- next_op's highest-priority event arm takes the reset instead of the
          -- TRAPA. A first-level TRAPA (syscall) runs at RB=0 and is untouched.
          event_i_gated.en  <= '1';
          event_i_gated.cmd <= RESET_CPU;
          event_i_gated.vec <= (others => '0');
        end if;
      end if;

    end process;

  end generate g_dblflt;

  g_no_dblflt : if not PRIV_ARCH generate
    event_i_gated <= event_i;
  end generate g_no_dblflt;

  -- Tie off the MMU-only counter signals when the MMU is absent.
  --
  -- walk_cnt_walks/walk_cnt_hits (the walker's) and cnt_itlb_wr/cnt_dtlb_wr
  -- (the TLB install counters) are driven inside g_mmu, but the datapath port
  -- map above reads all four UNCONDITIONALLY -- it is a single instantiation,
  -- not one per variant -- so on a PRIV_ARCH = false build they would have no
  -- driver at all.
  --
  -- A signal INITIALISER IS NOT A DRIVER. It settles simulation and nothing
  -- else: synthesis sees an undriven wire, i.e. a don't-care, not a constant
  -- zero. The resulting don't-care propagation is not confined to the dead
  -- port either -- it changes ABC's mapping decisions across the whole design.
  -- Measured on j2 (`synth/cpu_synth.sh ecp5-block`, deterministic, both
  -- numbers reproduced twice): adding just the two install counters to the
  -- port map moved `mult` 603 -> 909 LUT4 and `shifter` 5630 -> 5893, two
  -- blocks this file does not otherwise touch, for +526 LUT4 total on a
  -- variant that has no MMU at all. Tying them off puts every one of those
  -- back exactly. The walker's two counters had the same latent defect before
  -- the install counters existed and are fixed here with them.

  g_no_mmu_counters : if not PRIV_ARCH generate
    walk_cnt_walks <= (others => '0');
    walk_cnt_hits  <= (others => '0');
    cnt_itlb_wr    <= (others => '0');
    cnt_dtlb_wr    <= (others => '0');
  end generate g_no_mmu_counters;

  -- H-M3 defense-in-depth invariant: the banked exception state (RB=1) must
  -- never be live in user mode (MD=0) -- if any future path reached this it
  -- would mean untrusted code could observe/abuse bank-1 registers. Sim-only
  -- assertion (a synthesizable guard would need to force a state no RTL path
  -- should ever produce -- not cheap and not needed for a sim-verifiable
  -- invariant); PRIV_ARCH-gated so it is inert as a comment-only signal on
  -- non-PRIV_ARCH (J1/J2) builds.
  -- pragma translate_off

  g_rb_md_assert : if PRIV_ARCH generate

    process (clk) is
    begin

      if rising_edge(clk) then
        assert not (dp_sr.rb = '1' and dp_sr.md = '0')
          report "S-I4/H-M3: SR.RB=1 with SR.MD=0 -- banked exception state live in user mode"
          severity failure;
      end if;

    end process;

  end generate g_rb_md_assert;

  -- pragma translate_on

  u_decode : component decode
    port map (
      clk                => clk,
      rst                => rst,
      slot               => slot,
      enter_debug        => enter_debug,
      debug              => debug,
      if_dr              => if_dr,
      if_dr_next         => if_dr_next,
      if_stall           => if_stall,
      illegal_delay_slot => illegal_delay_slot,
      illegal_instr      => illegal_instr,
      mac_busy           => combined_mac_busy,
      reg                => reg,
      func               => func,
      sr                 => sr,
      mac                => mac,
      mem                => mem,
      instr              => instr,
      pc                 => pc,
      buses              => buses,
      coproc             => coproc_decode,
      copreg             => copreg,
      t_bcc              => t_bcc,
      event_i            => event_i_gated,
      event_ack          => event_ack,
      ibit               => ibit,
      slp                => slp_o,
      mask_int           => mask_int,
      tlb_exc_en         => tlb_exc_en,
      tlb_exc_kind       => tlb_exc_kind,
      if_pc              => dp_if_pc,
      delay_slot         => dslot,
      if_fault           => dp_if_fault,
      if_fault_prot      => dp_if_fault_prot,
      id_delay_slot      => dec_id_dslot,
      texc_defer_cap     => dec_texc_defer_cap,
      ex_if_pc           => dec_ex_if_pc
    );

  u_mult : component mult
    port map (
      clk  => clk,
      rst  => rst,
      slot => slot,
      a    => mac_i,
      y    => mac_o
    );

  mac_i.wr_m1      <= mac.com1; mac_i.command <= mac.com2;
  mac_i.wr_mach    <= mac.wrmach; mac_i.wr_macl <= mac.wrmacl;
  mac_i.acc_squash <= dp_tlb_squash;

  -- SH-2A DIVU/DIVS divider unit (Task 2), mirroring u_mult above. Tied off
  -- on base (sh2a_arch=false): div_i.start is driven '0' by datapath's
  -- g_div_off, so u_div never runs there, and div_o.busy/.quotient are
  -- excluded from the base stall/writeback paths below.

  g_div : if sh2a_arch generate

    u_div : component divider
      port map (
        clk => clk,
        rst => rst,
        a   => div_i,
        y   => div_o
      );

  end generate g_div;

  g_div_off : if not sh2a_arch generate
    div_o.busy     <= '0';
    div_o.quotient <= (others => '0');
  end generate g_div_off;

  -- div_o.busy is tied '0' by g_div_off on base (sh2a_arch=false), so these
  -- ORs are exactly mac_o.busy/mac_o.slot_stall there -- byte-identical.
  combined_mac_busy   <= mac_o.busy or div_o.busy;
  combined_mult_stall <= mac_o.slot_stall or div_o.busy;

  u_datapath : component datapath
    generic map (
      priv_arch => priv_arch, sh2a_arch => sh2a_arch
    )
    port map (
      clk                => clk,
      rst                => rst,
      slot               => slot,
      debug              => debug,
      enter_debug        => enter_debug,
      db_lock            => db_lock,
      db_o               => sig_db_o,
      db_i               => dp_db_i,
      inst_o             => sig_inst_o,
      inst_i             => dp_inst_i,
      debug_o            => debug_o,
      debug_i            => debug_i,
      reg                => reg,
      func               => func,
      sr_ctrl            => sr,
      mac                => mac,
      mem                => mem,
      pc_ctrl            => pc,
      buses              => buses,
      coproc             => coproc,
      instr              => instr,
      macin1             => mac_i.in1,
      macin2             => mac_i.in2,
      mach               => mac_o.mach,
      macl               => mac_o.macl,
      mult_stall         => combined_mult_stall,
      mac_s              => mac_i.s,
      div_dividend       => div_i.dividend,
      div_divisor        => div_i.divisor,
      div_start          => div_i.start,
      div_is_signed      => div_i.is_signed,
      div_quotient       => div_o.quotient,
      t_bcc              => t_bcc,
      ibit               => ibit,
      if_dr              => if_dr,
      if_dr_next         => if_dr_next,
      if_stall           => if_stall,
      mask_int           => mask_int,
      illegal_delay_slot => illegal_delay_slot,
      illegal_instr      => illegal_instr,
      copreg             => copreg,
      cop_i              => cop_i,
      cop_o              => cop_o,
      priv_o             => priv_o,
      mmu_regs_o         => dp_mmu_regs,
      sr_o               => dp_sr,
      tlb_squash_o       => dp_tlb_squash,
      p4_viol_o          => dp_p4_viol,
      p4_viol_wr_o       => dp_p4_viol_wr,
      tlb_exc_pend       => tlb_exc_pend,
      inst_fault         => inst_fault,
      inst_fault_prot    => inst_fault_prot,
      if_fault_o         => dp_if_fault,
      if_fault_prot_o    => dp_if_fault_prot,
      id_delay_slot      => dec_id_dslot,
      if_fault_cap       => dec_texc_defer_cap,
      tlb_fault_va       => tlb_fault_va,
      tlb_exc_expevt     => tlb_exc_expevt,
      tlb_exc_fsr        => tlb_exc_fsr,
      delay_slot         => dslot,
      tlb_exc_is_i       => tlb_exc_is_i,
      tlb_exc_ifetch     => tlb_exc_ifetch,
      if_pc              => dp_if_pc,
      ex_if_pc           => dec_ex_if_pc,
      -- Walker counters' P4 alias (P4_TSBCNT at 0xFF000054).
      walk_cnt_walks_i => std_logic_vector(walk_cnt_walks),
      walk_cnt_hits_i  => std_logic_vector(walk_cnt_hits),
      -- TLB install counters' P4 alias (P4_TLBINST at 0xFF000058).
      tlb_cnt_iwr_i => std_logic_vector(cnt_itlb_wr),
      tlb_cnt_dwr_i => std_logic_vector(cnt_dtlb_wr)
    );

  -- Withhold ack from the core while the walker owns the bus. The core keeps
  -- sig_db_o.en asserted, so the faulting access is held stable and replays
  -- when ack is restored. Data is passed through unconditionally; only the
  -- handshake is gated.
  -- The walker counters are read through their P4 alias (P4_TSBCNT,
  -- 0xFF000054), served inside datapath.vhm from walk_cnt_walks_i /
  -- walk_cnt_hits_i above. The old P2 debug window at 0xABCD0F00 that decoded
  -- them here has been retired.
  dp_db_i.d   <= db_i.d;
  dp_db_i.ack <= db_i.ack and not walk_busy;

  -- Stall the I-FETCH for exactly as long as its own miss exception is
  -- suppressed. walk_supp_i is the single source of truth for "the I-side miss
  -- is being walked", so the fetch is held over precisely the window in which
  -- no IMISS can fire -- there is no cycle in which the fetch is free to
  -- complete untranslated and no cycle in which it is stalled with no walk to
  -- resolve it. A D-side walk does not stall the fetch (walk_supp_i is now
  -- per-side), which is what preserves older-instruction-first ordering.
  dp_inst_i.d   <= inst_i.d;
  dp_inst_i.ack <= inst_i.ack and not walk_supp_i;

  -- D-store TLB-fault write suppression (J4). A store that misses or
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
  --
  -- SECOND CONSUMER, easy to miss from here: this demotion is precondition (a)
  -- of the DOUBLE-ISSUE HAZARD note at p_walk_own below. A D-side walk drives
  -- its faulting access on the external bus AND replays it, so that access
  -- issues TWICE; demoting a faulting store to a read here is the only reason
  -- that is one write rather than two. Narrowing or removing it turns a
  -- doubled read into a doubled WRITE. Re-read that note first.
  d_store_faulting <= '1' when priv_arch and d_at_translated = '1'
                               and sig_db_o.en = '1' and sig_db_o.wr = '1'
                               and (tlb_d_hit = '0' or tlb_d_prot = '1') else
                      '0';

  g_tlb_walk : if PRIV_ARCH generate
  begin

    -- ---- Walk eligibility ----------------------------------------------
    -- Mirrors the MISS arms of the exception process below, and ONLY the miss
    -- arms: MULTI_HIT and protection faults are not misses and must reach their
    -- vectors untouched. Gated on rb='0' for the same reason the exception
    -- process is -- a fault while already in a handler keeps today's behaviour
    -- exactly.
    walk_d_miss <= '1' when d_at_translated = '1' and sig_db_o.en = '1'
                            and tlb_d_multihit = '0' and tlb_d_hit = '0' else
                   '0';

    -- OLDER-INSTRUCTION-FIRST. A D-side access is in MA and therefore belongs
    -- to an OLDER instruction than the I-fetch running ahead of it; the machine
    -- drains outstanding load/stores before processing an I-fetch fault, and
    -- decode_core's next_op gives a HELD D-side request (texc_req) priority
    -- over both I-side arms. Guards: mmuidorder, mmudrain, mmumhorder.
    --
    -- So an I-side walk may only start when no D access is live AND no D fault
    -- is awaiting dispatch. Without the first term the walker would service the
    -- younger I-fetch's miss while an older D access is still outstanding --
    -- and, because the takeover borrows the data bus, it would also let that
    -- unrelated D access commit externally and then be replayed when the core
    -- resumes (harmless on plain SRAM, NOT harmless on MMIO or TAS).
    walk_i_miss <= '1' when i_at_translated = '1' and sig_inst_o.en = '1'
                            and tlb_i_multihit = '0' and tlb_i_hit = '0'
                            and sig_db_o.en = '0' and d_fault_held = '0' else
                   '0';

    -- ---- Ordering invariant, permanently asserted --------------------
    -- The gate on walk_i_miss above is the ONLY thing enforcing
    -- older-instruction-first walk ordering, and its sole software-visible
    -- consequence is a replayed external bus transaction -- invisible on the
    -- plain SRAM the guard suite runs on. Deleting it therefore leaves the
    -- entire guard suite green (measured; see
    -- .superpowers/sdd/2026-08-09-tsb-walker-phase1/task-7-8-report.md). This
    -- assertion is the protection instead: it re-states the invariant from the
    -- RAW conditions, so removing the gate makes it fire in EVERY simulation.
    -- Simulation-only in BEHAVIOUR -- but see p_walk_takeover below before
    -- concluding it is free in AREA. The claim that used to sit on this line,
    -- "assertions have no synthesis effect", is measurably false for this
    -- flow's area metric: the $check cell is deleted only after mapping, so
    -- the assertion still steers what survives optimisation.
    walk_i_miss_raw <= '1' when i_at_translated = '1' and sig_inst_o.en = '1'
                                and tlb_i_multihit = '0' and tlb_i_hit = '0' else
                       '0';

    -- An I-SIDE walk is being armed this cycle iff the walker arms (walk_arm,
    -- combinational, the single arming pulse) while the raw I-side miss holds
    -- and walk_va does NOT select the D side. walk_va prefers D whenever
    -- walk_d_miss is true, so "not walk_d_miss" is exactly "the VA taken is the
    -- I-side VA". This is the arming cycle itself; walk_side_i registers the
    -- same decision one edge later, so it must not be used here.
    walk_i_arm_raw <= walk_arm and walk_i_miss_raw and not walk_d_miss;

    -- Sampled at the edge that ENDS the arming cycle, so the operands are the
    -- settled combinational values of that cycle (same sampling as
    -- p_walk_side), not mid-cycle transients.
    p_walk_order_assert : process (clk) is
    begin

      if rising_edge(clk) then
        assert not (rst = '0' and walk_i_arm_raw = '1'
                    and (sig_db_o.en = '1' or d_fault_held = '1'))
          -- The cosim's line reader truncates a report at roughly 110
          -- characters including its own prefix, so the crux must come FIRST;
          -- the full rationale is in the comment above, which the reported
          -- cpu.vhd line number points at.
          report "WALK ORDER VIOLATED: I-side TSB walk armed while an older "
                 & "D access is live or its fault is held. Restore the gate "
                 & "'and sig_db_o.en = ''0'' and d_fault_held = ''0''' on "
                 & "walk_i_miss; see p_walk_order_assert in core/cpu.vhd."
          severity failure;
      end if;

    end process p_walk_order_assert;

    walk_req <= '1' when priv_arch and dp_sr.rb = '0'
                         and (walk_d_miss = '1' or walk_i_miss = '1') else
                '0';

    -- D FIRST, for the ordering reason above. (With the gate on walk_i_miss the
    -- two are already mutually exclusive; the priority is stated anyway so the
    -- selection is correct on its own terms and does not depend on that.)
    walk_va <= d_va_32 when walk_d_miss = '1' else
               i_va_32;

    -- Stand-in for decode_core's held D-side request, texc_req. That signal is
    -- internal to decode_core and decode.vhd is GENERATED, so exporting it
    -- would mean changing the decoder generator -- out of scope for this phase.
    -- Reconstructed here, conservatively, with texc_req's own clear condition:
    -- the request is retired when the exception is dispatched, which this
    -- design marks by SR.RB going to 1 (the same "in the handler" indicator the
    -- exception process itself uses).
    --
    -- Only D-side MULTI_HIT and protection set it, because only they can still
    -- be awaiting dispatch once the access has left the bus. A D-side MISS
    -- needs no entry here: while it is live sig_db_o.en='1' already blocks the
    -- I-side walk, and the moment it stops being live it has either been
    -- installed by the walker -- in which case there is no fault to order
    -- against -- or raised its exception, which takes SR.RB to 1 and blocks
    -- walk_req outright. Including the miss term would also self-poison: the
    -- condition is true on the walk's own first cycle, before busy rises.
    --
    -- Worst case this holds longer than texc_req would, which only ever costs
    -- an I-side walk that then runs a boundary later, or not at all. It cannot
    -- suppress an exception -- it feeds walk_req, nothing else.
    p_d_fault_held : process (clk) is
    begin

      if rising_edge(clk) then
        if (rst = '1' or dp_sr.rb = '1') then
          d_fault_held <= '0';
        elsif (d_at_translated = '1' and sig_db_o.en = '1'
               and (tlb_d_multihit = '1' or tlb_d_prot = '1')) then
          d_fault_held <= '1';
        end if;
      end if;

    end process p_d_fault_held;

    u_tlb_walk : entity work.tlb_walk
      generic map (
        tsb_ways       => 2,
        entry_bytes    => 16,
        timeout_cycles => 255
      )
      port map (
        clk          => clk,
        rst          => rst,
        req          => walk_req,
        req_va       => walk_va,
        asidr        => dp_mmu_regs.asidr(15 downto 0),
        tsbbr        => dp_mmu_regs.tsbbr,
        tsbcfg       => dp_mmu_regs.tsbcfg,
        bus_a        => walk_bus_a,
        bus_en       => walk_bus_en,
        bus_d        => db_i.d,
        bus_ack      => walk_bus_ack,
        install      => walk_install,
        install_ptel => walk_ptel,
        va_r         => walk_va_r,
        busy         => walk_busy,
        arm          => walk_arm,
        cnt_walks    => walk_cnt_walks,
        cnt_hits     => walk_cnt_hits
      );

    -- Miss-exception suppression. A walk suppresses the miss arms for its
    -- whole duration, INCLUDING the arming cycle -- see tlb_walk.vhd's `arm`
    -- comment for why the arming cycle is not optional.
    -- PER SIDE, as tlb_walk.vhd's `arm` comment requires: only the side
    -- actually being walked has its miss arm suppressed. An I-side and a D-side
    -- miss can be live in the same cycle; D wins the walk (walk_va prefers it),
    -- and the I-side exception must still fire on schedule. walk_i_miss and
    -- walk_d_miss are mutually exclusive by construction (walk_i_miss requires
    -- sig_db_o.en = '0', walk_d_miss requires sig_db_o.en = '1'), so the arming
    -- cycle needs no extra priority term, and walk_side_i alone identifies the
    -- side for the rest of the walk.
    walk_supp_i <= (walk_arm and walk_i_miss) or (walk_busy and walk_side_i);
    walk_supp_d <= (walk_arm and walk_d_miss) or (walk_busy and not walk_side_i);

    -- Which side this walk belongs to, sampled on the arming cycle. `busy`
    -- rises the cycle after `arm`, so this register is always valid before its
    -- first use above.
    p_walk_side : process (clk) is
    begin

      if rising_edge(clk) then
        if (rst = '1') then
          walk_side_i <= '0';
        elsif (walk_arm = '1') then
          walk_side_i <= walk_i_miss and not walk_d_miss;
        end if;
      end if;

    end process p_walk_side;

    -- The walker may only consume an ack it caused. Until walk_own rises the bus
    -- still belongs to the core's in-flight access, and its ack (which the core
    -- itself is not allowed to see) would otherwise be latched by the walker as
    -- a TSB word -- it would compare the core's own load data against the tag.
    --
    -- walk_own is REGISTERED (p_walk_own below), so it is still '0' on the very
    -- first walk_busy cycle, and db_o in g_dstore_squash below therefore still
    -- carries whatever sig_db_o the core presents that cycle rather than the
    -- walker's bus_a/bus_en. On a D-SIDE walk that is the deliberate handshake
    -- p_walk_own describes: the faulting access IS on the bus (walk_d_miss
    -- requires sig_db_o.en='1') and the takeover waits for its external ack.
    -- Deliberate is NOT the same as harmless -- see the DOUBLE-ISSUE HAZARD
    -- note at p_walk_own below, which is a live constraint on the address map
    -- rather than a settled property.
    --
    -- ON AN I-SIDE WALK THAT CYCLE IS PROVABLY EMPTY. It used to be recorded
    -- here as an UNVERIFIED double-commit window -- "if an OLDER, already
    -- in-flight D-side store happened to be on the bus in that exact cycle it
    -- commits externally and is then replayed; harmless on plain SRAM, not
    -- necessarily harmless on MMIO or TAS". It cannot happen. Proof, in four
    -- steps, each a property of a named line elsewhere:
    --
    --  (1) A new D-bus access is launched ONLY from the "start new memory
    --      transactions" block in core/datapath.vhm, which is gated on
    --      `this.slot = '1'`. Nothing else drives this.data_o.en to '1'.
    --  (2) `this.slot` is set to '1' only inside the block gated on
    --      `this.data_o.en = '0' and slot_inst_en = '0' and ...`
    --      (core/datapath.vhm) -- so a slot needs the instruction bus either
    --      IDLE or ACKED this cycle, since slot_inst_en is this.inst_o.en and
    --      is cleared only on the `inst_i.ack = '1'` transfer.
    --  (3) An I-side walk requires sig_inst_o.en = '1' (walk_i_miss above) and
    --      holds walk_supp_i = '1' from the ARMING cycle onwards -- that is
    --      what the `walk_arm and walk_i_miss` term is for. With
    --      `dp_inst_i.ack <= inst_i.ack and not walk_supp_i` the datapath's
    --      inst ack is therefore '0' for the whole walk, the fetch is never
    --      transferred, and slot_inst_en stays '1'. It also cannot LAPSE and
    --      be re-raised: this.inst_o is NULLed only on that same
    --      `inst_i.ack = '1'` transfer, so an un-acked fetch stays presented
    --      with en = '1' rather than being withdrawn and reissued.
    --  (4) So this.slot = '0' from the arming cycle to the end of the walk and
    --      no new D access can start; and walk_i_miss already required
    --      sig_db_o.en = '0' ON the arming cycle. sig_db_o.en is therefore '0'
    --      for the ENTIRE I-side walk, not merely on its first busy cycle.
    --
    -- Two consequences. p_walk_own's `sig_db_o.en = '0'` arm fires at the end
    -- of the first busy cycle, so the un-owned window is exactly one cycle
    -- wide; and that cycle carries no core access, so there is nothing to
    -- double-commit -- not on MMIO, not on TAS.
    --
    -- MEASURED, not only argued. A temporary `severity warning` probe of
    -- exactly p_walk_takeover's condition was swept over sim/tests: 108
    -- images under cpu_tb plus the 14 cache-top guards re-run under
    -- cpu_cache_tb, 122 image-runs. ZERO hits. The probe is live in both
    -- directions, by two INDEPENDENT single-term relaxations of the same
    -- expression:
    --   * drop the walk_side_i term  -> 768 hits (the D-side handshake:
    --     712 under cpu_tb + 56 under cpu_cache_tb)
    --   * count I-side ARMING cycles -> 953 hits (936 + 17)
    -- Counting convention, because it is easy to quote a different number for
    -- the same hardware: an "arm" is one rising-edge sample of
    -- walk_i_arm_raw = '1', i.e. ONE pulse per I-side walk, not per busy
    -- cycle; the 768 is likewise a count of CYCLES in which the un-owned
    -- window was occupied, not of walks. So the zero is the property, not a
    -- dead probe. (The four linux@jcore harnesses are absent from the sweep:
    -- they need $(LINUX_SRC) kbuild objects a normal checkout does not have.)
    --
    -- p_walk_takeover below is the standing lock on steps (1)-(4). It has to
    -- be an RTL assertion: a double-committed bus transaction leaves NO
    -- software-visible trace on the plain SRAM the guard suite runs on, so no
    -- .S file can detect it. Driver: sim/tests/mmuwalkitakeover.S.
    walk_bus_ack <= db_i.ack and walk_own;

    -- Bus ownership handshake for the takeover. On the cycle the walk starts,
    -- the core's own (faulting) access is still presented to the memory model
    -- with en='1' and may already be mid-operation; switching the address under
    -- it, or dropping en, is a protocol violation the SRAM model reports and
    -- which can wedge the transaction, after which the core waits forever for an
    -- ack ("Rd did not see ACK for data sram"). So the takeover waits: the core's
    -- access is left alone until it has been acked on the EXTERNAL bus (that ack
    -- is still withheld from the datapath, so the access stays in flight for the
    -- core and replays later), and only then does the walker drive. The walker
    -- advances only on bus_ack, so it simply waits meanwhile.
    --
    -- DOUBLE-ISSUE HAZARD -- READ THIS BEFORE CHANGING THE ADDRESS MAP.
    -- On a D-side walk this handshake ISSUES THE FAULTING ACCESS TWICE on the
    -- external bus: once here (driven, and acked externally, which is what
    -- releases the takeover) and once again on the replay, because
    -- `dp_db_i.ack <= db_i.ack and not walk_busy` withholds that ack from the
    -- datapath and keeps the access in flight. The transaction is NOT undone.
    -- It is benign today for exactly two reasons, BOTH load-bearing and
    -- neither of them a property of this process: (a) a faulting STORE is
    -- demoted to a read by d_store_faulting above, so only one real write ever
    -- reaches memory; and (b) d_at_translated is mmucr(0) only for SEG_P0 and
    -- SEG_P3 and hard '0' everywhere else, so an access in P1/P2/P4 can never
    -- be a walk's faulting access -- which is where all MMIO lives in this
    -- design. Map a device into P0 or P3 and run it under AT=1 and it WILL see
    -- the read twice; the same goes for anything read-sensitive reached
    -- through a translated page. This is a real defect waiting on an address-
    -- map decision, not a settled property, and nothing in the guard suite
    -- would notice: on plain SRAM a repeated read is invisible. Unlike the
    -- I-side window below it is NOT fixed and NOT asserted -- fixing it means
    -- deferring the external issue until ownership is resolved, which the
    -- bus-protocol paragraph above explains is not free.
    p_walk_own : process (clk) is
    begin

      if rising_edge(clk) then
        if (rst = '1' or walk_busy = '0') then
          walk_own <= '0';
        elsif (db_i.ack = '1' or sig_db_o.en = '0') then
          walk_own <= '1';
        end if;
      end if;

    end process p_walk_own;

    -- I-SIDE TAKEOVER WINDOW LOCK. Pins steps (1)-(4) of the proof above: on
    -- an I-side walk the core's data bus is idle, so the un-owned first busy
    -- cycle cannot double-commit anything. Any future change that lets the
    -- I-fetch be acked during a walk, drops the arming cycle from walk_supp_i,
    -- relaxes walk_i_miss's `sig_db_o.en = '0'` term, or lets datapath.vhm
    -- issue a D access without a slot, reopens the window and fires this.
    --
    -- NOT "free at synthesis", though it is usually written that way -- this
    -- comment said exactly that, and so did the one at p_walk_order_assert
    -- above, until both were measured. synth/cpu_synth.sh does run
    -- `chformal -remove; delete t:$check t:$print`, but AFTER `synth_ecp5` /
    -- `synth`, i.e. after mapping. The assertion CELL is gone from the written
    -- netlist; the influence it had on how everything ELSE was mapped is not.
    -- Its operands stay live through the whole optimisation pass, so nothing
    -- feeding them can be pruned and abc9 is handed a different cone. Measured
    -- on this design, with no functional change whatever: adding this process
    -- moves mapped ECP5 LUT4 by several hundred, and adds one `reg` to the
    -- generic ASIC netlist (2696 -> 2697). Figures and method are in the area
    -- note in core/tlb.vhd.
    --
    -- The consequence is a measurement rule, not a reason to drop the
    -- assertion: NEVER build an area A/B across two trees that differ in
    -- assertion count -- it silently charges the assertion's mapping effect to
    -- whatever else changed.
    --
    -- CLOCKED, not concurrent, for the same reason p_r1_assert is: walk_own is
    -- registered while its neighbours here are combinational, so a concurrent
    -- assert samples deltas instead of settled end-of-cycle values.
    p_walk_takeover : process (clk) is
    begin

      if rising_edge(clk) then
        assert not (rst = '0' and walk_busy = '1' and walk_own = '0'
                    and walk_side_i = '1' and sig_db_o.en = '1')
          -- The cosim's line reader truncates a report at roughly 110
          -- characters including its own prefix, so the crux comes FIRST.
          report "I-SIDE WALK TAKEOVER WINDOW OCCUPIED: a core D access is on "
                 & "db_o before the walker owns it, so it commits externally "
                 & "and is replayed. See p_walk_takeover in core/cpu.vhd."
          severity failure;
      end if;

    end process p_walk_takeover;

  end generate g_tlb_walk;

  g_no_tlb_walk : if not PRIV_ARCH generate
    walk_busy       <= '0';
    walk_arm        <= '0';
    walk_supp_i     <= '0';
    walk_supp_d     <= '0';
    walk_side_i     <= '0';
    walk_own        <= '0';
    walk_bus_ack    <= '0';
    walk_req        <= '0';
    walk_d_miss     <= '0';
    walk_i_miss     <= '0';
    walk_va         <= (others => '0');
    walk_va_r       <= (others => '0');
    d_fault_held    <= '0';
    walk_install    <= '0';
    walk_bus_en     <= '0';
    walk_bus_a      <= (others => '0');
    walk_ptel       <= (others => '0');
    walk_i_miss_raw <= '0';
    walk_i_arm_raw  <= '0';
  end generate g_no_tlb_walk;

  g_dstore_squash : if PRIV_ARCH generate

    process (sig_db_o, d_store_faulting, d_at_translated, tlb_d_hit,
             tlb_d_pa, tlb_d_pa12, tlb_d_page_mask,
             walk_own, walk_bus_a, walk_bus_en) is

      variable offm   : std_logic_vector(15 downto 0);
      variable ppn_lo : std_logic_vector(15 downto 0);

    begin

      db_o <= sig_db_o;

      if (d_store_faulting = '1') then
        db_o.rd <= '1';
        db_o.wr <= '0';
        db_o.we <= "0000";
      end if;

      -- SH P1 untranslated fold on the external data bus (P1 only; P2 holds
      -- the sim result MMIO at 0xBCDE0010 and must pass through unmasked).
      if (sig_db_o.a(31 downto 29) = "100") then
        db_o.a(31 downto 29) <= "000";
      elsif (d_at_translated = '1' and tlb_d_hit = '1') then
        -- Variable-page relocation (docs/architecture/tlb.md). Per PA bit 12+p:
        -- VA (in-page offset) if p < 2*pm, else PPN (frame). PA[11:0]=VA, [31:28]=0.
        offm                 := page_offset_mask(tlb_d_page_mask);
        ppn_lo               := tlb_d_pa & tlb_d_pa12;   -- PPN[27:12]: bit15=PPN[27] .. bit0=PPN[12]
        db_o.a(31 downto 28) <= "0000";
        db_o.a(27 downto 12) <= (ppn_lo and not offm) or (sig_db_o.a(27 downto 12) and offm);
      end if;

      -- Walker bus takeover. MUST be last and MUST be on the external db_o:
      -- the TLB has already consumed sig_db_o by this point. Gating the
      -- internal sig_db_o here would form the combinational loop described in
      -- the d_store_faulting comment above.
      if (walk_own = '1') then
        db_o.a <= walk_bus_a;
        -- Same SH P1 untranslated fold the core's own accesses get above: the
        -- takeover replaces db_o.a wholesale and so bypasses that block. Every
        -- TSBBR the guards and linux@jcore program is a P1 kernel address
        -- (e.g. 0x80002C04), which the software miss handler reads through the
        -- fold; without folding here the walker reads an unmapped 0x8xxxxxxx
        -- and the SRAM model rejects it.
        if (walk_bus_a(31 downto 29) = "100") then
          db_o.a(31 downto 29) <= "000";
        end if;
        db_o.en <= walk_bus_en;
        db_o.rd <= walk_bus_en;
        db_o.wr <= '0';
        db_o.we <= "0000";
      end if;

    end process;

  end generate g_dstore_squash;

  g_no_dstore_squash : if not PRIV_ARCH generate
    db_o <= sig_db_o;
  end generate g_no_dstore_squash;

  g_inst_p1_fold : if PRIV_ARCH generate
    -- SH P1 (0x8000_0000-0x9FFF_FFFF) is untranslated: PA = VA and 0x1FFFFFFF.
    -- inst_o.a is PA[31:1] (indices preserved 31..1, not reindexed), so P1 is
    -- a(31 downto 29)="100". Fold AFTER i_va_32 has sampled sig_inst_o.a, so
    -- seg_decode still sees the true P1 VA.
    process (sig_inst_o, i_at_translated, tlb_i_hit, tlb_i_pa, tlb_i_pa12, tlb_i_page_mask) is

      variable offm   : std_logic_vector(15 downto 0);
      variable ppn_lo : std_logic_vector(15 downto 0);

    begin

      inst_o <= sig_inst_o;

      if (sig_inst_o.a(31 downto 29) = "100") then
        inst_o.a(31 downto 29) <= "000";
      elsif (i_at_translated = '1' and tlb_i_hit = '1') then
        offm                   := page_offset_mask(tlb_i_page_mask);
        ppn_lo                 := tlb_i_pa & tlb_i_pa12;
        inst_o.a(31 downto 28) <= "0000";
        inst_o.a(27 downto 12) <= (ppn_lo and not offm) or (sig_inst_o.a(27 downto 12) and offm);
      end if;

    end process;

  end generate g_inst_p1_fold;

  g_inst_no_fold : if not PRIV_ARCH generate
    inst_o <= sig_inst_o;
  end generate g_inst_no_fold;

  coproc.cpu_data_mux <= coproc_decode.cpu_data_mux when copro_decode else
                         DBUS;
  coproc.coproc_cmd   <= coproc_decode.coproc_cmd when copro_decode else
                         NOP;

  -- TLB instantiation (J4 only).
  -- The TLB is combinational for lookups; it is clocked only for TI flush and
  -- installs, and every install now comes from the hardware walker
  -- (walk_install); ti is MMUCR bit[2].

  g_mmu : if PRIV_ARCH generate
  begin
    -- Reconstruct 32-bit VAs from the registered bus outputs.
    -- inst_o.a is PA[31:1]; bit 0 is always 0 for instruction fetch.
    -- db_o.a is the full 32-bit data VA.
    i_va_32 <= sig_inst_o.a & '0';
    d_va_32 <= sig_db_o.a;

    -- AT-translated: address translation is active for P0 and P3 segments.
    -- P1/P2 are fixed-translate (no TLB); P4 is kernel-only MMIO.
    --
    -- THIS SEGMENT LIST IS A SAFETY PRECONDITION, not just a decode. It is
    -- precondition (b) of the DOUBLE-ISSUE HAZARD note at p_walk_own: only an
    -- AT-translated access can be a walk's faulting access, and a walk's
    -- faulting access is issued TWICE on the external bus. Because MMIO in
    -- this design lives in P1/P2/P4 -- all hard '0' here -- no device can be
    -- the access that gets doubled. Widening d_at_translated to a segment
    -- that carries devices, or mapping a device into P0/P3 and running it
    -- under AT=1, makes that hazard live. Read the note before changing this
    -- list; nothing else in the file will remind you.
    i_at_translated <= dp_mmu_regs.mmucr(0) when
                                                 (seg_decode(i_va_32) = SEG_P0 or seg_decode(i_va_32) = SEG_P3) else
                       '0';
    d_at_translated <= dp_mmu_regs.mmucr(0) when
                                                 (seg_decode(d_va_32) = SEG_P0 or seg_decode(d_va_32) = SEG_P3) else
                       '0';

    -- TLB install port. Both arrays are written only when walk_install is set,
    -- so these carry the walker's data unconditionally -- the PTEH/PTEL CSR
    -- alternative that used to sit on the other leg of each mux went away with
    -- the software install instruction. PTEH and PTEL remain fully readable and
    -- writable by software; they simply no longer feed the install port.
    --
    -- On a walker install PTEH has NOT been written (no exception was taken),
    -- so the TLB's VPN input comes from the faulting VA -- and specifically
    -- from the walker's LATCHED copy of it (walk_va_r), not from walk_va.
    -- walk_va is a combinational selection that can change under a walk in
    -- progress, which would install the fetched PTEL under the wrong VPN. The
    -- walker compares its tag against the same latched value.
    tlb_ptel_mx <= walk_ptel;
    tlb_vpn_mx  <= walk_va_r(31 downto 12);

    -- Split ITLB/DTLB (S1). Two independent single-port arrays replace the one
    -- dual-ported 32-entry block, so each can be placed beside the cache it
    -- serves instead of straddling both. Behaviour per array is identical to
    -- the old shared block; the only cross-array rules are the install routing
    -- below and the fact that multi-hit is PER ARRAY (the same page resident in
    -- both is not a multi-hit).
    --
    -- INSTALL ROUTING. The hardware walker is the SOLE installer: there is no
    -- software install instruction any more. A walk installs into the faulting
    -- side only -- walk_side_i names it, and installing into the other array
    -- would be pure pollution.
    --
    -- This is demand-driven routing by construction, which is why retiring the
    -- software path was worth doing: an I-side miss can only ever want an ITLB
    -- entry and a D-side miss a DTLB entry, so no X-bit heuristic, fault-side
    -- state or ABI side-selector bit is needed. The old software install had to
    -- write BOTH arrays because the ISA gave it no side selector, which meant
    -- every pure-data page it installed also consumed an ITLB entry it could
    -- never legally use.
    -- SHADOW FILL, one way only: I -> D. An ITLB install is a strong predictor
    -- of an imminent D-side access to the SAME page, because SH code pages
    -- carry PC-relative literal pools -- `MOV.L @(disp,PC),Rn` reads the page
    -- it was just fetched from, a few cycles behind the fetch. Under pure
    -- side-only routing that read is a second full TSB walk of the entry the
    -- walker has just fetched and still holds. The shadow fill installs it
    -- into the DTLB as well, one cycle later. (guard mmuishadow)
    --
    -- NOT symmetric, and the asymmetry is the point. A D-side install must
    -- never touch the ITLB: a data page can never be legally fetched, so the
    -- prediction is always wrong, and the ITLB has 8 entries against the
    -- DTLB's 16 -- no room to be wrong in. The DTLB is already sized 2x partly
    -- because it carries this literal-pool traffic (see u_dtlb's generic).
    --
    -- DELAYED ONE CYCLE, which costs nothing: the load is several cycles
    -- behind the fetch by the nature of the ISA. It buys two things -- the two
    -- arrays are never written in the same cycle, so the shared install
    -- fan-out is unchanged, and no arbitration is needed against a real
    -- dtlb_wr, which cannot occur here (a new walk needs >= 4 cycles to reach
    -- st_install, so the OR below can never see both terms at once).
    --
    -- The data is LATCHED rather than re-read from walk_va_r/walk_ptel in the
    -- shadow cycle. Those do happen to still hold in that cycle today -- ptel_r
    -- is written only in st_data and va_reg only on arming, whose earliest
    -- effect is one edge later -- but that is a property of tlb_walk's re-arm
    -- timing, not a contract it offers. A future change to st_install would
    -- silently shadow-install the right PTE under the wrong VPN, which is a
    -- wrong-translation bug, not a performance one.
    p_tlb_install_cnt : process (clk) is
    begin

      if rising_edge(clk) then
        if (rst = '1') then
          cnt_itlb_wr <= (others => '0');
          cnt_dtlb_wr <= (others => '0');
        else
          if (itlb_wrote = '1') then
            cnt_itlb_wr <= cnt_itlb_wr + 1;
          end if;
          if (dtlb_wrote = '1') then
            cnt_dtlb_wr <= cnt_dtlb_wr + 1;
          end if;
        end if;
      end if;

    end process p_tlb_install_cnt;

    p_tlb_shadow : process (clk) is
    begin

      if rising_edge(clk) then
        if (rst = '1') then
          shadow_wr <= '0';
        else
          shadow_wr   <= walk_install and walk_side_i;
          shadow_vpn  <= tlb_vpn_mx;
          shadow_ptel <= tlb_ptel_mx;
          -- ASIDR is latched for the same reason as the VPN: the shadow
          -- install must stamp the context the WALK ran in. The two arrays
          -- would otherwise disagree about which ASID owns the page if ASIDR
          -- changed in between -- an aliasing bug, and a silent one.
          shadow_asid <= dp_mmu_regs.asidr(15 downto 0);
        end if;
      end if;

    end process p_tlb_shadow;

    itlb_wr <= walk_install and walk_side_i;
    dtlb_wr <= (walk_install and not walk_side_i) or shadow_wr;
    -- Speculative: installed as the next NRU victim, and skipped outright if
    -- the page is already resident in the DTLB. See tlb.vhd's `spec` port --
    -- the "already resident" case is a load-then-execute page, where the DTLB
    -- entry the shadow fill would write is one a demand fill already placed.
    dtlb_spec <= shadow_wr;

    dtlb_vpn  <= shadow_vpn when shadow_wr = '1' else
                 tlb_vpn_mx;
    dtlb_ptel <= shadow_ptel when shadow_wr = '1' else
                 tlb_ptel_mx;
    dtlb_asid <= shadow_asid when shadow_wr = '1' else
                 dp_mmu_regs.asidr(15 downto 0);

    u_itlb : entity work.tlb
      generic map (
        -- TLB CAPACITY (8 ITLB / 16 DTLB), measured 2026-08-13, 6-seed
        -- nextpnr sweeps vs the 32+32 control (mean 29.55, range 28.94-30.37):
        --
        --   8+16  mean 34.69  min 33.65  sd 0.95  -> +5.14  RESOLVED, SHIPPED
        --   8+8   mean 34.31  min 32.67  sd 1.22  -> +4.76  RESOLVED but RED
        --   16+16 mean 33.01  min 31.41  sd 1.19  -> +3.46  RESOLVED
        --   8+32  mean 31.36  min 29.84  sd 1.05  -> +1.81  marginal
        --
        -- Fmax scales with TOTAL comparator count, consistent with the
        -- broadcast-fanout theory the split was built on. 8+16 wins on both
        -- axes: the highest mean AND the whole suite green.
        --
        -- 8+8 is NOT shipped despite being within noise of 8+16 on clock: it
        -- turns mmudrain red (leg A fault count, Result=0x10) because that
        -- guard's D-side live set exceeds 8 pages. See sim/tests/mmudrain.S.
        --
        -- Only shrinking is possible at all because the walker is the sole
        -- installer and routes by side (itlb_wr/dtlb_wr above). Under the old
        -- software LDTLB, which wrote BOTH arrays, every shrunk size failed.
        --
        -- `entries` MUST stay a power of two (log2 leaf/root reduction).
        entries   => 8,
        side_is_i => true
      )
      port map (
        clk => clk,
        rst => rst,
        va  => i_va_32,
        -- An instruction fetch is never a store, so the W-permission check the
        -- D side makes on `we` has no I-side counterpart (the I side checks X /
        -- SMEP instead; see tlb.vhd's lookup process).
        we        => '0',
        pa_tag    => tlb_i_pa,
        pa12      => tlb_i_pa12,
        page_mask => tlb_i_page_mask,
        c         => tlb_i_c,
        hit       => tlb_i_hit,
        prot      => tlb_i_prot,
        multihit  => tlb_i_multihit,
        asid      => dp_mmu_regs.asidr(15 downto 0),
        md        => dp_sr.md,
        at        => dp_mmu_regs.mmucr(0),
        tlb_wr    => itlb_wr,
        pteh_vpn  => tlb_vpn_mx,
        -- Install data, not the CSR: the walker's fetched PTE.
        ptel  => tlb_ptel_mx,
        asidr => dp_mmu_regs.asidr(15 downto 0),
        -- Every ITLB install is a demand fill: nothing shadows INTO the I side.
        spec  => '0',
        ti    => dp_mmu_regs.mmucr(2),
        wrote => itlb_wrote
      );

    u_dtlb : entity work.tlb
      generic map (
        -- Twice the ITLB. Asymmetric on purpose: the D side is the one with a
        -- guard (mmudrain) that needs more than 8 entries, and every SH code
        -- page carrying a PC-relative literal pool is read through the DTLB as
        -- well as fetched through the ITLB. See the ITLB block above.
        entries   => 16,
        side_is_i => false
      )
      port map (
        clk       => clk,
        rst       => rst,
        va        => d_va_32,
        we        => sig_db_o.wr,
        pa_tag    => tlb_d_pa,
        pa12      => tlb_d_pa12,
        page_mask => tlb_d_page_mask,
        c         => tlb_d_c,
        hit       => tlb_d_hit,
        prot      => tlb_d_prot,
        multihit  => tlb_d_multihit,
        asid      => dp_mmu_regs.asidr(15 downto 0),
        md        => dp_sr.md,
        at        => dp_mmu_regs.mmucr(0),
        tlb_wr    => dtlb_wr,
        -- Muxed, not tlb_vpn_mx directly: a shadow fill replays the LATCHED
        -- install of the previous cycle. See p_tlb_shadow.
        pteh_vpn => dtlb_vpn,
        ptel     => dtlb_ptel,
        asidr    => dtlb_asid,
        spec     => dtlb_spec,
        ti       => dp_mmu_regs.mmucr(2),
        wrote    => dtlb_wrote
      );

    mmu_o.i_pa_tag <= tlb_i_pa;
    mmu_o.i_at     <= i_at_translated;
    mmu_o.i_c      <= tlb_i_c;
    -- Export the I-side hit so the cache side can refuse to SERVICE a fetch
    -- whose translation is not yet known (ITLB miss being walked). The core
    -- keeps inst_o.en asserted across that window (dp_inst_i.ack is withheld,
    -- not the request). Such a fetch never reaches the icache -- with at='1'
    -- and c undefined it routes uncacheable -- it reaches the UNCACHED BYPASS,
    -- which would read the raw untranslated VA off the bus and ack the fetch
    -- mid-walk. See cache/icache_cacheable_mux.vhd.
    mmu_o.i_hit    <= tlb_i_hit;
    mmu_o.d_pa_tag <= tlb_d_pa;

    -- TSB COHERENCY POLICY: walker TSB reads are CACHEABLE, decided by region
    -- decode on the walker's own (physical) address -- never by a TLB lookup.
    --
    -- g_dstore_squash replaces db_o.a wholesale with the walker's TSB PHYSICAL
    -- address during walk_own, but tlb_d_* here is the lookup of d_va_32 =
    -- sig_db_o.a, which is the core's unrelated (and for an I-side walk, IDLE,
    -- i.e. VA 0) address. dcache_cacheable_mux computes
    -- is_cacheable_mmu(db_o.a, d_at, d_c), so leaving d_at/d_c on that lookup
    -- made the walker's cacheable-vs-bypass routing a function of whether some
    -- unrelated page happened to be mapped -- measured flipping between the two
    -- across guards. Whichever way it landed was luck, and the bypass case is
    -- not coherent with dirty dcache lines holding TSB writes.
    --
    -- The fix states the truth about the access: the walker drives a PHYSICAL
    -- address, so it is by definition untranslated (at='0'), and cacheability
    -- falls to region decode on the address actually on the bus. Linux writes
    -- TSB entries with plain cacheable stores through the P1 alias
    -- (arch/sh/mm/tlb-jcore.c jcore_tsb_write_entry(); TSBBR holds a P1 kernel
    -- VA -- arch/sh/kernel/head_32.S), and P1 folds to P0 here, so region decode
    -- returns CACHEABLE: the walker reads through the very cache those stores
    -- go through. No flush and no uncached mapping is required of the OS, so
    -- this costs linux@jcore nothing. A TSBBR deliberately placed in P2 still
    -- decodes uncached, which is also correct.
    --
    -- WHY CACHEABLE RATHER THAN ALWAYS-BYPASS. Both are coherent TODAY, and it
    -- is worth being exact about why, because the obvious argument for
    -- CACHEABLE is wrong: this D-cache is WRITE-THROUGH, not write-back. Every
    -- store is pushed out as CACHE_DCMD_WRITESGL_SL (cache/dcache_ccl.vhm) and
    -- there is no dirty bit or writeback path anywhere under cache/ -- so a TSB
    -- row can never sit dirty in cache over stale memory, and a bypassing
    -- walker would in fact still see software's stores. (dcache_cacheable_mux
    -- .vhd's header comment claiming "write-back" and "dirty-line writeback" is
    -- simply wrong; it is corrected there.) CACHEABLE is chosen anyway because:
    --   * it is a statement of what the access IS, not a special case bolted
    --     onto the mux, so there is nothing to keep in sync;
    --   * TSB rows are hot and re-probed, so routing them through the cache is
    --     a latency win rather than a cost;
    --   * it is the arm that stays correct if the D-cache ever becomes
    --     write-back. Under always-bypass that change would silently
    --     reintroduce exactly the stale-PTE corruption this class of bug
    --     threatens, with no fault and no diagnostic.
    -- The one thing that is NOT acceptable either way is the previous
    -- behaviour: a routing decision that varies with an unrelated page's
    -- mapping. That is what the assert below pins.
    mmu_d_at_i <= '0' when walk_own = '1' else
                  d_at_translated;
    mmu_d_c_i  <= '0' when walk_own = '1' else
                  tlb_d_c;

    mmu_o.d_at <= mmu_d_at_i;
    mmu_o.d_c  <= mmu_d_c_i;

    -- R1 REGRESSION LOCK. The routing this enforces is NOT observable from
    -- software -- the D-cache is write-through, so a bypassing walker and a
    -- cache-routed walker return the same data and no guard can tell them
    -- apart (see sim/tests/mmutsbcoh.S). An unobservable invariant needs an
    -- RTL assert, or the regression is silent. This one fires the moment
    -- anything routes the walker's cacheability back through the TLB lookup.
    -- CLOCKED, not concurrent. As a concurrent assert this fires spuriously:
    -- walk_own is registered and mmu_d_at_i is combinational from it, so on the
    -- cycle walk_own rises there is a delta in which walk_own is already '1'
    -- while mmu_d_at_i still carries its pre-edge value. Sampling on the clock
    -- edge sees only settled values. (Measured -- the concurrent form failed 81
    -- of 103 guards.)
    p_r1_assert : process (clk) is
    begin

      if rising_edge(clk) then
        if (rst = '0') then
          assert not (walk_own = '1' and mmu_d_at_i = '1')
            report "R1: walker TSB access presented to the D-cache as "
                   & "AT-translated. Its cacheability is then decided by the TLB "
                   & "lookup of an UNRELATED address (core/cpu.vhd d_va_32), "
                   & "making cacheable-vs-bypass routing depend on whether some "
                   & "other page happens to be mapped."
            severity failure;
        end if;
      end if;

    end process p_r1_assert;

    -- TLB exception detection: priority I-side > D-side; miss > prot.
    -- tlb_exc_en is combinatorial (no register); it is sampled by decode_core
    -- on each slot and triggers the appropriate system microcode entry.
    -- tlb_exc_pend and tlb_fault_va go to datapath to write TEA/PTEH.
    process (i_at_translated, d_at_translated,
             sig_inst_o, sig_db_o,
             tlb_i_hit, tlb_i_prot, tlb_i_multihit,
             tlb_d_hit, tlb_d_prot, tlb_d_multihit,
             i_va_32, d_va_32, dp_sr, walk_supp_i, walk_supp_d,
             dp_p4_viol, dp_p4_viol_wr, dp_mmu_regs) is

      variable exc_en   : std_logic;
      variable exc_kind : tlb_exc_kind_t;
      variable fva      : std_logic_vector(31 downto 0);
      -- Set inside the i_at_translated branch below, for ANY exc_kind it
      -- raises (IMISS, IPROT, MULTI_HIT). See tlb_exc_ifetch's declaration
      -- comment for why this must be broader than the exc_kind-narrowed
      -- tlb_exc_is_i.
      variable v_ifetch : std_logic;

    begin

      exc_en   := '0';
      exc_kind := IMISS;
      fva      := (others => '0');
      v_ifetch := '0';
      -- Block further exceptions while one is being handled. Without this, a
      -- second faulting access (the instruction right after a faulting one, whose
      -- access already launched -- back-to-back D-faults) dispatches a SECOND
      -- exception entry that re-saves SSR<-SR while already in exception mode
      -- (RB=1). The handler's RTE then restores RB=1, so the resumed user
      -- code reads bank-1 (uninitialised) registers and corrupts addresses.
      -- SR.RB is this design's handler indicator: user code runs RB=0, exception
      -- entry sets RB=1, and RTE restores it -- so RB=1 means "in the
      -- handler". (SR.BL, the architectural block bit, is left set from reset by
      -- the bare-metal guards, so it cannot serve as the gate here.) The lingering
      -- second access then raises no exception while RB=1; it re-faults cleanly
      -- after the handler returns (RB back to 0). (J4.)
      -- walk_busy suppresses the MISS exception while the hardware walker is
      -- probing the TSB -- and ONLY the miss arm. MULTI_HIT and protection are
      -- not misses, the walker is never armed for them, and they must reach
      -- their vectors untouched (mmuvecsplit, mmumultihit): the suppression
      -- therefore sits on the miss arm itself, not on the outer condition.
      -- There is deliberately no "walk failed" wire: on a hit the install
      -- removes the miss condition, and on a give-up the walker stops with the
      -- condition still true, so this process raises the exception on the next
      -- cycle exactly as it did before.
      if (i_at_translated = '1' and sig_inst_o.en = '1' and dp_sr.rb = '0') then
        if (tlb_i_multihit = '1') then                                                          -- S-I5: hit-count fault, priority over hit_found/prot
          exc_en   := '1';
          exc_kind := MULTI_HIT;
          fva      := i_va_32;
        elsif (tlb_i_hit = '0') then
          if (walk_supp_i = '0') then
            exc_en   := '1';
            exc_kind := IMISS;
            fva      := i_va_32;
          end if;
        elsif (tlb_i_prot = '1') then
          exc_en   := '1';
          exc_kind := IPROT;
          fva      := i_va_32;
        end if;
      end if;

      -- Captured immediately: any exc_en set by the branch above came from
      -- fva = i_va_32 (an instruction-fetch VA), for every exc_kind it can
      -- raise. Must be read before the D-side branch below can overwrite
      -- exc_en.
      v_ifetch := exc_en;

      if (exc_en = '0' and d_at_translated = '1' and sig_db_o.en = '1'
          and dp_sr.rb = '0') then
        if (tlb_d_multihit = '1') then                                                          -- S-I5: hit-count fault, priority over hit_found/prot
          exc_en   := '1';
          exc_kind := MULTI_HIT;
          fva      := d_va_32;
        elsif (tlb_d_hit = '0') then
          -- Miss arm only -- see the I-side comment above.
          if (walk_supp_d = '0') then
            if (sig_db_o.wr = '1') then
              exc_en   := '1';
              exc_kind := DMISS_W;
            else
              exc_en   := '1';
              exc_kind := DMISS_R;
            end if;
            fva := d_va_32;
          end if;
        elsif (tlb_d_prot = '1') then
          if (sig_db_o.wr = '1') then
            exc_en   := '1';
            exc_kind := DPROT_W;
          else
            exc_en   := '1';
            exc_kind := DPROT_R;
          end if;
          fva := d_va_32;
        end if;
      end if;

      -- P4 PRIVILEGE VIOLATION (SH-4 CPU address error). A user-mode data
      -- access to the supervisor-only P4 segment, already detected and REFUSED
      -- one cycle ago by the datapath; all that is left here is to raise the
      -- exception for it.
      --
      -- It is a D-side fault and sits with the D-side arm's priority: gated on
      -- exc_en = '0' so a live I-fetch or TLB fault still wins (an I-fetch
      -- fault belongs to a younger instruction, but the existing arms above
      -- already resolve that ordering and this must not perturb it), and on
      -- dp_sr.rb = '0' for the same reason every other arm is -- see the
      -- nested-entry comment at the top of this process. Suppressing at RB='1'
      -- costs nothing in safety: the ACCESS is refused unconditionally in the
      -- datapath, with no dependence on this exception being delivered.
      --
      -- The VA comes from dp_mmu_regs.tea, which the datapath wrote at the
      -- refusal (it is the only point holding the address). dp_mmu_regs is
      -- driven from the REGISTERED CSRs, so this is a flop output and closes no
      -- loop; and the tlb_exc_pend capture triggered by exc_en below writes the
      -- same value straight back into TEA.
      --
      -- KNOWN, BOUNDED LIMITATION -- the request is a ONE-SHOT. dp_p4_viol
      -- pulses for a single cycle, where a D-side TLB fault re-asserts every
      -- cycle its access is held on the bus. So if this cycle is lost -- an
      -- I-fetch fault takes it through exc_en above (reachable only with
      -- MMUCR.AT = 1), or decode_core's texc_req is still holding an older
      -- undispatched request -- the exception can be DROPPED rather than
      -- re-raised, and the refused instruction is not necessarily re-executed
      -- to raise it again.
      --
      -- That costs nothing in SAFETY, which is the point: the datapath refuses
      -- the access unconditionally, with no dependence whatever on this
      -- exception being delivered. No CSR is written, no read side effect runs,
      -- and a refused load yields a hard zero. The worst outcome is a silently
      -- swallowed address error -- a missing signal, never a leak or an escape.
      -- It is not quite free, though: the refusal writes TEA unconditionally,
      -- so a swallowed violation leaves the P4 VA in TEA over an older
      -- undispatched fault's address, and that fault's handler then reads the
      -- wrong faulting address. Confined to diagnosis -- no privileged state is
      -- exposed and no access is granted -- but not merely a missing signal.
      --
      -- Turning it into a held request needs an ack path back from decode_core
      -- AND a frozen copy of the restart context: tlb_exc_pc is derived from the
      -- LIVE ex_if_pc inside the shared capture block, so a delayed raise would
      -- silently produce the wrong SPC. Worth doing, deliberately not done here,
      -- and not on the security path.
      if (exc_en = '0' and dp_p4_viol = '1' and dp_sr.rb = '0') then
        exc_en := '1';
        if (dp_p4_viol_wr = '1') then
          exc_kind := P4_USER_W;
        else
          exc_kind := P4_USER_R;
        end if;
        fva := dp_mmu_regs.tea;
      end if;

      -- Same I-side condition the branch above uses, exported for the datapath
      -- to RECORD with the fetched instruction (deferred delivery, step 1).
      -- IMISS/IPROT only -- NOT every I-fetch fault. An I-side MULTI_HIT also
      -- sets v_ifetch, but it is deliberately NOT deferred: it dispatches through
      -- General Illegal (see decode_core.vhm), and recording it here would make
      -- next_op's deferred arm raise TLB_IMISS for it instead. This is the same
      -- narrowing tlb_exc_is_i applies, for the same reason.
      if (exc_en = '1' and v_ifetch = '1'
          and (exc_kind = IMISS or exc_kind = IPROT)) then
        inst_fault <= '1';
      else
        inst_fault <= '0';
      end if;

      -- Kind of the recorded I-fetch fault.
      if (exc_kind = IPROT) then
        inst_fault_prot <= '1';
      else
        inst_fault_prot <= '0';
      end if;

      tlb_exc_en   <= exc_en;
      tlb_exc_kind <= exc_kind;
      tlb_exc_pend <= exc_en;
      tlb_fault_va <= fva;
      -- I-fetch faults (IMISS/IPROT) come only from the i_at_translated
      -- branch above; flag them so the datapath captures the I-side restart
      -- PC. MULTI_HIT dispatches to the existing General Illegal register-model
      -- exception (decode_core.vhm), which captures SPC/SSR the same way any
      -- other illegal-instruction trap does -- it does not need this TLB-specific
      -- I-side restart-PC side channel, so it is deliberately excluded here.
      if (exc_en = '1' and (exc_kind = IMISS or exc_kind = IPROT)) then
        tlb_exc_is_i <= '1';
      else
        tlb_exc_is_i <= '0';
      end if;

      -- tlb_exc_ifetch: "this fault's VA is an instruction-fetch VA", for
      -- EVERY exc_kind the i_at_translated branch can raise, including
      -- MULTI_HIT. See its declaration comment for why this must NOT be
      -- narrowed the way tlb_exc_is_i correctly is: this predicate gates
      -- whether the D-side access shadow (ma_numz/ma_base/ma_autoupd) may
      -- be trusted, not which restart-PC derivation to use.
      tlb_exc_ifetch <= v_ifetch;

    end process;

    -- SH-4 EXPEVT code for the detected fault kind.
    --
    -- TODO: remove this port and mux; kept only as documentation.
    --
    -- CAVEAT, verified 2026-08-21: this signal has NO READER. It reaches
    -- datapath.vhm only as the tlb_exc_expevt port and that port is never read
    -- there (it appears in the process sensitivity list and nowhere else), so
    -- it drives nothing. The code software actually observes is written by the
    -- dispatched exception microcode from its own system-plane immediate
    -- (decode/gen-go/spec/sh4/exceptions.toml, the `xbus = "<code>"` line on
    -- each entry). The table below is kept in step with those immediates so it
    -- does not become a second, contradicting source of truth -- but changing a
    -- value here changes nothing on its own. Do NOT hang design rationale off
    -- these arms; they are dead.
    --
    -- IMISS=0x040 DMISS_R=0x060
    -- DMISS_W=0x080 IPROT=0x0A0 DPROT_R/W=0x0C0. MULTI_HIT does NOT dispatch
    -- through this EXPEVT-driven path (it dispatches to the existing General
    -- Illegal register-model exception, which writes its own EXPEVT=0x180 via
    -- microcode), so no code is minted for it here; "others" is a required
    -- exhaustive arm, not a real dispatch. (This used to add "because decoder
    -- imm-field capacity is full"; that is false -- components_pkg.vhd,
    -- tlb_exc_kind_t.)
    with tlb_exc_kind select tlb_exc_expevt <=
      x"040" when IMISS,
      x"060" when DMISS_R,
      x"080" when DMISS_W,
      x"0A0" when IPROT,
      x"0C0" when DPROT_R,
      x"0C0" when DPROT_W,
      -- P4 privilege violation: 0x0C0, matching the DPROT entries it dispatches
      -- through. Why not SH-4's 0x0E0/0x100, and what it would cost to use
      -- them: components_pkg.vhd, tlb_exc_kind_t.
      x"0C0" when P4_USER_R,
      x"0C0" when P4_USER_W,
      (others => '0') when others;

    -- MMUFSR partial word (KIND/PROT/ITLB/WRITE; bits 12=VALID and 4=USER are
    -- filled in by the datapath fault-capture block -- VALID because capture
    -- only runs on a real fault, USER because it needs this.sr.md sampled at
    -- capture time, which is not available here). MULTI_HIT (KIND=7) still
    -- gets its KIND nibble here; the datapath capture block is responsible
    -- for leaving the rest of the low byte (including USER) at 0 for it.
    process (tlb_exc_kind) is

      variable kind_nibble : std_logic_vector(3 downto 0);
      variable prot_b      : std_logic;
      variable itlb_b      : std_logic;
      variable write_b     : std_logic;

    begin

      case tlb_exc_kind is

        when IMISS =>

          kind_nibble := x"1"; prot_b := '0'; itlb_b := '1'; write_b := '0';

        when DMISS_R =>

          kind_nibble := x"2"; prot_b := '0'; itlb_b := '0'; write_b := '0';

        when DMISS_W =>

          kind_nibble := x"3"; prot_b := '0'; itlb_b := '0'; write_b := '1';

        when IPROT =>

          kind_nibble := x"4"; prot_b := '1'; itlb_b := '1'; write_b := '0';

        when DPROT_R =>

          kind_nibble := x"5"; prot_b := '1'; itlb_b := '0'; write_b := '0';

        when DPROT_W =>

          kind_nibble := x"6"; prot_b := '1'; itlb_b := '0'; write_b := '1';

        when MULTI_HIT =>

          kind_nibble := x"7"; prot_b := '0'; itlb_b := '0'; write_b := '0';

        -- P4 privilege violation. KIND 8/9 extend the MMUFSR kind space past
        -- the seven TLB causes; PROT=1 (it IS a protection failure, just a
        -- segment-level rather than a page-level one), ITLB=0 (D-side by
        -- construction), WRITE from the direction. USER is not set here: the
        -- datapath ORs bit 4 in from this.sr.md at capture time and, since
        -- reaching this kind at all requires SR.MD='0', it always lands as 1.

        when P4_USER_R =>

          kind_nibble := x"8"; prot_b := '1'; itlb_b := '0'; write_b := '0';

        when P4_USER_W =>

          kind_nibble := x"9"; prot_b := '1'; itlb_b := '0'; write_b := '1';

        when others =>

          kind_nibble := x"0"; prot_b := '0'; itlb_b := '0'; write_b := '0';

      end case;

      tlb_exc_fsr <= '0' & kind_nibble & "000" & '0' & prot_b & itlb_b & '0' & write_b;

    end process;

  end generate g_mmu;

  g_no_mmu : if not PRIV_ARCH generate
    mmu_o           <= NULL_MMU_O;
    mmu_d_at_i      <= '0';
    mmu_d_c_i       <= '0';
    tlb_exc_en      <= '0';
    tlb_exc_kind    <= IMISS;
    tlb_exc_pend    <= '0';
    tlb_exc_fsr     <= (others => '0');
    tlb_fault_va    <= (others => '0');
    tlb_exc_expevt  <= (others => '0');
    inst_fault      <= '0'; -- tie off so J1/J2 datapath sees a constant, not a float
    inst_fault_prot <= '0';
    tlb_exc_is_i    <= '0'; -- tie off so J1/J2 datapath sees a constant, not a float
    tlb_exc_ifetch  <= '0'; -- tie off so J1/J2 datapath sees a constant, not a float
  end generate g_no_mmu;

end architecture stru;
