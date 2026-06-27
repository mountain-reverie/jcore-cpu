-- ===========================================================================
-- tlb -- J4 software-loaded translation lookaside buffer (MMU_ARCH only).
--
-- 32-entry, fully associative, software-loaded TLB. Parallel I-side and D-side
-- COMBINATIONAL lookup each cycle; a clocked process handles LDTLB installs and
-- the MMUCR.TI flush. There is no hardware page-table walker: a miss raises an
-- access-type exception and privileged software installs the entry (LDTLB /
-- LDTLB.RN). Fixed 4 KB pages. Instantiated in core/cpu.vhd under
-- `g_mmu : if MMU_ARCH generate`.
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
-- mmuasid, mmustale, mmustore, mmureloc*, ...).
--
-- Entry layout (work.cpu2j0_components_pack tlb_entry_t) and PTEL flag bits:
--   PPN = PTEL[31:10]; W7 X6 U5 D4 C3 G2 STALE1 V0.
-- ===========================================================================
library ieee;
use ieee.std_logic_1164.all;
use work.cpu2j0_components_pack.all;

entity tlb is
  port (
    clk      : in  std_logic;
    -- I-side (instruction fetch) lookup: VA in, translation + status out.
    i_va     : in  std_logic_vector(31 downto 0);
    i_pa_tag : out std_logic_vector(14 downto 0);  -- PA[27:13] of the hit entry
    i_pa12   : out std_logic;                       -- PA[12] (PIPT relocation)
    i_c      : out std_logic;                       -- cacheable (PTE.C)
    i_hit    : out std_logic;                       -- usable match found
    i_prot   : out std_logic;                       -- hit but permission violated
    -- D-side (load/store) lookup; d_we=1 marks the access a store (W check).
    d_va     : in  std_logic_vector(31 downto 0);
    d_we     : in  std_logic;
    d_pa_tag : out std_logic_vector(14 downto 0);
    d_pa12   : out std_logic;
    d_c      : out std_logic;
    d_hit    : out std_logic;
    d_prot   : out std_logic;
    -- Current context + mode for the lookup.
    asid     : in  std_logic_vector(15 downto 0);   -- live ASIDR (lookup tag)
    md       : in  std_logic;                       -- SR.MD (1=privileged)
    at       : in  std_logic;                       -- MMUCR.AT (translate enable)
    -- Install (LDTLB) + flush (MMUCR.TI) inputs.
    tlb_wr   : in  std_logic;                        -- 1 => install {asidr,pteh,ptel}
    pteh_vpn : in  std_logic_vector(31 downto 12);   -- VPN to install
    ptel     : in  std_logic_vector(31 downto 0);    -- PPN + flags to install
    asidr    : in  std_logic_vector(15 downto 0);    -- ASID_TAG to stamp on install
    ti       : in  std_logic                         -- 1 => flush all entries
  );
end entity;

architecture rtl of tlb is
  signal ram : tlb_array_t := (others => TLB_ENTRY_RESET);
