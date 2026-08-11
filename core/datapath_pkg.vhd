library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.cpu2j0_pack.all;
  use work.decode_pack.all;
  use work.cpu2j0_components_pack.all;
  use work.mult_pkg.all;

package datapath_pack is

  -- SR bit Positions
  constant t  : integer range 0 to 30 := 0;
  constant s  : integer range 0 to 30 := 1;
  constant cs : integer range 0 to 30 := 2;   -- SH-2A CLIPS/CLIPU saturation flag (J2A only)
  constant i0 : integer range 0 to 30 := 4;
  constant i1 : integer range 0 to 30 := 5;
  constant i2 : integer range 0 to 30 := 6;
  constant i3 : integer range 0 to 30 := 7;
  constant q  : integer range 0 to 30 := 8;
  constant m  : integer range 0 to 30 := 9;
  constant bl : integer range 0 to 30 := 28;
  constant rb : integer range 0 to 30 := 29;
  constant md : integer range 0 to 30 := 30;

  type segment_t is (seg_p0, seg_p1, seg_p2, seg_p3, seg_p4);

  -- P4 MMU-register MMIO selector (J4). Kept separate from
  -- decode_pack.mmu_reg_sel_t so the cold TSBBR/TSBCFG selectors do NOT widen
  -- that base-present pipeline enum (which would leak flops into j1/j2). This
  -- type is used only by a datapath process variable inside PRIV_ARCH-guarded
  -- code, so it is dead/eliminated in base builds.

  type p4_sel_t is (
    p4_none, p4_mmucr, p4_ttb, p4_tea, p4_tsbbr, p4_tsbcfg, p4_tsbptr, p4_mmufsr,
    p4_tra, p4_expevt, p4_intevt, p4_tsbslot, p4_tsbvseed, p4_tsbvict,
    -- Phase 3 (Task 1): read-only P4 aliases for the STC-only registers
    -- PTEH/PTEL/ASIDR, landed ahead of retiring the STC forms (see
    -- docs/superpowers/specs/2026-08-09-hardware-tsb-walker-design.md P3.1),
    -- plus the walker counter window's P4 home (P3.2). Both the STC
    -- read path and these aliases answer simultaneously for now; nothing
    -- is retired by this change.
    p4_pteh, p4_ptel, p4_asidr, p4_tsbcnt
  );

  function seg_decode (
    va : std_logic_vector(31 downto 0)
  ) return segment_t;

  -- TSB pointer assist (hardware-spec §2.8): address of the TSB slot for the
  -- faulting VPN, latched into TSBPTR on every fault. Factored out of
  -- datapath.vhm because there are now TWO capture sites -- the immediate
  -- (D-side / MULTI_HIT) one and the deferred I-fetch one, which sources the VA
  -- from the faulting instruction's own if_pc instead of the live tlb_fault_va.
  --   vpn    = va[31:12]                       (4 KB page number)
  --   a1     = asid xor (asid << 5)
  --   amix   = a1 xor (a1 >> 9)
  --   hash   = (HASH_MODE=1 ? vpn xor (vpn >> HASH_SHIFT) : vpn) xor amix
  --   mask   = (1 << TSB_SIZE_LOG) - 1
  --   TSBPTR = (TSBBR and not 0x1F) or ((hash and mask) << 5)
  -- TSBBR[N+4:5] are reserved-0 so clearing the low five bits and ORing the
  -- 32-byte-scaled index suffices (no variable base mask needed).
  --
  -- Phase-2 Task 4: TSB_SIZE_LOG counts SETS, not entries, and this returns a
  -- 32-byte-aligned SET address. A set is one 32-byte line holding two
  -- contiguous 16-byte entries -- way 0 at +0/+4/+8/+12 (tag_hi, tag_lo, data,
  -- reserved), way 1 at +16/+20/+24/+28. Both ways of a set therefore live in
  -- ONE line, which is what makes the "overwrite the matching way" rule in the
  -- kernel (arch/sh/mm/tlb-jcore.c) cheap: software already has both tags in
  -- hand from the line it read. Associativity here is a PERFORMANCE change --
  -- it absorbs conflict misses -- and is deliberately not claimed as an
  -- isolation mechanism.
  --
  -- ASID is folded into the INDEX, not just the tag. Without it the same VA in
  -- two address spaces always lands in the same set, and since a TSB hit is
  -- ~11x cheaper than a miss that gives an attacker a deterministic, targeted
  -- eviction primitive: to evict a victim's entry for VA X, touch VA X. With
  -- the fold the attacker must first search for a colliding VA, not knowing
  -- the victim's ASID.
  --
  -- The fold is NOT a bare `vpn xor asid`. US 5,899,994 records that XORing a
  -- narrow process id straight into the index distributes badly. The naive
  -- `asid << 7` spreading term is worse than useless here: for the common
  -- TSB_SIZE_LOG <= 7 it lands entirely ABOVE the index and contributes
  -- nothing, degenerating to the bare XOR. Instead `asid << 5` spreads, and
  -- the `>> 9` refold brings that spread back DOWN so that every index bit,
  -- at any TSB size, is a function of three different ASID bits with a
  -- different triple per bit.
  --
  -- Applied in BOTH hash modes: HASH_MODE selects the VPN xor-fold only. A
  -- mode that silently disabled the ASID fold would be a way to switch this
  -- hardening off. Hardening, not a boundary: the fold is a constant XOR per
  -- ASID and so is separable and brute-forceable -- it raises the cost of a
  -- targeted eviction, it does not bound it.
  --
  -- Note the fold is a constant XOR for a fixed ASID, hence a bijection on the
  -- set index: within one address space the conflict distribution is
  -- bit-for-bit what it was before the fold, so this cannot introduce
  -- thrashing in a single-ASID workload.

  function tsb_ptr (
    va     : std_logic_vector(31 downto 0);
    tsbcfg : std_logic_vector(31 downto 0);
    tsbbr  : std_logic_vector(31 downto 0);
    asid   : std_logic_vector(15 downto 0)
  ) return std_logic_vector;

  -- TSB victim selector (Phase-2 Task 4, Part B).
  --
  -- One step of a 16-bit Fibonacci LFSR, taps 16,14,13,11 (x^16+x^14+x^13+x^11+1,
  -- maximal length 65535). The nomination software reads is bit 0 of the NEW
  -- state, i.e. which of the two ways to replace when neither tag matches.
  --
  -- The SEED IS NOT IN THE HARDWARE. It is written by the OS at MMU init through
  -- a WRITE-ONLY register (0xFF00004C). A constant seed compiled into this file
  -- would be public -- this is an open-source core, so the polynomial and any
  -- built-in seed are readable by anyone, and a victim selector whose sequence
  -- an attacker can replay offline is no better than a fixed choice. Only the
  -- 1-bit nomination is exposed (0xFF000050); neither the seed nor the LFSR
  -- state can be read back, so an attacker cannot resynchronise to the sequence
  -- even by observing evictions -- each read consumes one bit and advances.
  --
  -- Zero is the LFSR's lock-up state. Rather than leave an un-seeded machine
  -- silently pinned to way 0 (a correct-but-slow failure nobody would notice),
  -- state 0 self-heals to a fixed non-secret constant. That constant carries no
  -- security claim; it exists so the selector still round-robins before the OS
  -- has seeded it. Security comes from the OS seed, and only from it.

  function tsb_lfsr_next (
    state : std_logic_vector(15 downto 0)
  ) return std_logic_vector;

  component datapath is
    generic (
      priv_arch          : boolean := false;
      sh2a_arch          : boolean := false;
      early_regfile_read : boolean := false
    );
    port (
      clk         : in    std_logic;
      rst         : in    std_logic;
      debug       : in    std_logic;
      enter_debug : out   std_logic;
      slot        : out   std_logic;
      reg         : in    reg_ctrl_t;
      func        : in    func_ctrl_t;
      sr_ctrl     : in    sr_ctrl_t;
      mac         : in    mac_ctrl_t;
      mem         : in    mem_ctrl_t;
      instr       : in    instr_ctrl_t;
      pc_ctrl     : in    pc_ctrl_t;
      buses       : in    buses_ctrl_t;
      coproc      : in    coproc_ctrl_t;
      db_lock     : out   std_logic;
      db_o        : out   cpu_data_o_t;
      db_i        : in    cpu_data_i_t;
      inst_o      : out   cpu_instruction_o_t;
      inst_i      : in    cpu_instruction_i_t;
      debug_o     : out   cpu_debug_o_t;
      debug_i     : in    cpu_debug_i_t;
      macin1      : out   std_logic_vector(31 downto 0);
      macin2      : out   std_logic_vector(31 downto 0);
      mach        : in    std_logic_vector(31 downto 0);
      macl        : in    std_logic_vector(31 downto 0);
      -- J1: high while mult(seq) iterates -> stretch the slot. '0' for mult(stru).
      mult_stall : in    std_logic;
      mac_s      : out   std_logic;
      -- SH-2A DIVU/DIVS divider unit ports (Task 2); mirrors macin1/macin2/
      -- mach/macl above. '0'/unused on base (sh2a_arch=false).
      div_dividend       : out   std_logic_vector(31 downto 0);
      div_divisor        : out   std_logic_vector(31 downto 0);
      div_start          : out   std_logic;
      div_is_signed      : out   std_logic;
      div_quotient       : in    std_logic_vector(31 downto 0) := (others => '0');
      t_bcc              : out   std_logic;
      ibit               : out   std_logic_vector(3 downto 0);
      if_dr              : out   std_logic_vector(15 downto 0);
      if_dr_next         : out   std_logic_vector(15 downto 0);
      if_stall           : out   std_logic;
      mask_int           : out   std_logic;
      illegal_delay_slot : out   std_logic;
      illegal_instr      : out   std_logic;
      copreg             : in    std_logic_vector(7 downto 0);
      cop_i              : in    cop_i_t;
      cop_o              : out   cop_o_t;
      priv_o             : out   cpu_priv_o_t := NULL_PRIV_O;
      mmu_regs_o         : out   mmu_reg_t := MMU_REG_RESET;
      -- Zero-skew placement replica of mmu_regs_o.asidr(15 downto 0) for the
      -- TLB lookup compare only (Phase 4a); see core/datapath.vhm.
      asidr_tlb_o      : out   std_logic_vector(15 downto 0) := (others => '0');
      sr_o             : out   sr_t;
      tlb_squash_o     : out   std_logic := '0';
      tlb_exc_pend     : in    std_logic := '0';
      tlb_fault_va     : in    std_logic_vector(31 downto 0) := (others => '0');
      tlb_exc_expevt   : in    std_logic_vector(11 downto 0) := (others => '0');
      tlb_exc_fsr      : in    std_logic_vector(12 downto 0) := (others => '0');
      delay_slot       : in    std_logic := '0';
      tlb_exc_is_i     : in    std_logic := '0';
      inst_fault       : in    std_logic := '0';
      inst_fault_prot  : in    std_logic := '0';
      if_fault_o       : out   std_logic;
      if_fault_prot_o  : out   std_logic;
      id_delay_slot    : in    std_logic := '0';
      if_fault_cap     : in    std_logic := '0';
      tlb_exc_ifetch   : in    std_logic := '0';
      if_pc            : out   std_logic_vector(31 downto 0);
      ex_if_pc         : in    std_logic_vector(31 downto 0) := (others => '0');
      walk_cnt_walks_i : in    std_logic_vector(15 downto 0) := (others => '0');
      walk_cnt_hits_i  : in    std_logic_vector(15 downto 0) := (others => '0')
    );
  end component datapath;

