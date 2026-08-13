library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.cpu2j0_pack.all;
  use work.datapath_pack.all;

-- Hardware TSB walker (design spec section 5).
--
-- On a TLB miss the core stalls (cpu.vhd withholds ack) and this FSM probes
-- the TSB set for the faulting VPN. On a match it installs through the TLB's
-- existing tlb_wr port; the faulting access then replays and translates, and
-- NO exception is ever raised. On no match it simply stops: the miss condition
-- is still true, so cpu.vhd's exception process raises the fault exactly as it
-- did before this entity existed. There is therefore no "fail" output.
--
-- The walk cannot itself fault: TSBBR is physical, so these reads bypass
-- translation entirely. No nesting, no recursion, no new exception class.

entity tlb_walk is
  generic (
    -- Ways per TSB set. Phase 1 shipped 1; Phase 2 Task 4 raises this to 2.
    -- Keeping the loop parameterised is what makes 2-way revertible.
    --
    -- A set is one 32-byte line of two contiguous 16-byte entries: way 0 at
    -- +0/+4/+8/+12 (tag_hi, tag_lo, data, reserved), way 1 at +16/+20/+24/+28.
    -- way_word() below derives those offsets from `entry_bytes`, so the way
    -- loop needs no per-way address table.
    --
    -- The `way < tsb_ways - 1` test in ST_NEXT_WAY is evaluated on the natural
    -- subtype: at tsb_ways = 1 it is `way < 0`, which is FALSE for the only
    -- reachable value (way = 0) and never underflows, because `tsb_ways - 1`
    -- is a universal-integer expression, not a natural one. At tsb_ways = 2 it
    -- is `way < 1`: way 0 advances to way 1, way 1 gives up. Both elaborate.
    tsb_ways : natural := 1;
    -- Bytes per TSB ENTRY (not per set). 16 in both phases; a 2-way set is
    -- therefore 32 bytes, which is what tsb_ptr() now aligns and indexes.
    entry_bytes : natural := 16;
    -- Liveness bound on a single walk, in cycles. `busy` suppresses the miss
    -- exception, so a walk that never finishes is a HANG where the machine
    -- owes a fault. The walk can stall for reasons outside this entity: the
    -- faulting access cpu.vhd is waiting to have acked may target a VA the
    -- memory model does not decode, in which case cpu.vhd never hands the bus
    -- over and no bus_ack ever arrives. This counter bounds that. On expiry
    -- the walker gives up exactly as it does on a tag mismatch -- it fails
    -- OPEN, to the software miss path, never closed into a stall.
    timeout_cycles : natural := 255;
    -- Liveness bound on RE-ARMING within one continuous `req` assertion.
    --
    -- `tried` is what gives the miss exception a cycle with `busy` = '0'.
    -- Because one continuous `req` level can span several DIFFERENT misses
    -- (see ST_IDLE), `tried` alone is per-level and wrongly denies the later
    -- ones a walk; the fix re-arms when the requested VPN changes. But a
    -- `req_va` that oscillates between two absent VPNs would then re-arm for
    -- ever, `busy` would suppress the exception every time, and the core would
    -- never progress -- a livelock traded for a deadlock. This counts the
    -- give-ups within one `req` assertion and saturates: once exhausted,
    -- `tried` sticks regardless of VPN and the exception is guaranteed a
    -- cycle. Cleared only when `req` falls.
    giveup_limit : natural := 4
  );
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- Miss request. Held by cpu.vhd for as long as the faulting access is
    -- stalled, so these are stable for the whole walk.
    req    : in    std_logic;
    req_va : in    std_logic_vector(31 downto 0);
    asidr  : in    std_logic_vector(15 downto 0);
    tsbbr  : in    std_logic_vector(31 downto 0);
    tsbcfg : in    std_logic_vector(31 downto 0);

    -- Bus. The walker drives its own read; cpu.vhd muxes this onto db_o.
    bus_a   : out   std_logic_vector(31 downto 0);
    bus_en  : out   std_logic;
    bus_d   : in    std_logic_vector(31 downto 0);
    bus_ack : in    std_logic;

    -- Install into the TLB, one cycle, same port LDTLB uses.
    install      : out   std_logic;
    install_ptel : out   std_logic_vector(31 downto 0);
    -- The VA this walk was started for, LATCHED at st_idle. cpu.vhd drives the
    -- TLB's pteh_vpn from this on an install. It must NOT use the live req_va:
    -- that is cpu.vhd's combinational mux (walk_va) selecting between the D-
    -- and I-side VAs on walk_d_miss, fed by sig_db_o/tlb_d_hit/tlb_d_multihit --
    -- signals this entity has no authority over and does not hold stable
    -- itself. (The I-fetch IS now stalled for the duration of an I-side walk,
    -- via dp_inst_i.ack <= inst_i.ack and not walk_supp_i in cpu.vhd -- see
    -- a9c2658 -- so that is no longer the risk.) The risk this latch actually
    -- guards is a D-side walk: were the walk to re-read live req_va at
    -- st_install instead of the value latched on arming, any cycle-to-cycle
    -- change in walk_va's selector while the walk is in flight would install
    -- the PTEL fetched for one VA under the VPN of another. Same reason the
    -- tag compare below uses va_reg.
    va_r : out   std_logic_vector(31 downto 0);

    -- High for the whole walk. cpu.vhd uses it to withhold ack, take the bus,
    -- and suppress the miss exception.
    busy : out   std_logic;

    -- '1' on the ARMING cycle only: the walk has been accepted and starts on
    -- the next rising edge, but `state` is still st_idle so `busy` is still
    -- '0'. cpu.vhd must suppress the miss exception on this cycle too.
    --
    -- Without it the walker cannot work at all. `req` is combinational over
    -- the live TLB miss signals, and so is cpu.vhd's exception process: both
    -- see the miss in the SAME cycle, and the exception wins because `busy`
    -- has not risen yet. The walk then installs into a machine that already
    -- vectored to VBR+0x400. (Measured: exception at 800 ns, install at
    -- 880 ns, on sim/tests/mmuwalkhit.S.)
    --
    -- This is NOT a "walk failed" wire: it says "a walk is being armed", never
    -- "a walk finished and lost". `tried` keeps the give-up path intact --
    -- once a walk has given up, req stays high but tried is set, so both arm
    -- and busy are low and the miss exception fires by itself exactly as
    -- before. It is deliberately separate from `busy` rather than folded into
    -- it, because cpu.vhd must apply it ONLY to the side actually being armed:
    -- an I-side miss and a D-side miss can be live in the same cycle, D wins
    -- the walk, and the I-side exception must still fire on schedule
    -- (older-instruction-first; guard mmuidorder).
    arm : out   std_logic;

    -- Anti-vacuity counters (design spec section 8). Read via the debug
    -- interface; not architectural.
    cnt_walks : out   unsigned(15 downto 0);
    cnt_hits  : out   unsigned(15 downto 0)
  );
