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
-- different from its install ASID (core/tlb.vhd:105/162), and 15 proves a
-- STALE entry is suppressed on the lookup path (:103/160) even though the
-- install path does NOT gate on stale (:232-281 has no stale check --
-- install can freely write a stale-marked entry, e.g. software installing
-- a mapping already soft-invalidated). That install/lookup asymmetry on
-- STALE is exactly the dimension a later install-path change must not
-- regress, hence both directions (install-accepts-stale,
-- lookup-suppresses-stale) are exercised. Still NOT covered here: the U
-- (user/supervisor) permission bit is only exercised via u='0' in every
-- case above (case 7's i_prot check depends on u='0' combined with md='1'
-- with X=0 -- see core/tlb.vhd:114-116); no case sets u='1' or drives
-- md='0', so the SMEP and user/kernel-page paths at :114-116/171 are
-- untested. That gap is not closed by this round and should not be assumed
-- covered.
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
  use work.cpu2j0_components_pack.all;

entity tlb_tb is
end entity tlb_tb;

architecture beh of tlb_tb is

  signal clk : std_logic := '0';
  signal i_va, d_va : std_logic_vector(31 downto 0) := (others => '0');
  signal asid : std_logic_vector(15 downto 0) := (others => '0');
  signal md, at, d_we, tlb_wr, ti : std_logic := '0';
  -- Install-path inputs (LDTLB). Widths taken from the entity: pteh_vpn is
  -- 31 downto 12, ptel is 31 downto 0, asidr is 15 downto 0.
  signal pteh_vpn : std_logic_vector(31 downto 12) := (others => '0');
  signal ptel     : std_logic_vector(31 downto 0)  := (others => '0');
  signal asidr    : std_logic_vector(15 downto 0)  := (others => '0');
  signal i_hit, i_prot, i_multihit : std_logic;
  signal d_hit, d_prot, d_multihit : std_logic;
  signal i_pa_tag, d_pa_tag : std_logic_vector(14 downto 0);
  signal i_page_mask, d_page_mask : std_logic_vector(3 downto 0);
  signal i_c, d_c, i_pa12, d_pa12 : std_logic;
  signal done : boolean := false;

