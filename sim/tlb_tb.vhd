-- ===========================================================================
-- tlb_tb -- standalone testbench for work.tlb (core/tlb.vhd).
--
-- Instantiates the TLB directly (no CPU datapath) and drives the LDTLB
-- install port + MMUCR.TI flush, then checks I-side/D-side lookups.
--
-- Ported from the abandoned two-level-tlb split effort (branch
-- feat/two-level-tlb, commit f22694e, sim/tlb_tb.vhd, 782 lines / 22 cases).
-- That effort split the TLB into small L1 arrays over the 32-entry L2, added
-- a refill FSM, and exposed busy/i_busy/d_busy stall signals. It was
-- abandoned (area +7.7% vs a predicted -25%, 21 broken MMU guards, Fmax
-- regressed with the TLB moved onto the critical path). Master's tlb.vhd
-- has none of that: no L1, no refill FSM, no busy signal at all --
-- translation is purely combinational and installs/flushes are single-cycle.
--
-- Cases dropped from the original 22 because they test machinery this
-- design does not have (L1 hit/miss, the refill FSM, i_busy/d_busy,
-- probe-vs-install arbitration, pend_wr queued drains, LDTLB latency
-- bounds): originals #11 (L1 refill contract), #12 (C3 busy combinational
-- assertion), #13 (confirmed-miss busy clears), #14 (fault-handler loop via
-- busy), #15 (confirmed-miss VA isolation), #18 (install racing an
-- in-progress flush walk -- master's flush has no walk to race), #20 (LDTLB
-- install-to-visible latency bound), #21 (shared comparator array
-- probe/install arbitration race -- master has no shared array), #22
-- (pend_wr-only queued-drain path -- master has no pend_wr).
--
-- Retained cases test TLB BEHAVIOUR, which is identical in spirit between
-- the split and unsplit designs: install, flush, ASID isolation, GLOBAL
-- cross-ASID visibility, STALE suppression, superpages/page-mask handling,
-- exact-VPN install dedup, multi-hit detection on coexisting overlapping
-- entries, and protection checks. Original numbering is kept in the
-- comments below for traceability back to f22694e.
--
-- Coverage note (fix round 1): the original 22 cases never set GLOBAL='1'
-- or the STALE bit at all -- that gap pre-dates this port. Cases 14 and 15
-- close it directly: 14 proves a global entry is visible under an ASID
-- different from its install ASID (the ASID-isolation term of tlb_match,
-- core/tlb.vhd), and 15 proves a STALE entry is suppressed on the lookup
-- path (tlb_match's STALE term) even though the install path does NOT gate
-- on stale (the LDTLB install process has no stale check -- install can
-- freely write a stale-marked entry, e.g. software installing a mapping
-- already soft-invalidated). That install/lookup asymmetry on STALE is
-- exactly the dimension a later install-path change must not regress,
-- hence both directions (install-accepts-stale, lookup-suppresses-stale)
-- are exercised.
--
-- Coverage note (fix round 2): round 1 left the U (user/supervisor)
-- permission bit exercised only via u='0' (case 7's i_prot check depends on
-- u='0' combined with md='1' with X=0), and no case set u='1' or drove
-- md='0' -- so the SMEP and user/kernel-page paths in the I-side and D-side
-- leaf protection predicates (core/tlb.vhd) were untested. That gap is now
-- closed. Cases 19-23 cover it: 19 proves a user page (U=1) accessed from
-- user mode (MD=0) is permitted on both I and D sides; 20 proves a
-- supervisor page (U=0) accessed from user mode (MD=0) faults on both
-- sides -- the u/md combination round 1 left untested; 21 proves SMEP (a
-- kernel-mode instruction fetch of a user page faults) and that SMEP is
-- I-side only (the identical D-side load does not fault); 22 proves S-I7
-- (a global user page is illegal on both sides regardless of MD -- unlike
-- 20/21, this fault does not depend on the mode bit at all); 23 proves the
-- W (writable) check is independent of the U/MD isolation exercised in
-- 19/20 (a store to a non-writable page faults, a load through the same
-- entry does not).
--
-- ptel layout mirrored from the install path at core/tlb.vhd:
--   ptel(31 downto 10) = ppn(31 downto 10)  -- entry.ppn; PA_TAG=ppn(27:13),
--                                              pa12=ppn(12)
--   ptel(11 downto 8)  = page_mask
--   ptel(7)            = w
--   ptel(6)            = x
--   ptel(5)            = u
--   ptel(4)            = d          (unused by this testbench, tied '0')
--   ptel(3)            = c
--   ptel(2)            = global
--   ptel(1)            = stale      (tied '0': fresh installs are not stale)
--   ptel(0)            = unused (V comes from the install control path, not
--                                  from ptel)
-- ===========================================================================

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.cpu2j0_components_pack.all;

entity tlb_tb is
end entity tlb_tb;

architecture beh of tlb_tb is

  signal clk               : std_logic                     := '0';
  signal i_va,        d_va : std_logic_vector(31 downto 0) := (others => '0');
  signal asid              : std_logic_vector(15 downto 0) := (others => '0');
  signal md                : std_logic                     := '0';
  signal at                : std_logic                     := '0';
  signal d_we              : std_logic                     := '0';
  signal tlb_wr            : std_logic                     := '0';
  signal ti                : std_logic                     := '0';
  -- Install-path inputs (LDTLB). Widths taken from the entity: pteh_vpn is
  -- 31 downto 12, ptel is 31 downto 0, asidr is 15 downto 0.
  signal pteh_vpn                 : std_logic_vector(31 downto 12) := (others => '0');
  signal ptel                     : std_logic_vector(31 downto 0)  := (others => '0');
  signal asidr                    : std_logic_vector(15 downto 0)  := (others => '0');
  signal i_hit                    : std_logic;
  signal i_prot                   : std_logic;
  signal i_multihit               : std_logic;
  signal d_hit                    : std_logic;
  signal d_prot                   : std_logic;
  signal d_multihit               : std_logic;
  signal i_pa_tag,    d_pa_tag    : std_logic_vector(14 downto 0);
  signal i_page_mask, d_page_mask : std_logic_vector(3 downto 0);
  signal i_c                      : std_logic;
  signal d_c                      : std_logic;
  signal i_pa12                   : std_logic;
  signal d_pa12                   : std_logic;
  signal done                     : boolean                        := false;

begin

  -- Stop the clock once the stimulus process is done, else the simulation
  -- (which has no --stop-time) would run forever on the passing path (only
  -- the FAIL path halts on its own, via `severity failure`).
  clk <= not clk after 5 ns when not done else
         clk;

  dut : entity work.tlb
    port map (
      clk         => clk,
      i_va        => i_va,
      i_pa_tag    => i_pa_tag,
      i_pa12      => i_pa12,
      i_page_mask => i_page_mask,
      i_c         => i_c,
      i_hit       => i_hit,
      i_prot      => i_prot,
      i_multihit  => i_multihit,
      d_va        => d_va,
      d_we        => d_we,
      d_pa_tag    => d_pa_tag,
      d_pa12      => d_pa12,
      d_page_mask => d_page_mask,
      d_c         => d_c,
      d_hit       => d_hit,
      d_prot      => d_prot,
      d_multihit  => d_multihit,
      asid        => asid,
      md          => md,
      at          => at,
      tlb_wr      => tlb_wr,
      pteh_vpn    => pteh_vpn,
      ptel        => ptel,
      asidr       => asidr,
      ti          => ti
    );

  stim : process is

    -- A process variable, NOT a signal: `check` and the final pass/fail
    -- report run in the same process with no intervening `wait` between the
    -- last check and the final `if fail then`, so a signal assignment
    -- (`fail <= true`) would not have taken effect yet when read back --
    -- the very last check in the suite could fail and still be reported as
    -- PASSED. A variable update is immediate, so this is correct regardless
    -- of which check fails.
    variable fail : boolean := false;

    procedure check (
      cond : boolean;
      msg  : string
    ) is
    begin

      if (not cond) then
        report "FAIL: " & msg
          severity error;
        fail := true;
      end if;

    end procedure check;

    -- One install = one LDTLB. ptel packs ppn/page_mask/permissions exactly
    -- as the install path in core/tlb.vhd unpacks them (see the header
    -- comment above). vpn and ppn are both std_logic_vector(31 downto 12)
    -- so they line up 1:1 with pteh_vpn / a VA's upper bits.
    -- master's install is a single clocked process with no busy/stall
    -- signal: the entry is committed on the rising edge tlb_wr is sampled,
    -- and is visible to the (purely combinational) lookups immediately
    -- after.

    procedure install (
      vpn       : std_logic_vector(31 downto 12);
      asid_tag  : std_logic_vector(15 downto 0);
      ppn       : std_logic_vector(31 downto 12);
      page_mask : std_logic_vector(3 downto 0);
      w,
      x,
      u,
      c,
      g         : std_logic
    ) is
    begin

      pteh_vpn <= vpn;
      asidr    <= asid_tag;
      ptel     <= ppn & page_mask & w & x & u & '0' & c & g & '0' & '0';
      tlb_wr   <= '1';
      wait until rising_edge(clk);
      tlb_wr   <= '0';
      wait for 1 ns;

    end procedure install;

    procedure flush_all is
    begin

      ti <= '1';
      wait until rising_edge(clk);
      ti <= '0';
      wait for 1 ns;

    end procedure flush_all;

  begin

    at <= '1';
    md <= '1';
    wait until rising_edge(clk);

    -- 1. miss on an empty TLB
    i_va <= x"00001000";
    wait for 1 ns;
    check(i_hit = '0', "empty TLB must miss");

    -- 2. install a 4K page and hit it.
    install(vpn       => x"00001", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    i_va <= x"00001000";
    wait for 1 ns;
    check(i_hit = '1', "installed 4K page must hit");
    check(i_multihit = '0', "single install must not report multi-hit");

    -- 3. ASID isolation: a non-global entry must miss under a different ASID.
    asid <= x"0001";
    wait for 1 ns;
    check(i_hit = '0', "non-global entry must miss on ASID mismatch");
    asid <= x"0000";
    wait for 1 ns;
    check(i_hit = '1', "entry must hit again under its own ASID");

    -- 4. superpage: a larger page must match VAs differing in the low VPN
    -- bits, and still miss outside its (masked) range. page_mask="0011"
    -- (vpn_compare_mask -> n=6) ignores VPN bits 0..5, i.e. a 256KB page
    -- (2**(12+6)) whose covered VA range here is [0x00000000, 0x0003FFFF]
    -- (the installed entry's vpn=0x00010 has all bits from 6 up equal 0).
    -- Explicit precondition (don't rely on case 3 having restored this):
    asid <= x"0000";
    wait for 1 ns;
    flush_all;
    install(vpn       => x"00010", asid_tag => x"0000", ppn => x"00020",
            page_mask => "0011", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    i_va <= x"00010000";
    wait for 1 ns;
    check(i_hit = '1', "superpage base VA must hit");
    i_va <= x"00013000";
    wait for 1 ns;
    check(i_hit = '1', "VA inside the superpage must hit (masked VPN compare)");
    -- 0x00040000 is the first VA whose VPN has bit 6 set (vpn=0x40), which
    -- differs from the installed entry's masked (all-zero) high bits -- the
    -- first VA genuinely outside the installed 256KB range.
    i_va <= x"00040000";
    wait for 1 ns;
    check(i_hit = '0', "VA outside the (masked) superpage range must miss");

    -- 5. S-I5, C2 fix (task 3, INVERTED from the original "coexist" case):
    -- install-time overlap now PREVENTS the multi-hit rather than leaving it
    -- to be caught (fatally) at lookup. Install a 256KB superpage covering
    -- [0x0,0x3FFFF], then a 4K page whose VA falls inside that range but
    -- whose raw vpn differs. Task 3's masked overlap compare (core/tlb.vhd)
    -- must detect that the new 4K install overlaps the resident superpage
    -- under the coarser (superpage) mask and evict it, so only the narrower
    -- mapping survives.
    flush_all;
    install(vpn       => x"00010", asid_tag => x"0000", ppn => x"00020",
            page_mask => "0011", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    install(vpn       => x"00011", asid_tag => x"0000", ppn => x"00030",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    -- The narrower (2nd-installed) entry's own VA must now be a CLEAN hit:
    -- the overlapping superpage was evicted at install, not left to coexist.
    i_va <= x"00011000";
    wait for 1 ns;
    check(i_hit = '1', "overlapping VA must hit the narrower, just-installed mapping");
    check(i_multihit = '0',
          "install-time overlap detection must evict the overlapping superpage, so this is a clean hit, not a multi-hit");
    -- The superpage that covered a WIDER range (e.g. 0x00010000, outside the
    -- narrower entry) is now gone -- it was evicted, so that VA misses.
    i_va <= x"00010000";
    wait for 1 ns;
    check(i_hit = '0',
          "the evicted superpage's range outside the narrower entry must now miss (it was replaced, not merely deprioritized)");

    -- 6. Exact-VPN dedup: re-installing the SAME vpn/asid replaces the
    -- existing entry in place (core/tlb.vhd :234-238) rather than adding a
    -- second one -- this is the dedup case master's install path actually
    -- implements.
    flush_all;
    install(vpn       => x"00001", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    install(vpn       => x"00001", asid_tag => x"0000", ppn => x"00007",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    i_va <= x"00001000";
    wait for 1 ns;
    check(i_hit = '1', "re-install of the same VPN/ASID must still hit");
    check(i_multihit = '0', "re-install of the same VPN/ASID must dedup, not coexist as two entries");
    check(i_pa_tag = "000000000000011",
          "re-install of the same VPN/ASID must replace the entry (surviving PA must be the 2nd install's)");

    -- 7. protection: a non-executable page fetched must report i_prot.
    flush_all;
    install(vpn       => x"00001", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '1', x => '0', u => '0', c => '1',
            g         => '0');
    i_va <= x"00001000";
    wait for 1 ns;
    check(i_hit = '1', "X=0 page must still report a hit");
    check(i_prot = '1', "X=0 page must raise i_prot on fetch");

    -- 8. D-side install-and-hit: mirrors case 2 but through d_va/d_hit.
    -- The I-side and D-side are two independent combinational processes
    -- sharing only the tlb_match predicate -- their protection logic
    -- differs (D-side checks the store case and has no X check at all), so
    -- the D-side must be driven and checked directly, not inferred from the
    -- I-side passing.
    flush_all;
    install(vpn       => x"00001", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    d_we <= '0';
    d_va <= x"00001000";
    wait for 1 ns;
    check(d_hit = '1', "installed 4K page must hit on D-side");
    check(d_multihit = '0', "single install must not report D-side multi-hit");

    -- 9. D-side superpage: same range arithmetic as case 4, through d_va.
    flush_all;
    install(vpn       => x"00010", asid_tag => x"0000", ppn => x"00020",
            page_mask => "0011", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    d_va <= x"00010000";
    wait for 1 ns;
    check(d_hit = '1', "D-side superpage base VA must hit");
    d_va <= x"00013000";
    wait for 1 ns;
    check(d_hit = '1',
          "VA inside the D-side superpage must hit (masked VPN compare)");
    -- Same corrected boundary as case 4: 0x00040000 is the first VA whose
    -- VPN has bit 6 set, genuinely outside the installed 256KB range.
    d_va <= x"00040000";
    wait for 1 ns;
    check(d_hit = '0', "VA outside the (masked) D-side superpage range must miss");

    -- 10. D-side write protection: a store to a non-writable (w=0) page must
    -- raise d_prot. This is the D-side's distinctive check (`d_we='1' and
    -- entry.w='0'`) and has no I-side equivalent, so nothing else in this
    -- testbench covers it.
    flush_all;
    install(vpn       => x"00001", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '0', x => '1', u => '0', c => '1',
            g         => '0');
    d_we <= '1';
    d_va <= x"00001000";
    wait for 1 ns;
    check(d_hit = '1', "w=0 page must still report a D-side hit");
    check(d_prot = '1', "store to a w=0 page must raise d_prot");
    d_we <= '0';

    -- 11 (was #16, INVERTED for task 3): mirror image of case 5 -- narrow
    -- entries installed FIRST, then a wider superpage installed on top,
    -- rather than case 5's wide-then-narrow order. Install two
    -- non-overlapping 4K pages: one (vpn=0x00000) inside the 256KB range
    -- the superpage will cover, one (vpn=0x00040, VA=0x00040000) genuinely
    -- OUTSIDE it (the same boundary established in case 4: 0x00040000 is
    -- the first VA whose VPN has bit 6 set). Then install the 256KB
    -- superpage. It overlaps only the in-range 4K entry, which the masked
    -- install-time overlap check must detect and evict -- leaving a clean
    -- single hit there -- while the out-of-range entry, which never
    -- overlapped anything, must be left completely untouched.
    flush_all;
    install(vpn       => x"00000", asid_tag => x"0000", ppn => x"00001",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    install(vpn       => x"00040", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    install(vpn       => x"00000", asid_tag => x"0000", ppn => x"00020",
            page_mask => "0011", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    -- The in-range 4K entry's overlap must have been evicted at install:
    -- this VA is now a clean hit on the surviving superpage, not a
    -- multi-hit.
    i_va <= x"00001000";
    wait for 1 ns;
    check(i_hit = '1', "VA formerly covered by the evicted 4K entry must still hit (now via the superpage)");
    check(i_multihit = '0',
          "install-time overlap detection must have evicted the overlapping 4K entry, so this is a clean hit");
    check(i_pa_tag = "000000000010000",
          "the surviving mapping at this VA must be the superpage (3rd-installed) entry's PA");
    -- The out-of-range 4K entry never overlapped anything and must be
    -- completely unaffected: still resident, still a clean single hit.
    i_va <= x"00040000";
    wait for 1 ns;
    check(i_hit = '1', "the non-overlapping 4K entry outside the superpage's range must be untouched and still hit");
    check(i_multihit = '0', "the untouched, non-overlapping entry must not multi-hit");
    check(i_pa_tag = "000000000000001",
          "the untouched entry's PA must still be its own (2nd-installed) mapping");

    -- 12 (was #17): a flush must invalidate every entry, not just some of
    -- them. Install two entries at different VPNs, confirm both hit, flush,
    -- then confirm both now miss. core/tlb.vhd's flush clears VALID on all
    -- 32 entries in a single clocked pass (:210-215) -- no walk, so no
    -- multi-cycle wait is needed before checking.
    flush_all;
    install(vpn       => x"00001", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    install(vpn       => x"00005", asid_tag => x"0000", ppn => x"00003",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    i_va <= x"00001000";
    wait for 1 ns;
    check(i_hit = '1', "case 12 precondition: first installed VA must hit before the flush");
    i_va <= x"00005000";
    wait for 1 ns;
    check(i_hit = '1', "case 12 precondition: second installed VA must hit before the flush");
    flush_all;
    i_va <= x"00001000";
    wait for 1 ns;
    check(i_hit = '0', "case 12: first installed VA must miss after the flush");
    i_va <= x"00005000";
    wait for 1 ns;
    check(i_hit = '0', "case 12: second installed VA must miss after the flush");

    -- 13 (was #19): a flush must invalidate within a single cycle (no
    -- 32-cycle walk). Since master's flush is a plain single-cycle clocked
    -- process (unlike the split design's serialised walk), this collapses
    -- to: the entry misses on the very next lookup after ti is deasserted,
    -- with no bounded-wait loop needed at all (there is no busy signal to
    -- poll here in the first place).
    install(vpn       => x"0000a", asid_tag => x"0000", ppn => x"0000b",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    i_va <= x"0000A000";
    wait for 1 ns;
    check(i_hit = '1', "case 13 precondition: installed VA must hit before the flush");

    ti   <= '1';
    wait until rising_edge(clk);
    ti   <= '0';
    wait for 1 ns;
    i_va <= x"0000A000";
    wait for 1 ns;
    check(i_hit = '0', "case 13: flush must invalidate the entry within a single cycle");

    -- 14 (new, fix round 1): GLOBAL cross-ASID visibility. A global entry
    -- (ptel bit 2, `g` argument here) must be visible to a lookup under an
    -- ASID different from the one it was installed with, per the ASID
    -- isolation term of tlb_match in core/tlb.vhd (`entry.global = '1' or
    -- entry.asid_tag = asid`). Contrast directly against case 3, which
    -- already proves a NON-global entry misses under a different ASID --
    -- this case proves the opposite for g='1', so the ASID half of the
    -- predicate is exercised on both sides of the OR.
    flush_all;
    install(vpn       => x"00002", asid_tag => x"0007", ppn => x"00004",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '1');
    i_va <= x"00002000";
    asid <= x"0007";
    wait for 1 ns;
    check(i_hit = '1', "case 14 precondition: global entry must hit under its own install ASID");
    asid <= x"00AB";
    wait for 1 ns;
    check(i_hit = '1', "case 14: global entry must hit under a DIFFERENT ASID than it was installed with");
    check(i_pa_tag = "000000000000010",
          "case 14: global entry's PA must be correct under the different ASID, not a miss-masked stale value");
    asid <= x"0000";
    wait for 1 ns;

    -- 15 (new, fix round 1): STALE suppression on the lookup path. ptel
    -- bit 1 (tied '0' in every install above) is written straight through
    -- to entry.stale in the LDTLB install process (core/tlb.vhd) and gates
    -- both lookup processes directly via the STALE term of tlb_match
    -- (`entry.stale = '0'`) -- install itself does not gate on stale at
    -- all, so a stale entry can be installed exactly like any other.
    -- Install one directly with ptel(1)='1' (bypassing the
    -- `install` procedure, which always drives '0' there) and confirm the
    -- lookup path suppresses it: a probe of its VA must miss outright, not
    -- merely lose priority to some other entry.
    flush_all;
    pteh_vpn <= x"00003";
    asidr    <= x"0000";
    -- ppn=x"00005", page_mask="0000", w='1', x='1', u='0', d='0', c='1',
    -- g='0', stale='1', (unused)='0'.
    ptel   <= x"00005" & "0000" & '1' & '1' & '0' & '0' & '1' & '0' & '1' & '0';
    tlb_wr <= '1';
    wait until rising_edge(clk);
    tlb_wr <= '0';
    wait for 1 ns;
    i_va   <= x"00003000";
    wait for 1 ns;
    check(i_hit = '0', "case 15: a STALE entry must be suppressed on the lookup path (miss, not a low-priority hit)");
    check(i_multihit = '0', "case 15: a suppressed stale entry must not register as any kind of match");

    -- 16 (new, task 3): masked install-time overlap. Install a 1 MB
    -- superpage (page_mask="0100" -> vpn_compare_mask n=8, ignores VPN bits
    -- 0..7, i.e. VA bits 12..19 -- see core/components_pkg.vhd:107/548 and
    -- the "PageMask helpers" comment: pm=4 => 2**(12+8)=1MB) covering VA
    -- range [0x00000000, 0x000FFFFF] (installed vpn=0x00000, all bits from
    -- 8 up are zero). Then install a 4K page whose VA (0x00005000) falls
    -- INSIDE that range but whose raw vpn (0x00005) differs from the
    -- superpage's vpn (0x00000) -- master's OLD exact-VPN dedup could not
    -- see this as the same range, so both entries stayed valid and a lookup
    -- of 0x00005000 multi-hit (S-I5 fatal). Task 3's masked overlap compare
    -- must detect this at install time and evict the superpage, replacing
    -- it with the narrower mapping: the lookup must be a clean single hit.
    flush_all;
    install(vpn       => x"00000", asid_tag => x"0000", ppn => x"00050",
            page_mask => "0100", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    install(vpn       => x"00005", asid_tag => x"0000", ppn => x"00060",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    i_va <= x"00005000";
    wait for 1 ns;
    check(i_hit = '1', "case 16: VA inside the evicted superpage's range, covered by the new 4K page, must hit");
    check(i_multihit = '0',
          "case 16: install-time overlap detection must evict the overlapping superpage, not leave both entries coexisting as a multi-hit");
    check(i_pa_tag = "000000000110000",
          "case 16: the surviving mapping must be the narrower (2nd-installed) entry's PA");

    -- 17 (new, fix round 1): install-side overlap eviction of a STALE
    -- resident entry. The install dedup scan (core/tlb.vhd) deliberately
    -- does NOT gate on ram(k).stale, unlike the lookup path's tlb_match
    -- (which does) -- an install must be able to see and evict a resident
    -- mapping that is stale, or it could install something overlapping a
    -- range it can no longer perceive. This is the subtlest part of task 3
    -- and was previously UNTESTED: case 15 only proves the lookup-side half
    -- (a stale entry never hits); this proves the install-side half (a
    -- stale entry IS still considered -- and evicted -- by the overlap
    -- scan).
    --
    -- The trap: a STALE resident entry never hits at lookup regardless of
    -- whether it was evicted or left coexisting (tlb_match suppresses it
    -- either way), so a naive VA-hit/miss check cannot distinguish "evicted"
    -- from "silently coexisting forever, gating wrongly excluded it". The
    -- only externally observable difference is TLB CAPACITY: a coexisting
    -- dead stale entry permanently occupies one of the 32 slots. This case
    -- exploits that: a canary entry is installed into slot 0 first, then the
    -- stale entry + its overlapping narrow install, then exactly enough
    -- filler entries to fill the TLB to capacity IF (and only if) the stale
    -- entry was evicted (freeing its slot). If the stale entry was instead
    -- left resident (the regression this case exists to catch), the TLB is
    -- one slot short, the last filler install overflows NRU's "all
    -- valid+used -> clear used bits, take slot 0" recycle path, and that
    -- recycle unconditionally overwrites slot 0 -- silently evicting the
    -- canary. Checking the canary's continued presence at the end is the
    -- discriminator.
    flush_all;

    -- Canary: must land in slot 0 (first install after the flush, on an
    -- all-invalid array). vpn=0xF0 is deliberately OUTSIDE every range used
    -- below (the stale superpage's 0x00-0x3F, the narrow install's 0x11,
    -- and the fillers' 0x100-0x11D) -- it must never itself be a party to
    -- any overlap eviction in this case, or its disappearance would prove
    -- nothing about the stale asymmetry being tested.
    install(vpn       => x"000F0", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');

    -- STALE resident superpage (256KB, covers VA [0x0,0x3FFFF] -- same
    -- range arithmetic as cases 4/5/16). Installed directly (bypassing the
    -- `install` procedure, which always drives ptel(1)='0'), same technique
    -- as case 15. Lands in slot 1 (next invalid slot after the canary).
    pteh_vpn <= x"00010";
    asidr    <= x"0000";
    -- ppn=x"00020", page_mask="0011", w='1', x='1', u='0', d='0', c='1',
    -- g='0', stale='1', (unused)='0'.
    ptel   <= x"00020" & "0011" & '1' & '1' & '0' & '0' & '1' & '0' & '1' & '0';
    tlb_wr <= '1';
    wait until rising_edge(clk);
    tlb_wr <= '0';
    wait for 1 ns;

    -- Overlapping narrow install: VA 0x00011000 falls inside the stale
    -- superpage's range but has a different raw vpn. If the install scan
    -- correctly considers the stale entry, this evicts it in place (slot 1
    -- freed for reuse -- overwritten, in fact, by this very install). If the
    -- install scan wrongly excludes stale entries, this instead lands via
    -- plain NRU in slot 2, leaving the stale entry stranded (still valid,
    -- still occupying slot 1) forever.
    install(vpn       => x"00011", asid_tag => x"0000", ppn => x"00099",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');

    -- Fill the TLB to exactly 32 total valid entries under the CORRECT
    -- (evicted) hypothesis: 2 already resident (canary, narrow) + 30 more =
    -- 32, landing in slots 2..31 with no NRU overflow at all. Under the
    -- BUGGY (not-evicted) hypothesis there are 3 resident entries (canary,
    -- dead stale, narrow) + 30 more = 33 needed in 32 slots: the last of
    -- these 30 filler installs overflows and clobbers slot 0 (the canary).
    for i in 0 to 29 loop

      install(vpn       => std_logic_vector(to_unsigned(16#00100# + i, 20)),
              asid_tag  => x"0000",
              ppn       => std_logic_vector(to_unsigned(16#00200# + i, 20)),
              page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
              g         => '0');

    end loop;

    -- The discriminator: the canary (slot 0) must still be there. If the
    -- stale entry was wrongly left resident (install gated on stale), the
    -- capacity shortfall above forces its silent eviction here.
    i_va <= x"000F0000";
    wait for 1 ns;
    check(i_hit = '1',
          "case 17: canary (slot 0) must still hit -- if this misses, the stale resident entry was NOT evicted at install (the stale asymmetry is broken) and starved the TLB of a slot");
    check(i_pa_tag = "000000000000001",
          "case 17: canary's PA must be unchanged -- a different PA here means slot 0 was silently overwritten by NRU overflow");

    -- The overlapping narrow install itself must also be a clean single
    -- hit, exactly like case 16.
    i_va <= x"00011000";
    wait for 1 ns;
    check(i_hit = '1', "case 17: the overlapping narrow install must hit");
    check(i_multihit = '0',
          "case 17: the overlapping narrow install must be a clean hit, not a multi-hit against the (should-be-evicted) stale superpage");
    check(i_pa_tag = "000000001001100",
          "case 17: the surviving mapping at this VA must be the narrow (overlapping) install's own PA");

    -- 18 (new, fix round 1): the DOCUMENTED, BOUNDED residual multi-hit gap
    -- (docs/architecture/tlb.md S-I5, sim/tests/mmumultihit.S header): the
    -- install dedup scan evicts only the FIRST resident entry it finds
    -- overlapping a new install (`not dedup` short-circuits further matches
    -- in the same scan) -- it does not sweep and evict every overlapping
    -- entry. So if TWO pre-existing, mutually non-overlapping entries each
    -- independently overlap one new (wider) install, only the first-scanned
    -- one is evicted; the second survives and now genuinely overlaps the
    -- new entry, reaching a real multi-hit. This is current, INTENTIONAL,
    -- bounded behaviour (not a defect to fix here) -- this case asserts it
    -- so the gap stays documented-AND-tested rather than documented-only.
    flush_all;
    install(vpn       => x"00050", asid_tag => x"0000", ppn => x"00060",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    install(vpn       => x"00051", asid_tag => x"0000", ppn => x"00061",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    -- Wide superpage (256KB, covers VPN 0x40..0x7F i.e. VA
    -- [0x00040000,0x0007FFFF] -- vpn=0x50 masked to its 64-VPN-aligned base
    -- is 0x40). Overlaps BOTH prior entries (0x50 and 0x51 both fall in
    -- 0x40..0x7F). Dedup finds and evicts only the FIRST-scanned resident
    -- match (vpn=0x00050, installed first -> earlier slot).
    install(vpn       => x"00050", asid_tag => x"0000", ppn => x"00070",
            page_mask => "0011", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    -- The evicted entry's own VA is now a clean single hit (superpage only).
    i_va <= x"00050000";
    wait for 1 ns;
    check(i_hit = '1', "case 18: VA of the evicted (first-scanned) entry must still hit, via the surviving superpage");
    check(i_multihit = '0', "case 18: the evicted entry's VA must be a clean hit, not a multi-hit");
    -- The SECOND overlapping entry was never scanned for dedup (short-
    -- circuited) and survives untouched, now genuinely double-matched by
    -- both itself and the superpage: a real, current, bounded multi-hit.
    i_va <= x"00051000";
    wait for 1 ns;
    check(i_hit = '1', "case 18: VA covered by both the surviving 2nd entry and the superpage must still hit");
    check(i_multihit = '1',
          "case 18: two independently-overlapping entries against one new install is the documented residual gap -- dedup only evicts the first match it scans, so this must still genuinely multi-hit");

    -- 19 (fix round 2, closes the u/md coverage gap documented in the file
    -- header): a user page (U=1) accessed from user mode (MD=0) is
    -- permitted on both sides -- no case before this one ever drove
    -- md='0' or installed u='1'. asid_tag distinguishes this entry from any
    -- residue left by earlier cases.
    flush_all;
    asid <= x"0002";
    install(vpn       => x"00060", asid_tag => x"0002", ppn => x"00090",
            page_mask => "0000", w => '1', x => '1', u => '1', c => '1',
            g         => '0');
    md   <= '0';
    i_va <= x"00060000";
    d_va <= x"00060000";
    d_we <= '0';
    wait for 1 ns;
    check(i_hit = '1', "case 19: user page fetched from user mode must hit");
    check(i_prot = '0', "case 19: user page fetched from user mode must NOT fault (I-side leaf protection predicate, core/tlb.vhd)");
    check(d_hit = '1', "case 19: user page loaded from user mode must hit");
    check(d_prot = '0', "case 19: user page loaded from user mode must NOT fault (D-side leaf protection predicate, core/tlb.vhd)");

    -- 20: a supervisor page (U=0) accessed from user mode (MD=0) faults on
    -- both sides -- this is the u/md combination the header called out as
    -- untested (every earlier case only ever drove md='1').
    flush_all;
    install(vpn       => x"00061", asid_tag => x"0002", ppn => x"00091",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g         => '0');
    md   <= '0';
    i_va <= x"00061000";
    d_va <= x"00061000";
    d_we <= '0';
    wait for 1 ns;
    check(i_hit = '1', "case 20: supervisor page fetched from user mode must still report a hit");
    check(i_prot = '1', "case 20: supervisor page fetched from user mode must fault (I-side leaf protection predicate, core/tlb.vhd)");
    check(d_hit = '1', "case 20: supervisor page loaded from user mode must still report a hit");
    check(d_prot = '1', "case 20: supervisor page loaded from user mode must fault (D-side leaf protection predicate, core/tlb.vhd)");

    -- 21 (mmusmep): SMEP -- a kernel-mode (MD=1) instruction fetch of a
    -- user page (U=1) faults on the I side (the SMEP term of the I-side
    -- leaf protection predicate, core/tlb.vhd), even though the same entry
    -- is perfectly executable from user mode (case 19). The D side has no
    -- SMEP term at all: confirm a load through the identical entry does NOT
    -- fault while in kernel mode.
    flush_all;
    install(vpn       => x"00062", asid_tag => x"0002", ppn => x"00092",
            page_mask => "0000", w => '1', x => '1', u => '1', c => '1',
            g         => '0');
    md   <= '1';
    i_va <= x"00062000";
    d_va <= x"00062000";
    d_we <= '0';
    wait for 1 ns;
    check(i_hit = '1', "case 21: SMEP precondition: kernel fetch of user page must still report a hit");
    check(i_prot = '1', "case 21: SMEP -- kernel fetch of a user page must fault (SMEP term of the I-side leaf protection predicate, core/tlb.vhd)");
    check(d_hit = '1', "case 21: D-side precondition: kernel load of the same user page must still report a hit");
    check(d_prot = '0', "case 21: SMEP is I-side only -- a kernel-mode LOAD of the same user page must NOT fault (the D-side leaf protection predicate, core/tlb.vhd, has no SMEP term)");

    -- 22 (mmuglobal, S-I7): a global user page (GLOBAL=1, U=1) is illegal
    -- on both sides regardless of MD -- unlike cases 20/21, this fault does
    -- not depend on the mode bit at all. Check it under both md='0' and
    -- md='1' against the SAME installed entry to prove MD is irrelevant to
    -- this rule. NOTE: the md='1' leg of the I-side check below is
    -- confounded -- for a global user page with md='1', the SMEP term
    -- (u='1' and md='1') also fires, so that leg alone does not
    -- independently prove S-I7 on the I side. The md='0' leg is the
    -- load-bearing isolator for S-I7 on the I side (SMEP cannot fire at
    -- md='0'); the D-side check has no SMEP term at all, so both of its
    -- legs (md='0' and md='1') are unconfounded proof of S-I7.
    flush_all;
    install(vpn       => x"00063", asid_tag => x"0002", ppn => x"00093",
            page_mask => "0000", w => '1', x => '1', u => '1', c => '1',
            g         => '1');
    md   <= '0';
    i_va <= x"00063000";
    d_va <= x"00063000";
    d_we <= '0';
    wait for 1 ns;
    check(i_hit = '1', "case 22: S-I7 precondition (md=0): global user page fetch must still report a hit");
    check(i_prot = '1', "case 22: S-I7 (md=0) -- a global user page must fault on fetch regardless of mode (S-I7 term of the I-side leaf protection predicate, core/tlb.vhd)");
    check(d_hit = '1', "case 22: S-I7 precondition (md=0): global user page load must still report a hit");
    check(d_prot = '1', "case 22: S-I7 (md=0) -- a global user page must fault on load regardless of mode (S-I7 term of the D-side leaf protection predicate, core/tlb.vhd)");
    md   <= '1';
    wait for 1 ns;
    check(i_prot = '1', "case 22: S-I7 (md=1) -- a global user page must fault on fetch regardless of mode (I-side leaf protection predicate, core/tlb.vhd; NOTE this leg is confounded with SMEP -- see comment above)");
    check(d_prot = '1', "case 22: S-I7 (md=1) -- a global user page must fault on load regardless of mode (S-I7 term of the D-side leaf protection predicate, core/tlb.vhd; unconfounded, D-side has no SMEP term)");

    -- 23: a store (d_we='1') to a non-writable (W=0) user page faults, but
    -- a load (d_we='0') through the SAME entry does not -- the W check is
    -- independent of the U/MD isolation check exercised in cases 19/20.
    flush_all;
    install(vpn       => x"00064", asid_tag => x"0002", ppn => x"00094",
            page_mask => "0000", w => '0', x => '1', u => '1', c => '1',
            g         => '0');
    md   <= '0';
    d_va <= x"00064000";
    d_we <= '1';
    wait for 1 ns;
    check(d_hit = '1', "case 23: store precondition: non-writable page must still report a hit");
    check(d_prot = '1', "case 23: a STORE to a non-writable page must fault (W term of the D-side leaf protection predicate, core/tlb.vhd)");
    d_we <= '0';
    wait for 1 ns;
    check(d_hit = '1', "case 23: load precondition: non-writable page must still report a hit");
    check(d_prot = '0', "case 23: a LOAD from the same non-writable page must NOT fault (D-side leaf protection predicate, core/tlb.vhd)");

    if (fail) then
      report "tlb_tb FAILED"
        severity failure;
    else
      report "tlb_tb PASSED"
        severity note;
    end if;

    done <= true;
    wait;

  end process stim;

end architecture beh;
