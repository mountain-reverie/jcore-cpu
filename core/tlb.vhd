-- ===========================================================================
-- tlb -- J4 walker-loaded translation lookaside buffer (PRIV_ARCH only).
--
-- SINGLE-PORT, fully associative TLB with a configurable entry count (generic
-- `entries`, power of two). ONE combinational lookup port per instance; a
-- clocked process handles installs (hardware TSB walker -- the only installer;
-- there is no software install instruction) and the MMUCR.TI flush. Variable page sizes via PageMask ptel(11:8)
-- (4KB..1GB); Linux uses a 16KB base page plus 64KB..256MB huge pages.
--
-- core/cpu.vhd instantiates this TWICE under `g_mmu : if PRIV_ARCH generate`:
-- `u_itlb` (instruction fetch, generic side_is_i => true) and `u_dtlb`
-- (load/store, side_is_i => false). Each instance owns its OWN `ram`, so the
-- two arrays can be placed beside their respective caches instead of one
-- dual-ported block straddling both. Consequences of the split:
--   * An install goes to the FAULTING side only (walk_side_i), which is
--     demand-driven routing by construction: an I-side miss can only want an
--     ITLB entry and a D-side miss a DTLB entry. Nothing writes both arrays.
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
    -- Synchronous reset. Revokes every entry, exactly as MMUCR.TI does -- see
    -- the flush process at the bottom of this file for why the `ram` signal's
    -- initialiser is not a substitute.
    rst : in    std_logic;
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
    -- Install (hardware walker) + flush (MMUCR.TI) inputs.
    tlb_wr   : in    std_logic;                      -- 1 => install {asidr,pteh,ptel}
    pteh_vpn : in    std_logic_vector(31 downto 12); -- VPN to install
    ptel     : in    std_logic_vector(31 downto 0);  -- PPN + flags to install
    asidr    : in    std_logic_vector(15 downto 0);  -- ASID_TAG to stamp on install
    -- 1 => this install is SPECULATIVE (the I->D shadow fill in cpu.vhd), not
    -- a demand fill resolving an access that is happening now. Two effects,
    -- both confined to this process:
    --
    --   * if the mapping is ALREADY RESIDENT and usable, the install is
    --     skipped ENTIRELY -- no write, no slot consumed, no `used` change.
    --     Without this a page that was loaded from before it was executed
    --     would have its (hot, demand-installed) DTLB entry rewritten by the
    --     shadow fill and DEMOTED to the speculative `used` = '0' below --
    --     a speculative fill actively evicting the very entry it duplicates.
    --     The dedup scan needed to detect this is the one already run below,
    --     so this costs a gate, not a comparator.
    --
    --   * otherwise it installs NOT-recently-used, i.e. as the next NRU
    --     victim, because a prediction must not be allowed to evict a hot
    --     entry when it turns out wrong.
    --
    -- Tie to '0' for a demand-only port.
    --
    -- NOTE the exact `used` semantics, which are stronger than "LRU-ish": it is
    -- set ONLY on install and cleared only by the all-used sweep or TI -- the
    -- lookup path never touches it, so this array's NRU is really "not recently
    -- INSTALLED" and a speculative entry does NOT promote itself when it is
    -- hit. It stays first-in-line for eviction for its whole life. That is the
    -- intended bound and not a defect: the load the shadow fill exists to serve
    -- is a handful of cycles behind the fetch, far inside the window before any
    -- other install needs a slot, and free slots are still preferred over it
    -- (the NRU scan takes an invalid slot first), so speculative entries
    -- accumulate harmlessly until the array is full and are then given up
    -- before any demand entry. Adding hit-driven promotion would mean a write
    -- into `ram` from the combinational lookup, on the path the 8+16 sizing was
    -- chosen to protect; it is deliberately not done here.
    spec : in    std_logic := '0';
    ti   : in    std_logic; -- 1 => flush all entries
    -- One-cycle pulse: an install ACTUALLY wrote a slot this cycle. Not the
    -- same as tlb_wr, which a skipped speculative install also asserts -- and
    -- the difference is the whole point, so it is exported rather than
    -- reconstructed by the caller. Anti-vacuity instrumentation only (it feeds
    -- the P4 install counters); nothing architectural reads it.
    wrote : out   std_logic := '0'
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

  -- Clocked install (hardware walker) + RESET / MMUCR.TI flush. Either clears
  -- VALID (and the NRU "used" state) on every entry -> a full revocation
  -- (docs/architecture/tlb.md section 6). An install latches the whole entry
  -- atomically from {asidr, pteh_vpn, ptel} into one NRU-chosen slot (no
  -- half-written, matchable entry). NRU replacement: prefer an invalid slot,
  -- else a not-recently-used one, else clear all "used" bits and take slot 0.
  -- The installed entry's flags come straight from PTEL (W7 X6 U5 D4 C3 G2
  -- STALE1 V0); STALE is preserved so software can install an entry already
  -- soft-invalidated.
  process (clk) is

    variable idx     : integer range 0 to entries - 1;
    variable nru_idx : integer range 0 to entries - 1;
    variable dedup   : boolean;
    -- dedup match that is also USABLE (not soft-invalidated). Only a
    -- speculative install consults it; see the `spec` port. `dedup` itself
    -- must keep ignoring `stale`, for the reason given at its use below.
    variable resident  : boolean;
    variable nru_found : boolean;
    variable all_used  : boolean;

  begin

    if rising_edge(clk) then
      -- Default-off every cycle, so `wrote` pulses only on a cycle that
      -- actually writes a slot. It sits AHEAD of the reset arm deliberately:
      -- a reset flush is a revocation, not an install, and must not be
      -- counted as one by the P4 TLBINST instrumentation.
      wrote <= '0';

      -- RESET FLUSH. Revokes every entry, exactly as MMUCR.TI does below.
      --
      -- WHY IT IS NEEDED AT ALL, given `signal ram := (others =>
      -- TLB_ENTRY_RESET)` above. That declaration is a power-on INITIALISER,
      -- not a reset: simulation honours it and FPGA BRAM inference can, but
      -- ASIC synthesis ignores it outright and core/cpu_asic.vhd is a real
      -- target. And nothing anywhere covers an `rst` asserted MID-RUN -- a
      -- warm reset used to leave every valid entry, with its ASID tag and its
      -- permissions, resident and matchable.
      --
      -- That was defence-in-depth rather than a live escape, and it is worth
      -- being exact about why: mmu_reg_reset (core/components_pkg.vhd) zeroes
      -- MMUCR, so MMUCR.AT comes out of reset at 0 and the stale entries are
      -- not consulted until software sets AT=1. But it left the isolation
      -- boundary of docs/architecture/tlb.md resting entirely on software
      -- issuing MMUCR.TI before it next enables translation -- across a reset
      -- which, by definition, may be recovery from a state in which software
      -- was not behaving. The hardware states the invariant itself now.
      --
      -- IT IS STILL A COMPLETE REVOCATION UNDER THE I->D SHADOW FILL. Two
      -- things had to be checked when that landed, because a flush that misses
      -- one entry is worse than no flush -- it looks correct.
      --   * The shadow fill adds NO per-entry state: `spec` only selects the
      --     `used` value and gates the write, and `resident` is a process
      --     VARIABLE recomputed from `ram` every install. Clearing `valid`
      --     still unmatches every slot, since tlb_match above requires
      --     valid = '1' before anything else is consulted. A speculative entry
      --     is revoked by exactly the same two assignments as a demand one.
      --   * A shadow install cannot land in the cycle AFTER the flush and
      --     resurrect a translation. p_tlb_shadow (core/cpu.vhd) clears
      --     shadow_wr under the same `rst`, on the same clock, so dtlb_wr's
      --     shadow term is already '0' when the flush releases -- and during
      --     the reset cycle itself this arm outranks the install anyway (case
      --     25 of sim/tlb_tb.vhd, and see the priority note at the end of this
      --     comment).
      --
      -- AREA. MEASURED, SYNTH_VARIANT=j4, yosys 0.44 (deterministic here -- a
      -- repeated identical run reproduces the counts exactly). Four trees, all
      -- built from REAL COMMITS rather than hand mutations, each synthesised in
      -- a throwaway `git archive` copy: synth/cpu_synth.sh regenerates the J4
      -- overlay into TRACKED decode/*.vhd behind a `|| true` restore, so it
      -- must never be run in a tree whose diff matters.
      --
      --   tree                        assert flush |  ECP5             | ASIC
      --                                            | LUT4   FF  cells  | gates ff
      --   N0  6475932 (base)            no    no   | 9751 3078  15758  | 35579 2696
      --   N1  6475932 + this change     no    yes  | 9670 3078  15638  | 35605 2696
      --   A0  7423e18 (the assertion)   yes   no   |10292 3078  16793  | 35568 2697
      --   A1  this branch's HEAD        yes   yes  | 9956 3078  16154  | 35593 2697
      --
      -- THE RESET FLUSH IS LUT4-NEGATIVE, in both controlled pairs:
      --   N0 -> N1   -81 LUT4   -120 cells   +26 generic gates
      --   A0 -> A1  -336 LUT4   -639 cells   +25 generic gates
      -- It adds 25-26 gates to the generic netlist (0.07%) and hands the
      -- mapper a dedicated clear path in exchange, which it spends well. Flop
      -- count is identical in all four -- no state is added, only that clear
      -- path -- and nothing here touches the combinational LOOKUP process
      -- above, which is where this block's Fmax actually lives. A post-place-
      -- and-route Fmax A/B (scripts/fmax_ab.sh) has NOT been run.
      --
      -- ITS OWN ARM, NOT `rst = '1' or ti = '1'`, AND THE DUPLICATED LOOP IS
      -- THE POINT. That is the comparison the choice actually rests on, and it
      -- is properly controlled: two trees byte-identical except for the arm
      -- structure, both carrying the assertion and the rst port.
      --
      --   THIS FORM (rst's own arm)  9956 LUT4  16154 cells  35593 gates
      --   `rst = '1' or ti = '1'`   10420 LUT4  17064 cells  35570 gates
      --   `ti = '1' or rst = '1'`   10420 LUT4  17064 cells      --
      --
      -- -464 LUT4 for +23 generic gates. With rst in its own leading arm the
      -- mapper can reach the flops' own reset instead of widening a shared
      -- enable term; folded in, it cannot. Operand order buys nothing --
      -- swapping the two terms reproduces the folded numbers to the cell.
      --
      -- TWO WAYS TO GET THIS WRONG, both of which an earlier revision of this
      -- note did get wrong, in the same table:
      --   * NEVER build an area table across trees that differ in ASSERTION
      --     COUNT. p_walk_takeover in core/cpu.vhd is worth +286 to +541 LUT4
      --     (N1->A1 and N0->A0) and one generic flop (2696 -> 2697), because
      --     synth/cpu_synth.sh deletes the $check cell only AFTER mapping.
      --     The earlier table took its baseline from a tree without the
      --     assertion and charged that whole swing to the flush, which
      --     INVERTED THE SIGN of the result: it read +2.0%, not -0.8%.
      --   * NEVER synthesise a "baseline" by DELETING the term under test and
      --     leaving the port behind. That tree -- rst connected, flush term
      --     gone -- measures 9757 LUT4, which is 535 BELOW A0, the honest
      --     no-flush tree, while its generic netlist is IDENTICAL to A0's at
      --     35568 gates. A dangling input changes no logic and moves the LUT
      --     mapping by more than the change under test; the same effect
      --     core/datapath.vhm records at +/-464 LUT4 on J1 from signals merely
      --     tied off. Baselines come from commits.
      --
      -- Priority over the install is intentional and is locked by case 25 of
      -- sim/tlb_tb.vhd: a reset landing on the same edge as a walker install
      -- must leave nothing behind, not resurrect the newest entry.
      if (rst = '1') then

        for k in 0 to entries - 1 loop

          ram(k).valid <= '0';
          ram(k).used  <= '0';

        end loop;

      elsif (ti = '1') then

        for k in 0 to entries - 1 loop

          ram(k).valid <= '0';
          ram(k).used  <= '0';

        end loop;

      elsif (tlb_wr = '1') then
        -- Slot selection for an install. Dedup takes PRIORITY over NRU:
        -- if a valid entry already OVERLAPS this mapping's range under this
        -- ASID (or either side is global), overwrite THAT slot so the
        -- install replaces the mapping in place. This mirrors SH-4 LDTLB
        -- semantics (inherited even though the instruction itself is gone)
        -- and prevents a benign re-install -- e.g. Linux upgrading
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
        all_used := true; resident := false;

        for k in 0 to entries - 1 loop

          if (not dedup and ram(k).valid = '1'
              and ((ram(k).vpn xor pteh_vpn)
                   and (vpn_compare_mask(ram(k).page_mask)
                        and vpn_compare_mask(ptel(11 downto 8))))
                  = (ram(k).vpn'range => '0')
              and (ram(k).global = '1' or ptel(2) = '1'
                    or ram(k).asid_tag = asidr)) then
            idx := k; dedup := true;
            -- A STALE dedup match is still a dedup (the entry occupies the
            -- range and must be overwritten in place), but it is NOT resident
            -- for the purpose of skipping a speculative install: a stale entry
            -- does not translate, so skipping would leave the D side to miss
            -- and walk after all. Refreshing it is exactly what we want.
            if (ram(k).stale = '0') then
              resident := true;
            end if;
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
        -- A speculative install whose mapping is already resident and usable
        -- does nothing at all: no write, no slot consumed, and crucially no
        -- demotion of a hot demand entry to `used` = '0'. See the `spec` port.
        if (not (spec = '1' and resident)) then
          wrote              <= '1';
          ram(idx).valid     <= '1';
          ram(idx).used      <= not spec;
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
    end if;

  end process;

end architecture rtl;