end package datapath_pack;

package body datapath_pack is

  function seg_decode (
    va : std_logic_vector(31 downto 0)
  ) return segment_t is
  begin

    if (va(31 downto 24) = x"FF") then
      return SEG_P4;
    elsif (va(31 downto 29) = "100") then
      return SEG_P1;
    elsif (va(31 downto 29) = "101") then
      return SEG_P2;
    elsif (va(31 downto 29) = "110" or va(31 downto 29) = "111") then
      return SEG_P3;
    else
      return SEG_P0;
    end if;

  end function seg_decode;

  function tsb_ptr (
    va     : std_logic_vector(31 downto 0);
    tsbcfg : std_logic_vector(31 downto 0);
    tsbbr  : std_logic_vector(31 downto 0);
    asid   : std_logic_vector(15 downto 0)
  ) return std_logic_vector is

    variable v_vpn   : unsigned(31 downto 0);
    variable v_asid  : unsigned(31 downto 0);
    variable v_a1    : unsigned(31 downto 0);
    variable v_amix  : unsigned(31 downto 0);
    variable v_hash  : unsigned(31 downto 0);
    variable v_mask  : unsigned(31 downto 0);
    variable v_idx   : unsigned(31 downto 0);
    variable v_shift : integer range 0 to 31;
    variable v_size  : integer range 0 to 31;

  begin

    v_vpn   := x"000" & unsigned(va(31 downto 12));
    v_asid  := x"0000" & unsigned(asid);
    v_shift := to_integer(unsigned(tsbcfg(7 downto 4)));
    v_size  := to_integer(unsigned(tsbbr(3 downto 0)));

    -- Spread ASID across the VPN's width, then refold it back down so its
    -- bits reach the low index bits too (see the header comment).
    v_a1   := v_asid xor shift_left(v_asid, 5);
    v_amix := v_a1 xor shift_right(v_a1, 9);

    if (tsbcfg(3 downto 0) = x"1") then
      v_hash := v_vpn xor shift_right(v_vpn, v_shift);
    else
      v_hash := v_vpn;
    end if;

    v_hash := v_hash xor v_amix;

    v_mask := shift_left(to_unsigned(1, 32), v_size) - 1;
    v_idx  := (v_hash and v_mask);
    return (tsbbr and x"FFFFFFE0") or std_logic_vector(shift_left(v_idx, 5));

  end function tsb_ptr;

  function tsb_lfsr_next (
    state : std_logic_vector(15 downto 0)
  ) return std_logic_vector is

    variable v_s  : std_logic_vector(15 downto 0);
    variable v_fb : std_logic;

  begin

    -- Self-heal out of the all-zero lock-up state (see the header comment).
    if (state = x"0000") then
      v_s := x"ACE1";
    else
      v_s := state;
    end if;

    v_fb := v_s(15) xor v_s(13) xor v_s(12) xor v_s(10);

    return v_s(14 downto 0) & v_fb;

  end function tsb_lfsr_next;

end package body datapath_pack;