begin

  -- Stop the clock once the stimulus process is done, else the simulation
  -- (which has no --stop-time) would run forever on the passing path (only
  -- the FAIL path halts on its own, via `severity failure`).
  clk <= not clk after 5 ns when not done else clk;

  dut : entity work.tlb
    port map (
      clk => clk,
      i_va => i_va, i_pa_tag => i_pa_tag, i_pa12 => i_pa12,
      i_page_mask => i_page_mask, i_c => i_c,
      i_hit => i_hit, i_prot => i_prot, i_multihit => i_multihit,
      d_va => d_va, d_we => d_we, d_pa_tag => d_pa_tag, d_pa12 => d_pa12,
      d_page_mask => d_page_mask, d_c => d_c,
      d_hit => d_hit, d_prot => d_prot, d_multihit => d_multihit,
      asid => asid, md => md, at => at,
      tlb_wr => tlb_wr, pteh_vpn => pteh_vpn, ptel => ptel,
      asidr => asidr, ti => ti);

  stim : process

    -- A process variable, NOT a signal: `check` and the final pass/fail
    -- report run in the same process with no intervening `wait` between the
    -- last check and the final `if fail then`, so a signal assignment
    -- (`fail <= true`) would not have taken effect yet when read back --
    -- the very last check in the suite could fail and still be reported as
    -- PASSED. A variable update is immediate, so this is correct regardless
    -- of which check fails.
    variable fail : boolean := false;

    procedure check (cond : boolean; msg : string) is
    begin
      if not cond then
        report "FAIL: " & msg severity error;
        fail := true;
      end if;
    end procedure;

    -- One install = one LDTLB. ptel packs ppn/page_mask/permissions exactly
    -- as the install path in core/tlb.vhd unpacks them (see the header
    -- comment above). vpn and ppn are both std_logic_vector(31 downto 12)
    -- so they line up 1:1 with pteh_vpn / a VA's upper bits.
    -- master's install is a single clocked process with no busy/stall
    -- signal: the entry is committed on the rising edge tlb_wr is sampled,
    -- and is visible to the (purely combinational) lookups immediately
    -- after.
    procedure install (vpn       : std_logic_vector(31 downto 12);
                        asid_tag : std_logic_vector(15 downto 0);
                        ppn      : std_logic_vector(31 downto 12);
                        page_mask : std_logic_vector(3 downto 0);
                        w, x, u, c, g : std_logic) is
    begin
      pteh_vpn <= vpn;
      asidr    <= asid_tag;
      ptel     <= ppn & page_mask & w & x & u & '0' & c & g & '0' & '0';
      tlb_wr   <= '1';
      wait until rising_edge(clk);
      tlb_wr   <= '0';
      wait for 1 ns;
    end procedure;

    procedure flush_all is
    begin
      ti <= '1';
      wait until rising_edge(clk);
      ti <= '0';
      wait for 1 ns;
    end procedure;

  begin
    at <= '1'; md <= '1';
    wait until rising_edge(clk);

    -- 1. miss on an empty TLB
    i_va <= x"00001000"; wait for 1 ns;
    check(i_hit = '0', "empty TLB must miss");

    -- 2. install a 4K page and hit it.
    install(vpn => x"00001", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    i_va <= x"00001000"; wait for 1 ns;
    check(i_hit = '1', "installed 4K page must hit");
    check(i_multihit = '0', "single install must not report multi-hit");

    -- 3. ASID isolation: a non-global entry must miss under a different ASID.
    asid <= x"0001"; wait for 1 ns;
    check(i_hit = '0', "non-global entry must miss on ASID mismatch");
    asid <= x"0000"; wait for 1 ns;
    check(i_hit = '1', "entry must hit again under its own ASID");

    -- 4. superpage: a larger page must match VAs differing in the low VPN
    -- bits, and still miss outside its (masked) range. page_mask="0011"
    -- (vpn_compare_mask -> n=6) ignores VPN bits 0..5, i.e. a 256KB page
    -- (2**(12+6)) whose covered VA range here is [0x00000000, 0x0003FFFF]
    -- (the installed entry's vpn=0x00010 has all bits from 6 up equal 0).
    -- Explicit precondition (don't rely on case 3 having restored this):
    asid <= x"0000"; wait for 1 ns;
    flush_all;
    install(vpn => x"00010", asid_tag => x"0000", ppn => x"00020",
            page_mask => "0011", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    i_va <= x"00010000"; wait for 1 ns;
    check(i_hit = '1', "superpage base VA must hit");
    i_va <= x"00013000"; wait for 1 ns;
    check(i_hit = '1', "VA inside the superpage must hit (masked VPN compare)");
    -- 0x00040000 is the first VA whose VPN has bit 6 set (vpn=0x40), which
    -- differs from the installed entry's masked (all-zero) high bits -- the
    -- first VA genuinely outside the installed 256KB range.
    i_va <= x"00040000"; wait for 1 ns;
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
    install(vpn => x"00010", asid_tag => x"0000", ppn => x"00020",
            page_mask => "0011", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    install(vpn => x"00011", asid_tag => x"0000", ppn => x"00030",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    -- The narrower (2nd-installed) entry's own VA must now be a CLEAN hit:
    -- the overlapping superpage was evicted at install, not left to coexist.
    i_va <= x"00011000"; wait for 1 ns;
    check(i_hit = '1', "overlapping VA must hit the narrower, just-installed mapping");
    check(i_multihit = '0',
          "install-time overlap detection must evict the overlapping superpage, so this is a clean hit, not a multi-hit");
    -- The superpage that covered a WIDER range (e.g. 0x00010000, outside the
    -- narrower entry) is now gone -- it was evicted, so that VA misses.
    i_va <= x"00010000"; wait for 1 ns;
    check(i_hit = '0',
          "the evicted superpage's range outside the narrower entry must now miss (it was replaced, not merely deprioritized)");

    -- 6. Exact-VPN dedup: re-installing the SAME vpn/asid replaces the
    -- existing entry in place (core/tlb.vhd :234-238) rather than adding a
    -- second one -- this is the dedup case master's install path actually
    -- implements.
    flush_all;
    install(vpn => x"00001", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    install(vpn => x"00001", asid_tag => x"0000", ppn => x"00007",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    i_va <= x"00001000"; wait for 1 ns;
    check(i_hit = '1', "re-install of the same VPN/ASID must still hit");
    check(i_multihit = '0', "re-install of the same VPN/ASID must dedup, not coexist as two entries");
    check(i_pa_tag = "000000000000011",
          "re-install of the same VPN/ASID must replace the entry (surviving PA must be the 2nd install's)");

    -- 7. protection: a non-executable page fetched must report i_prot.
    flush_all;
    install(vpn => x"00001", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '1', x => '0', u => '0', c => '1',
            g => '0');
    i_va <= x"00001000"; wait for 1 ns;
    check(i_hit = '1', "X=0 page must still report a hit");
    check(i_prot = '1', "X=0 page must raise i_prot on fetch");

    -- 8. D-side install-and-hit: mirrors case 2 but through d_va/d_hit.
    -- The I-side and D-side are two independent combinational processes
    -- sharing only the tlb_match predicate -- their protection logic
    -- differs (D-side checks the store case and has no X check at all), so
    -- the D-side must be driven and checked directly, not inferred from the
    -- I-side passing.
    flush_all;
    install(vpn => x"00001", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    d_we <= '0';
    d_va <= x"00001000"; wait for 1 ns;
    check(d_hit = '1', "installed 4K page must hit on D-side");
    check(d_multihit = '0', "single install must not report D-side multi-hit");

    -- 9. D-side superpage: same range arithmetic as case 4, through d_va.
    flush_all;
    install(vpn => x"00010", asid_tag => x"0000", ppn => x"00020",
            page_mask => "0011", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    d_va <= x"00010000"; wait for 1 ns;
    check(d_hit = '1', "D-side superpage base VA must hit");
    d_va <= x"00013000"; wait for 1 ns;
    check(d_hit = '1',
          "VA inside the D-side superpage must hit (masked VPN compare)");
    -- Same corrected boundary as case 4: 0x00040000 is the first VA whose
    -- VPN has bit 6 set, genuinely outside the installed 256KB range.
    d_va <= x"00040000"; wait for 1 ns;
    check(d_hit = '0', "VA outside the (masked) D-side superpage range must miss");

    -- 10. D-side write protection: a store to a non-writable (w=0) page must
    -- raise d_prot. This is the D-side's distinctive check (`d_we='1' and
    -- entry.w='0'`) and has no I-side equivalent, so nothing else in this
    -- testbench covers it.
    flush_all;
    install(vpn => x"00001", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '0', x => '1', u => '0', c => '1',
            g => '0');
    d_we <= '1';
    d_va <= x"00001000"; wait for 1 ns;
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
    install(vpn => x"00000", asid_tag => x"0000", ppn => x"00001",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    install(vpn => x"00040", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    install(vpn => x"00000", asid_tag => x"0000", ppn => x"00020",
            page_mask => "0011", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    -- The in-range 4K entry's overlap must have been evicted at install:
    -- this VA is now a clean hit on the surviving superpage, not a
    -- multi-hit.
    i_va <= x"00001000"; wait for 1 ns;
    check(i_hit = '1', "VA formerly covered by the evicted 4K entry must still hit (now via the superpage)");
    check(i_multihit = '0',
          "install-time overlap detection must have evicted the overlapping 4K entry, so this is a clean hit");
    check(i_pa_tag = "000000000010000",
          "the surviving mapping at this VA must be the superpage (3rd-installed) entry's PA");
    -- The out-of-range 4K entry never overlapped anything and must be
    -- completely unaffected: still resident, still a clean single hit.
    i_va <= x"00040000"; wait for 1 ns;
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
    install(vpn => x"00001", asid_tag => x"0000", ppn => x"00002",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    install(vpn => x"00005", asid_tag => x"0000", ppn => x"00003",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    i_va <= x"00001000"; wait for 1 ns;
    check(i_hit = '1', "case 12 precondition: first installed VA must hit before the flush");
    i_va <= x"00005000"; wait for 1 ns;
    check(i_hit = '1', "case 12 precondition: second installed VA must hit before the flush");
    flush_all;
    i_va <= x"00001000"; wait for 1 ns;
    check(i_hit = '0', "case 12: first installed VA must miss after the flush");
    i_va <= x"00005000"; wait for 1 ns;
    check(i_hit = '0', "case 12: second installed VA must miss after the flush");

    -- 13 (was #19): a flush must invalidate within a single cycle (no
    -- 32-cycle walk). Since master's flush is a plain single-cycle clocked
    -- process (unlike the split design's serialised walk), this collapses
    -- to: the entry misses on the very next lookup after ti is deasserted,
    -- with no bounded-wait loop needed at all (there is no busy signal to
    -- poll here in the first place).
    install(vpn => x"0000a", asid_tag => x"0000", ppn => x"0000b",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    i_va <= x"0000a000"; wait for 1 ns;
    check(i_hit = '1', "case 13 precondition: installed VA must hit before the flush");

    ti <= '1';
    wait until rising_edge(clk);
    ti <= '0';
    wait for 1 ns;
    i_va <= x"0000a000"; wait for 1 ns;
    check(i_hit = '0', "case 13: flush must invalidate the entry within a single cycle");

    -- 14 (new, fix round 1): GLOBAL cross-ASID visibility. A global entry
    -- (ptel bit 2, `g` argument here) must be visible to a lookup under an
    -- ASID different from the one it was installed with, per the isolation
    -- predicate at core/tlb.vhd:105/162 (`entry.global = '1' or
    -- entry.asid_tag = asid`). Contrast directly against case 3, which
    -- already proves a NON-global entry misses under a different ASID --
    -- this case proves the opposite for g='1', so the ASID half of the
    -- predicate is exercised on both sides of the OR.
    flush_all;
    install(vpn => x"00002", asid_tag => x"0007", ppn => x"00004",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g => '1');
    i_va <= x"00002000";
    asid <= x"0007"; wait for 1 ns;
    check(i_hit = '1', "case 14 precondition: global entry must hit under its own install ASID");
    asid <= x"00ab"; wait for 1 ns;
    check(i_hit = '1', "case 14: global entry must hit under a DIFFERENT ASID than it was installed with");
    check(i_pa_tag = "000000000000010",
          "case 14: global entry's PA must be correct under the different ASID, not a miss-masked stale value");
    asid <= x"0000"; wait for 1 ns;

    -- 15 (new, fix round 1): STALE suppression on the lookup path. ptel
    -- bit 1 (tied '0' in every install above) is written straight through
    -- to entry.stale (core/tlb.vhd:280) and gates both lookup processes
    -- directly (`entry.stale = '0'` at :103/160) -- install itself does not
    -- gate on stale at all, so a stale entry can be installed exactly like
    -- any other. Install one directly with ptel(1)='1' (bypassing the
    -- `install` procedure, which always drives '0' there) and confirm the
    -- lookup path suppresses it: a probe of its VA must miss outright, not
    -- merely lose priority to some other entry.
    flush_all;
    pteh_vpn <= x"00003";
    asidr    <= x"0000";
    -- ppn=x"00005", page_mask="0000", w='1', x='1', u='0', d='0', c='1',
    -- g='0', stale='1', (unused)='0'.
    ptel     <= x"00005" & "0000" & '1' & '1' & '0' & '0' & '1' & '0' & '1' & '0';
    tlb_wr   <= '1';
    wait until rising_edge(clk);
    tlb_wr   <= '0';
    wait for 1 ns;
    i_va <= x"00003000"; wait for 1 ns;
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
    install(vpn => x"00000", asid_tag => x"0000", ppn => x"00050",
            page_mask => "0100", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    install(vpn => x"00005", asid_tag => x"0000", ppn => x"00060",
            page_mask => "0000", w => '1', x => '1', u => '0', c => '1',
            g => '0');
    i_va <= x"00005000"; wait for 1 ns;
    check(i_hit = '1', "case 16: VA inside the evicted superpage's range, covered by the new 4K page, must hit");
    check(i_multihit = '0',
          "case 16: install-time overlap detection must evict the overlapping superpage, not leave both entries coexisting as a multi-hit");
    check(i_pa_tag = "000000000110000",
          "case 16: the surviving mapping must be the narrower (2nd-installed) entry's PA");

    if fail then
      report "tlb_tb FAILED" severity failure;
    else
      report "tlb_tb PASSED" severity note;
    end if;
    done <= true;
    wait;
  end process stim;

end architecture beh;
