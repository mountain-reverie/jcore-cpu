-- ===========================================================================
-- tlb -- J4 software-loaded translation lookaside buffer (PRIV_ARCH only).
--
-- SINGLE-PORT, fully associative, software-loaded TLB with a configurable
-- entry count (generic `entries`, power of two). ONE combinational lookup port
-- per instance; a clocked process handles installs (LDTLB / hardware walker)
-- and the MMUCR.TI flush. Variable page sizes via PageMask ptel(11:8)
-- (4KB..1GB); Linux uses a 16KB base page plus 64KB..256MB huge pages.
--
-- core/cpu.vhd instantiates this TWICE under `g_mmu : if PRIV_ARCH generate`:
-- `u_itlb` (instruction fetch, generic side_is_i => true) and `u_dtlb`
-- (load/store, side_is_i => false). Each instance owns its OWN `ram`, so the
-- two arrays can be placed beside their respective caches instead of one
-- dual-ported block straddling both. Consequences of the split:
--   * A hardware-walker install goes to the FAULTING side only (walk_side_i).
--   * An LDTLB (software install) writes BOTH arrays -- conservative, and it
--     preserves the semantics of guards that LDTLB a page then both fetch and
--     load from it.
--   * MMUCR.TI flushes both; asid/md/at feed both.
--   * Multi-hit is detected PER ARRAY. The same page resident in both the
--     ITLB and the DTLB is NOT a multi-hit -- they are different arrays.
--
-- This is the multi-tenant isolation boundary. The lookup hit condition is
--     VALID and STALE=0 and VPN-match and (GLOBAL or ASID_TAG=ASIDR)
-- and a hit additionally has its U/W/X permissions checked against the access
-- type and SR.MD before the access is allowed. On a hit the entry's PPN
-- (pa_tag=PPN[27:13], pa12=PPN[12]) relocates the virtual address to the
-- physical address in cpu.vhd, so the L1 caches are physically indexed (PIPT).
--
-- FULL SOFTWARE & SECURITY ARCHITECTURE (the kernel's contract, the isolation
-- and threat model, per-bit PTE semantics, revocation rules): see
--     docs/architecture/tlb.md   (hardware/block view: docs/architecture/j4.md)
-- Behaviour is locked by the sim/tests/mmu*.S guards (mmuxlate, mmufault,
-- mmuasid, mmustale, mmustore, mmureloc*, mmusplit, ...).
--
-- Entry layout (work.cpu2j0_components_pack tlb_entry_t) and PTEL flag bits:
--   PPN = PTEL[31:10]; W7 X6 U5 D4 C3 G2 STALE1 V0.
-- ===========================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use work.cpu2j0_components_pack.all;

entity tlb is
  generic (
    -- Number of fully-associative entries. MUST be a power of two: the lookup
    -- reduction tree halves the candidate set at every level.
    entries : natural := 32;
    -- true  => instruction-fetch port (X / SMEP permission rules, `we` unused)
    -- false => load/store port (W-on-store permission rule)
    side_is_i : boolean := false
  );
  port (
    clk : in    std_logic;
    -- Lookup: VA in, translation + status out. we=1 marks the access a store
    -- (D side only; ignored when side_is_i).
    va        : in    std_logic_vector(31 downto 0);
    we        : in    std_logic;
    pa_tag    : out   std_logic_vector(14 downto 0); -- PA[27:13] of the hit entry
    pa12      : out   std_logic;                     -- PA[12] (PIPT relocation)
    page_mask : out   std_logic_vector(3 downto 0);  -- PageMask of the hit entry
    c         : out   std_logic;                     -- cacheable (PTE.C)
    hit       : out   std_logic;                     -- usable match found
    prot      : out   std_logic;                     -- hit but permission violated
    multihit  : out   std_logic;                     -- S-I5: >1 usable match (fatal, priority over hit)
    -- Current context + mode for the lookup.
    asid : in    std_logic_vector(15 downto 0); -- live ASIDR (lookup tag)
    md   : in    std_logic;                     -- SR.MD (1=privileged)
    at   : in    std_logic;                     -- MMUCR.AT (translate enable)
    -- Install (LDTLB / walker) + flush (MMUCR.TI) inputs.
    tlb_wr   : in    std_logic;                      -- 1 => install {asidr,pteh,ptel}
    pteh_vpn : in    std_logic_vector(31 downto 12); -- VPN to install
    ptel     : in    std_logic_vector(31 downto 0);  -- PPN + flags to install
    asidr    : in    std_logic_vector(15 downto 0);  -- ASID_TAG to stamp on install
    ti       : in    std_logic                       -- 1 => flush all entries
  );