end entity tlb_walk;

architecture rtl of tlb_walk is

  type state_t is (st_idle, st_tag_hi, st_tag_lo, st_data, st_next_way, st_install);

  signal state : state_t := st_idle;
  -- One-shot: set when a walk gives up, cleared only when `req` falls. See
  -- ST_IDLE for why the walker MUST NOT re-arm on a still-asserted req.
  signal tried : std_logic := '0';
  -- Saturating give-up counter for the current `req` assertion; see the
  -- `giveup_limit` generic. Cleared only when `req` falls.
  signal giveups : natural range 0 to giveup_limit := 0;
  -- Combinational "this request may be armed". Drives BOTH the `arm` output
  -- and the ST_IDLE arming branch, so the two can never disagree -- a
  -- registered clear of `tried` would be one cycle too late: cpu.vhd's
  -- exception process sees the miss in the very cycle the walk is denied, so
  -- the re-arm decision must be visible on `arm` in THAT cycle.
  signal may_arm  : std_logic;
  signal way      : natural range 0 to 3          := 0;
  signal set_addr : std_logic_vector(31 downto 0) := (others => '0');
  -- req_va latched at st_idle. The single source of truth for both the tag
  -- compare and the installed VPN for the whole walk.
  signal va_reg  : std_logic_vector(31 downto 0)     := (others => '0');
  signal timeout : natural range 0 to timeout_cycles := 0;
  signal ptel_r  : std_logic_vector(31 downto 0)     := (others => '0');
  signal walks_r : unsigned(15 downto 0)             := (others => '0');
  signal hits_r  : unsigned(15 downto 0)             := (others => '0');

  -- Word offset within the current way: 0 = tag_hi, 1 = tag_lo, 2 = data.

  function way_word (
    base : std_logic_vector(31 downto 0);
    w    : natural;
    word : natural;
    ebytes : natural
  ) return std_logic_vector is
  begin

    return std_logic_vector(unsigned(base) + to_unsigned(w * ebytes + word * 4, 32));

  end function way_word;