begin

  -- Combinational I-lookup (instruction fetch). Scan all 32 entries; a usable
  -- match requires VALID and not-STALE and VPN match and (GLOBAL or ASID match)
  -- -- the isolation predicate (docs/architecture/tlb.md §3). On a hit, an
  -- instruction fetch is a protection violation when the page is non-executable
  -- (X=0) OR it is a supervisor page (U=0) accessed from user mode (MD=0).
  -- Note: on a multi-hit the last (highest-index) match wins; software must not
  -- install duplicate VPN+ASID entries.
  process(ram, i_va, asid, md)
    variable entry     : tlb_entry_t;
    variable hit_found : std_logic;
    variable hit_pa    : std_logic_vector(14 downto 0);
    variable hit_pa12  : std_logic;
    variable hit_c     : std_logic;
    variable prot      : std_logic;
  begin
    hit_found := '0'; hit_pa := (others => '0'); hit_pa12 := '0'; hit_c := '0'; prot := '0';
    for k in 0 to 31 loop
      entry := ram(k);
      if entry.valid = '1'
         and entry.stale = '0'  -- STALE (PTEL[1]) = SW soft-invalidate/revocation (mmustale)
         and entry.vpn = i_va(31 downto 12)
         and (entry.global = '1' or entry.asid_tag = asid) then  -- ASID isolation (mmuasid)
        hit_found := '1';
        hit_pa    := entry.ppn(27 downto 13);  -- PA[27:13] = 15-bit relocation tag
        hit_pa12  := entry.ppn(12);            -- PA[12] (PIPT relocation, mmurelocif)
        hit_c     := entry.c;
        if entry.x = '0' or (entry.u = '0' and md = '0') then  -- X / user-on-super (mmufault)
          prot := '1';
        end if;
      end if;
    end loop;
    i_hit    <= hit_found;
    i_pa_tag <= hit_pa;
    i_pa12   <= hit_pa12;
    i_c      <= hit_c;
    i_prot   <= prot and hit_found;  -- prot only meaningful on a hit
  end process;

  -- Combinational D-lookup (load/store). Same isolation predicate as the I-side.
  -- A data access is a protection violation when it is a supervisor page (U=0)
  -- accessed from user mode (MD=0), OR it is a STORE (d_we=1) to a non-writable
  -- (W=0) page -- the W check applies to the kernel too (no privileged write
  -- bypass). There is no separate read bit (readability = U for user, else
  -- kernel). See docs/architecture/tlb.md §3; guard mmufault (DPROT_R/DPROT_W).
  process(ram, d_va, d_we, asid, md)
    variable entry     : tlb_entry_t;
    variable hit_found : std_logic;
    variable hit_pa    : std_logic_vector(14 downto 0);
    variable hit_pa12  : std_logic;
    variable hit_c     : std_logic;
    variable prot      : std_logic;
  begin
    hit_found := '0'; hit_pa := (others => '0'); hit_pa12 := '0'; hit_c := '0'; prot := '0';
    for k in 0 to 31 loop
      entry := ram(k);
      if entry.valid = '1'
         and entry.stale = '0'  -- STALE (PTEL[1]) = software soft-invalidate
         and entry.vpn = d_va(31 downto 12)
         and (entry.global = '1' or entry.asid_tag = asid) then
        hit_found := '1';
        hit_pa    := entry.ppn(27 downto 13);
        hit_pa12  := entry.ppn(12);            -- PA[12] (PIPT relocation)
        hit_c     := entry.c;
        if (entry.u = '0' and md = '0') or (d_we = '1' and entry.w = '0') then
          prot := '1';
        end if;
      end if;
    end loop;
    d_hit    <= hit_found;
    d_pa_tag <= hit_pa;
    d_pa12   <= hit_pa12;
    d_c      <= hit_c;
    d_prot   <= prot and hit_found;
  end process;

  -- Clocked install (LDTLB) + MMUCR.TI flush. TI clears VALID (and the NRU
  -- "used" state) on every entry -> a full revocation (docs/architecture/tlb.md
  -- §6). An install latches the whole entry atomically from {asidr, pteh_vpn,
  -- ptel} into one NRU-chosen slot (no half-written, matchable entry). NRU
  -- replacement: prefer an invalid slot, else a not-recently-used one, else
  -- clear all "used" bits and take slot 0. The installed entry's flags come
  -- straight from PTEL (W7 X6 U5 D4 C3 G2 STALE1 V0); STALE is preserved so
  -- software can install an entry already soft-invalidated.
  process(clk)
    variable idx      : integer range 0 to 31;
    variable found    : boolean;
    variable all_used : boolean;
  begin
    if rising_edge(clk) then
      if ti = '1' then
        for k in 0 to 31 loop
          ram(k).valid <= '0';
          ram(k).used  <= '0';
        end loop;
      elsif tlb_wr = '1' then
        -- NRU: find first invalid slot; if none, first unused; if all used clear all
        idx := 0; found := false; all_used := true;
        for k in 0 to 31 loop
          if not found then
            if ram(k).valid = '0' then
              idx := k; found := true;
            elsif ram(k).used = '0' then
              if all_used then idx := k; end if;
              all_used := false;
            end if;
          end if;
        end loop;
        if not found and all_used then
          -- all entries valid+used: clear used bits, write to slot 0
          for k in 0 to 31 loop
            ram(k).used <= '0';
          end loop;
          idx := 0;
        end if;
        ram(idx).valid     <= '1';
        ram(idx).used      <= '1';
        ram(idx).vpn       <= pteh_vpn;
        ram(idx).asid_tag  <= asidr;
        ram(idx).page_mask <= (others => '0');
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

end architecture;
