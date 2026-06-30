-- J1 sequential shift-and-add multiplier.
--
-- This is an alternative architecture of entity 'mult' (declared in
-- core/mult.vhm / core/mult_pkg.vhd).  It has the exact same port interface
-- and reproduces the observable results (MACH/MACL) of the J2 multiplier
-- 'stru', but it computes the product with a GENUINELY SEQUENTIAL
-- shift-and-add FSM instead of the 31x16 hardware array multiplier.
--
-- J1's whole reason to exist is to make the CPU SMALLER by removing the
-- hardware multiplier.  A combinationally-unrolled 32-step shift-add would
-- synthesise to a full array multiplier -- as big (or bigger) than the unit
-- we are trying to remove -- so that is exactly what we must NOT do.
--
-- Instead, this engine has ONE add/shift datapath that is reused over
-- ~N clock cycles (N = 32 for 32-bit ops, 16 for 16-bit ops).  It holds
-- y.busy = '1' for the entire duration; the CPU pipeline already stalls on
-- busy (mac_stall in decode_core), so the long latency is harmless -- slow
-- is the GOAL here, area is the prize.
--
-- The surrounding protocol -- how operands are latched (a.wr_m1 / a.in1 /
-- a.in2), how 'mb' is captured for MAC ops, how MACH/MACL are zeroed /
-- written, the slot gating, the busy handshake and the saturation -- mirrors
-- core/mult.vhm exactly.
--
-- Only work.mult_pkg types are used.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mult_pkg.all;

architecture seq of mult is

  type seq_state_t is (S_IDLE, S_RUN, S_DONE);

  type seq_reg_t is record
    sstate : seq_state_t;
    dec    : mult_decode_t;                -- decoded command (shared decode)
    m1     : std_logic_vector(31 downto 0);
    m2     : std_logic_vector(31 downto 0);
    mb     : std_logic_vector(31 downto 0);
    mach   : std_logic_vector(31 downto 0);
    macl   : std_logic_vector(31 downto 0);
    count  : unsigned(5 downto 0);         -- iterations remaining
    mcand  : unsigned(63 downto 0);        -- shifting multiplicand magnitude
    mplier : unsigned(31 downto 0);        -- shifting multiplier magnitude
    acc    : unsigned(63 downto 0);        -- running product magnitude
  end record;

  constant SEQ_RESET : seq_reg_t := (
    sstate => S_IDLE, dec => MULT_DECODE_NOP,
    m1 => (others => '0'), m2 => (others => '0'), mb => (others => '0'),
    mach => (others => '0'), macl => (others => '0'),
    count => (others => '0'), mcand => (others => '0'),
    mplier => (others => '0'), acc => (others => '0'));

  signal r, rin : seq_reg_t;

begin

  y.busy       <= '1' when r.sstate /= S_IDLE else '0';
  y.slot_stall <= '1' when r.sstate /= S_IDLE else '0';
  y.mach       <= r.mach;
  y.macl       <= r.macl;

  comb : process(r, slot, a)
    variable v      : seq_reg_t;
    variable accept : boolean;
    variable dec    : mult_decode_t;
    variable o      : mult_macout_t;
  begin
    v := r;

    -- Operand / accumulator load from the CPU, gated by slot.
    accept := (r.sstate = S_IDLE) and (slot = '1') and (a.command /= NOP);
    if slot = '1' then
      if a.command /= NOP then
        v.m2 := a.in2;
        if a.command = MACL or a.command = MACW then
          v.mb := r.m1;
        end if;
      end if;
      if a.wr_m1 = '1' then
        v.m1 := a.in1;
      end if;
    end if;
    if slot = '1' and a.wr_mach = '1' then
      v.mach := a.in1;
    end if;
    if slot = '1' and a.wr_macl = '1' then
      v.macl := a.in2;
    end if;

    -- Command acceptance: shared decode, then preload the sequential datapath
    -- with the magnitude operands and clear MACH/MACL as decoded.
    if accept then
      dec := mult_decode(a.command, a.s, v.m1, v.mb, v.m2);
      v.dec    := dec;
      v.sstate := S_RUN;
      v.mcand  := resize(unsigned(dec.mag_a), 64);
      v.mplier := unsigned(dec.mag_b);
      v.acc    := (others => '0');
      v.count  := to_unsigned(dec.width, 6);
      if dec.clr_mach = '1' then v.mach := (others => '0'); end if;
      if dec.clr_macl = '1' then v.macl := (others => '0'); end if;
    end if;

    -- RUN: ONE shift-add iteration per cycle (the sequential heart of J1).
    if r.sstate = S_RUN then
      if r.mplier(0) = '1' then
        v.acc := r.acc + r.mcand;
      end if;
      v.mcand  := r.mcand sll 1;
      v.mplier := r.mplier srl 1;
      v.count  := r.count - 1;
      if r.count = 1 then
        v.sstate := S_DONE;
      end if;
    end if;

    -- DONE: shared finalize (sign + MAC seed + saturate + MACH/MACL write).
    if r.sstate = S_DONE then
      o := mult_finalize(r.dec, r.acc, r.mach, r.macl);
      v.mach    := o.mach;
      v.macl    := o.macl;
      v.sstate  := S_IDLE;
      v.dec.cmd := NOP;
    end if;

    rin <= v;
  end process;

  reg : process(clk, rst)
  begin
    if rst = '1' then
      r <= SEQ_RESET;
    elsif rising_edge(clk) then
      r <= rin;
    end if;
  end process;

end seq;