begin

  busy <= '0' when state = st_idle else
          '1';
  -- The one-shot is per-REQUEST, not per-`req`-LEVEL. `req` stays high across
  -- an I-side fetch miss that gave up and the D-side miss of an OLDER
  -- instruction that arrives right behind it, so keying the one-shot on the
  -- level alone denies the second miss its walk for a VA it was never tried
  -- for. Re-arm when the requested VPN differs from the one `tried` was set
  -- for, bounded by the saturating give-up counter.
  --
  -- The compare is on VPN(31 downto 12), not the full VA: two accesses to the
  -- same 4 KB page are the same translation, so re-arming for them would be
  -- pure wasted work (measured: 46% of all denials were a fetch VA +2 inside
  -- the page already tried). It is also materially cheaper in timing than a
  -- 32-bit compare, which matters because `arm` feeds cpu.vhd's exception
  -- suppression in the same cycle.
  may_arm      <= '1' when tried = '0'
                           or (req_va(31 downto 12) /= va_reg(31 downto 12)
                       and giveups < giveup_limit) else
                  '0';
  arm          <= '1' when state = st_idle and req = '1' and may_arm = '1' else
                  '0';
  install      <= '1' when state = st_install else
                  '0';
  install_ptel <= ptel_r;
  va_r         <= va_reg;
  cnt_walks    <= walks_r;
  cnt_hits     <= hits_r;

  bus_en <= '1' when (state = st_tag_hi or state = st_tag_lo or state = st_data) else
            '0';

  with state select bus_a <=
    way_word(set_addr, way, 0, entry_bytes) when st_tag_hi,
    way_word(set_addr, way, 1, entry_bytes) when st_tag_lo,
    way_word(set_addr, way, 2, entry_bytes) when st_data,
    (others => '0') when others;

  process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        state   <= st_idle;
        tried   <= '0';
        giveups <= 0;
        way     <= 0;
        timeout <= 0;
        walks_r <= (others => '0');
        hits_r  <= (others => '0');
      else

        case state is

          when st_idle =>

            -- One-shot. `req` is a LEVEL that stays true until the miss is
            -- resolved, so without `tried` the walker re-arms the cycle after
            -- it gives up and the exception can never fire -- the core waits
            -- forever for an ack. Task 1's spike deadlocked on exactly this.
            -- Cleared only when req falls, i.e. when the access finally
            -- completed or the exception took RB to 1.
            --
            -- `va_reg` deliberately has NO reset assignment (only a signal
            -- initialiser), so it is a plain enabled register in synthesis and
            -- its post-reset content is don't-care. That is safe: the compare
            -- above is only ever consulted when `tried` = '1', and `tried` IS
            -- reset, so the first request after reset always arms via the
            -- `tried = '0'` term without reading `va_reg` at all.
            if (req = '0') then
              tried   <= '0';
              giveups <= 0;
            elsif (may_arm = '1') then
              tried    <= '0';
              set_addr <= tsb_ptr(req_va, tsbcfg, tsbbr, asidr);
              va_reg   <= req_va;
              way      <= 0;
              timeout  <= 0;
              walks_r  <= walks_r + 1;
              state    <= st_tag_hi;
            end if;

          when st_tag_hi =>

            if (bus_ack = '1') then
              -- Full 32-bit compare against the 4 KB-granular VPN, which is
              -- what Linux writes into tag_hi (address & PAGE_MASK).
              if (bus_d(31 downto 12) = va_reg(31 downto 12)
                  and bus_d(11 downto 0) = x"000") then
                state <= st_tag_lo;
              else
                state <= st_next_way;
              end if;
            end if;

          when st_tag_lo =>

            if (bus_ack = '1') then
              -- Full-word compare against zero-extended ASIDR: a garbage or
              -- half-written tag_lo fails closed rather than aliasing.
              if (bus_d = (x"0000" & asidr)) then
                state <= st_data;
              else
                state <= st_next_way;
              end if;
            end if;

          when st_data =>

            if (bus_ack = '1') then
              ptel_r <= bus_d;
              -- V=1 and STALE=0 required. STALE would re-miss immediately and
              -- livelock; V distinguishes a real entry from a zeroed TSB,
              -- which would otherwise alias VPN 0.
              if (bus_d(0) = '1' and bus_d(1) = '0') then
                hits_r <= hits_r + 1;
                state  <= st_install;
              else
                state <= st_next_way;
              end if;
            end if;

          when st_next_way =>

            if (way < tsb_ways - 1) then
              way   <= way + 1;
              state <= st_tag_hi;
            else
              -- Give up. The miss condition is still true, so cpu.vhd raises
              -- the exception on the cycle after busy drops. `tried` MUST be
              -- set here or ST_IDLE re-arms into the same still-true req and
              -- the exception never gets a cycle in which busy is low.
              tried <= '1';
              state <= st_idle;
              if (giveups < giveup_limit) then
                giveups <= giveups + 1;
              end if;
            end if;

          when st_install =>

            state <= st_idle;

        end case;

        -- Liveness. Counted over EVERY non-idle state, so it covers the walk
        -- stalling on a bus_ack that never comes as well as an FSM that
        -- somehow fails to advance. Expiry takes the same exit as a tag
        -- mismatch: `tried` set, state st_idle, busy low -- the miss condition
        -- is still true, so cpu.vhd raises the exception on the next cycle.
        if (state /= st_idle) then
          if (timeout = timeout_cycles) then
            tried   <= '1';
            timeout <= 0;
            state   <= st_idle;
            if (giveups < giveup_limit) then
              giveups <= giveups + 1;
            end if;
          else
            timeout <= timeout + 1;
          end if;
        end if;
      end if;
    end if;

  end process;

end architecture rtl;