end entity tlb;

architecture rtl of tlb is

  -- Number of halving levels in the reduction tree: log2(entries).

  function log2_ceil (
    n : natural
  ) return natural is

    variable r : natural := 0;
    variable v : natural := 1;

  begin

    while v < n loop

      v := v * 2;
      r := r + 1;

    end loop;

    return r;

  end function log2_ceil;

  constant levels : natural := log2_ceil(entries);

  signal ram : tlb_ram_t(0 to entries - 1) := (others => TLB_ENTRY_RESET);

  -- Usable-match predicate for the lookup scan.
  -- Usable = VALID and not STALE and masked-VPN equal and (GLOBAL or ASID
  -- match) -- the isolation predicate of docs/architecture/tlb.md section 3.

  function tlb_match (
    entry : tlb_entry_t;
    va    : std_logic_vector(31 downto 0);
    asid  : std_logic_vector(15 downto 0)
  ) return boolean is
  begin

    -- page_mask selects how many low VPN bits are ignored, so superpages match
    -- a range of VAs.
    return (entry.valid = '1'
            and entry.stale = '0'                               -- STALE (PTEL[1]) = SW soft-invalidate/revocation (mmustale)
            and ((entry.vpn xor va(31 downto 12)) and vpn_compare_mask(entry.page_mask)) = (entry.vpn'range => '0')
            and (entry.global = '1' or entry.asid_tag = asid)); -- ASID isolation (mmuasid)

  end function tlb_match;

  -- Log-depth reduction for the lookup. Replaces the sequential for-loop,
  -- which carried hit_found/hit_pa/prot across iterations and so synthesized
  -- to an N-deep mux chain -- the head of the j4c critical path.
  --
  -- Field semantics are preserved EXACTLY:
  --   hit    = OR of matches
  --   multi  = two or more matches
  --   pa/pa12/page_mask/c = HIGHEST-INDEX match wins (loop's last-writer-wins)
  --   prot   = STICKY OR over matching entries (loop never clears prot), which
  --            is NOT the same as taking the winning entry's prot bit.

  type sel_t is record
    hit       : std_logic;
    multi     : std_logic;
    pa        : std_logic_vector(14 downto 0);
    pa12      : std_logic;
    page_mask : std_logic_vector(3 downto 0);
    c         : std_logic;
    prot      : std_logic;
  end record sel_t;

  type sel_arr_t is array (natural range <>) of sel_t;

  constant sel_none : sel_t :=
  (
    hit       => '0',
    multi     => '0',
    pa        => (others => '0'),
    pa12      => '0',
    page_mask => (others => '0'),
    c         => '0',
    prot      => '0'
  );

  -- lo = lower entry indices, hi = higher. hi wins the field select so the
  -- tree reproduces the loop's ascending last-writer-wins order.

  function combine (
    lo,
    hi : sel_t
  ) return sel_t is

    variable r : sel_t;

  begin

    r.hit   := lo.hit or hi.hit;
    r.multi := lo.multi or hi.multi or (lo.hit and hi.hit);
    r.prot  := lo.prot or hi.prot; -- sticky OR, matches the loop

    if (hi.hit = '1') then
      r.pa        := hi.pa; r.pa12 := hi.pa12;
      r.page_mask := hi.page_mask; r.c := hi.c;
    else
      r.pa        := lo.pa; r.pa12 := lo.pa12;
      r.page_mask := lo.page_mask; r.c := lo.c;
    end if;

    return r;

  end function combine;

begin

  -- Combinational lookup. Scan all `entries` slots; a usable match requires
  -- VALID and not-STALE and VPN match and (GLOBAL or ASID match) -- the
  -- isolation predicate (docs/architecture/tlb.md section 3).
  --
  -- I side (side_is_i): an instruction fetch is a protection violation when
  -- the page is non-executable (X=0) OR it is a supervisor page (U=0) accessed
  -- from user mode (MD=0) OR (SMEP) it is a user page (U=1) fetched from
  -- kernel mode (MD=1) -- a kernel is never permitted to execute
  -- user-controlled code.
  --
  -- D side: a data access is a protection violation when it is a supervisor
  -- page (U=0) accessed from user mode (MD=0), OR it is a STORE (we=1) to a
  -- non-writable (W=0) page -- the W check applies to the kernel too (no
  -- privileged write bypass). There is no separate read bit (readability = U
  -- for user, else kernel). Guard mmufault (DPROT_R/DPROT_W).
  --
  -- Both sides additionally fault a global user page (S-I7, mmuglobal).
  -- S-I5: a multi-hit (>1 usable match, e.g. a duplicate VPN+ASID install) is
  -- a defined non-recoverable fault (multihit), never a silent PA pick. It is
  -- per-array: a page resident in both the ITLB and the DTLB is not a
  -- multi-hit.
  process (ram, va, we, asid, md) is

    variable entry : tlb_entry_t;
    variable m     : std_logic;
    variable leaf  : sel_arr_t(0 to entries - 1);
    variable lvl   : sel_arr_t(0 to entries - 1);
    variable n     : natural;
    variable root  : sel_t;
    variable viol  : boolean;

  begin

    -- Leaves: all comparisons are independent and evaluate in parallel.
    -- Fields are masked to zero on a non-match so the root reproduces the
    -- loop's zero initialisers when nothing hits.
    for k in 0 to entries - 1 loop

      entry := ram(k);

      if (tlb_match(entry, va, asid)) then
        m := '1';
      else
        m := '0';
      end if;

      leaf(k)     := sel_none;
      leaf(k).hit := m;

      if (m = '1') then
        leaf(k).pa        := entry.ppn(27 downto 13);
        leaf(k).pa12      := entry.ppn(12);
        leaf(k).page_mask := entry.page_mask;
        leaf(k).c         := entry.c;
        if (side_is_i) then
          viol := entry.x = '0' or (entry.u = '0' and md = '0')  -- X / user-on-super (mmufault)
                  or (entry.u = '1' and md = '1');               -- SMEP: kernel fetch of user page (mmusmep)
        else
          viol := (entry.u = '0' and md = '0')
                  or (we = '1' and entry.w = '0');               -- store to non-writable (mmustore)
        end if;
        if (viol or (entry.global = '1' and entry.u = '1')) then -- S-I7: global user page illegal (mmuglobal)
          leaf(k).prot := '1';
        end if;
      end if;

    end loop;

    -- Balanced reduction: entries -> ... -> 1, log2(entries) statically
    -- unrollable levels (lvl_i is a locally-static loop parameter and
    -- `entries` is a generic, so n and the inner bound are elaboration-time
    -- constants -- required by some synthesis tools that reject
    -- variable-bound loops). 2*j stays the LOWER half at every level so the
    -- highest-index-wins field select is unchanged.
    lvl := leaf;

    for lvl_i in 0 to levels - 1 loop

      n := entries / (2 ** lvl_i);

      for j in 0 to (n / 2) - 1 loop

        lvl(j) := combine(lvl(2 * j), lvl(2 * j + 1));

      end loop;

    end loop;

    root := lvl(0);

    hit       <= root.hit;
    pa_tag    <= root.pa;
    pa12      <= root.pa12;
    page_mask <= root.page_mask;
    c         <= root.c;
    prot      <= root.prot and root.hit;                         -- prot only meaningful on a hit
    multihit  <= root.multi;                                     -- S-I5: duplicate VPN+ASID install (fatal)

  end process;

  -- Clocked install (LDTLB / walker) + MMUCR.TI flush. TI clears VALID (and the
  -- NRU "used" state) on every entry -> a full revocation
  -- (docs/architecture/tlb.md section 6). An install latches the whole entry
  -- atomically from {asidr, pteh_vpn, ptel} into one NRU-chosen slot (no
  -- half-written, matchable entry). NRU replacement: prefer an invalid slot,
  -- else a not-recently-used one, else clear all "used" bits and take slot 0.
  -- The installed entry's flags come straight from PTEL (W7 X6 U5 D4 C3 G2
  -- STALE1 V0); STALE is preserved so software can install an entry already
  -- soft-invalidated.
  process (clk) is

    variable idx       : integer range 0 to entries - 1;
    variable nru_idx   : integer range 0 to entries - 1;
    variable dedup     : boolean;
    variable nru_found : boolean;
    variable all_used  : boolean;

  begin

    if rising_edge(clk) then
      if (ti = '1') then

        for k in 0 to entries - 1 loop

          ram(k).valid <= '0';
          ram(k).used  <= '0';

        end loop;

      elsif (tlb_wr = '1') then
        -- Slot selection for an install. Dedup takes PRIORITY over NRU:
        -- if a valid entry already OVERLAPS this mapping's range under this
        -- ASID (or either side is global), overwrite THAT slot so the
        -- install replaces the mapping in place. This mirrors SH-4 LDTLB
        -- semantics and prevents a benign re-install -- e.g. Linux upgrading
        -- a page's permissions (dirty bit) while it is still resident, or
        -- installing a narrower page inside a resident superpage -- from
        -- leaving TWO matching entries, which the S-I5 multi-hit check would
        -- otherwise (correctly) flag as a fatal illegal state. With dedup, a
        -- multi-hit can only arise from a genuinely inconsistent SW/HW
        -- state, never normal use.
        --
        -- Overlap uses a MASKED compare under the intersection of the two
        -- entries' page masks (the coarser/wider of the two), not exact VPN
        -- equality: a resident 1 MB superpage and a newly-installed 4 KB
        -- page inside it have different vpn values but genuinely overlap in
        -- VA range, and exact equality (master's old compare) could not see
        -- that -- both stayed valid and a later lookup hit both, producing
        -- a fatal S-I5 multi-hit on a perfectly reasonable software
        -- sequence (docs/architecture/tlb.md S-I5). Exact-VPN equality is
        -- the special case where both masks are "0000" (4 KB, no bits
        -- ignored), so this subsumes the old dedup path.
        --
        -- Deliberately does NOT gate on ram(k).stale, unlike the lookup
        -- path's tlb_match (which does): an install must consider stale
        -- entries too, or it could install a mapping that overlaps one it
        -- cannot see (a stale entry is a soft-invalidated-but-still-resident
        -- slot, not an absent one). This asymmetry is intentional.
        --
        -- Absent a dedup match, fall back to NRU: first invalid slot, else
        -- first unused; if all valid+used, clear used bits and take slot 0.
        idx      := 0; nru_idx := 0; dedup := false; nru_found := false;
        all_used := true;

        for k in 0 to entries - 1 loop

          if (not dedup and ram(k).valid = '1'
              and ((ram(k).vpn xor pteh_vpn)
                   and (vpn_compare_mask(ram(k).page_mask)
                        and vpn_compare_mask(ptel(11 downto 8))))
                  = (ram(k).vpn'range => '0')
              and (ram(k).global = '1' or ptel(2) = '1'
                    or ram(k).asid_tag = asidr)) then
            idx := k; dedup := true;
          end if;

          if (not nru_found) then
            if (ram(k).valid = '0') then
              nru_idx := k; nru_found := true;
            elsif (ram(k).used = '0') then
              if (all_used) then
                nru_idx := k;
              end if;
              all_used := false;
            end if;
          end if;

        end loop;

        if (not dedup) then
          if (not nru_found and all_used) then
            -- all entries valid+used: clear used bits, write to slot 0
            for k in 0 to entries - 1 loop

              ram(k).used <= '0';

            end loop;

            idx := 0;
          else
            idx := nru_idx;
          end if;
        end if;
        ram(idx).valid     <= '1';
        ram(idx).used      <= '1';
        ram(idx).vpn       <= pteh_vpn;
        ram(idx).asid_tag  <= asidr;
        ram(idx).page_mask <= ptel(11 downto 8);
        ram(idx).ppn       <= ptel(31 downto 10);
        ram(idx).w         <= ptel(7);
        ram(idx).x         <= ptel(6);
        ram(idx).u         <= ptel(5);
        ram(idx).d         <= ptel(4);
        ram(idx).c         <= ptel(3);
        ram(idx).global    <= ptel(2);
        ram(idx).stale     <= ptel(1);
      end if;
    end if;

  end process;

end architecture rtl;
