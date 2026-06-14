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

  -- FSM phases:
  --   S_IDLE : waiting for a command (busy='0').
  --   S_RUN  : iterating the shift-add loop, one bit per slot cycle.
  --   S_DONE : one finalisation cycle (sign-correct, accumulate, saturate,
  --            write MACH/MACL), then back to S_IDLE.
  type seq_state_t is (S_IDLE, S_RUN, S_DONE);

  type seq_reg_t is record
    sstate    : seq_state_t;
    cmd       : mult_state_t;            -- command being executed
    result_op : mult_result_op_t;        -- IDENTITY / SATURATE32 / SATURATE64
    -- operand latches (loaded from the CPU, same as mult.vhm)
    m1        : std_logic_vector(31 downto 0); -- multiplicand latch (Rn)
    m2        : std_logic_vector(31 downto 0); -- multiplier latch   (Rm / in2)
    mb        : std_logic_vector(31 downto 0); -- saved m1 for MAC ops
    mach      : std_logic_vector(31 downto 0);
    macl      : std_logic_vector(31 downto 0);
    -- sequential datapath state (the ONE adder is reused over many cycles)
    count     : unsigned(5 downto 0);    -- iterations remaining
    mcand     : unsigned(63 downto 0);   -- shifting multiplicand (<<1 each step)
    mplier    : unsigned(31 downto 0);    -- shifting multiplier   (>>1 each step)
    acc       : unsigned(63 downto 0);   -- running product magnitude
    res_neg   : std_logic;               -- final product is negative
    width     : integer range 16 to 32;  -- 16 or 32 significant bits
    accum     : std_logic;               -- accumulate into MACH:MACL (MAC ops)
    use_h     : std_logic;               -- high word participates in seed/result
    mach_en   : std_logic;
    macl_en   : std_logic;
  end record;

  constant SEQ_RESET : seq_reg_t := (
    sstate    => S_IDLE,
    cmd       => NOP,
    result_op => IDENTITY,
    m1        => (others => '0'),
    m2        => (others => '0'),
    mb        => (others => '0'),
    mach      => (others => '0'),
    macl      => (others => '0'),
    count     => (others => '0'),
    mcand     => (others => '0'),
    mplier    => (others => '0'),
    acc       => (others => '0'),
    res_neg   => '0',
    width     => 32,
    accum     => '0',
    use_h     => '1',
    mach_en   => '0',
    macl_en   => '0');

  signal r, rin : seq_reg_t;

begin

  -- busy: high while a command is in flight (RUN or DONE).
  y.busy <= '1' when r.sstate /= S_IDLE else '0';
  y.mach <= r.mach;
  y.macl <= r.macl;

  comb : process(r, slot, a)
    variable v       : seq_reg_t;
    variable cmd     : mult_state_t;
    variable rop     : mult_result_op_t;
    variable accept  : boolean;
    variable mcand0  : unsigned(31 downto 0); -- magnitude of multiplicand
    variable mplier0 : unsigned(31 downto 0); -- magnitude of multiplier
    variable a_neg   : std_logic;
    variable b_neg   : std_logic;
    variable signd   : std_logic;
    variable use_mb  : std_logic;
    variable opa     : std_logic_vector(31 downto 0);
    variable prod    : std_logic_vector(63 downto 0);
    variable seed    : unsigned(63 downto 0);
    variable sum     : unsigned(63 downto 0);
    variable result  : std_logic_vector(63 downto 0);
    variable sat32   : boolean; -- SATURATE32 overflow detected (sign-region)
  begin
    v := r;

    -------------------------------------------------------------------
    -- Operand / accumulator load from the CPU, gated by slot.
    -- Mirrors mult.vhm lines 120-138 for the inputs the testbench drives
    -- (wr_m1, in1, in2; wr_mach/wr_macl handled for completeness).
    -------------------------------------------------------------------
    accept := (r.sstate = S_IDLE) and (slot = '1') and (a.command /= NOP);

    if slot = '1' then
      if a.command /= NOP then
        v.m2 := a.in2;
        if a.command = MACL or a.command = MACW then
          v.mb := r.m1;        -- capture old m1 before it is overwritten
        end if;
      end if;
      if a.wr_m1 = '1' then
        v.m1 := a.in1;
      end if;
    end if;

    -- Explicit MACH/MACL writes from the CPU (wr_mach/wr_macl).
    if slot = '1' and a.wr_mach = '1' then
      v.mach := a.in1;
    end if;
    if slot = '1' and a.wr_macl = '1' then
      v.macl := a.in2;
    end if;

    -------------------------------------------------------------------
    -- Command acceptance: latch command, decode result_op + the
    -- per-command control (width / sign / which MAC words / accumulate),
    -- preload the sequential datapath, and clear MACH/MACL as appropriate.
    -- This mirrors mult.vhm lines 130/136/145-154.
    -------------------------------------------------------------------
    if accept then
      cmd := a.command;
      rop := IDENTITY;
      if a.command = MACL then
        if a.s = '1' then rop := SATURATE64; end if;
      elsif a.command = MACW then
        if a.s = '1' then rop := SATURATE32; cmd := MACWS; end if;
      end if;
      v.cmd       := cmd;
      v.result_op := rop;
      v.sstate    := S_RUN;

      -- Per-command decode of width / sign / operand-A / MAC-word enables.
      use_mb    := '0';   -- operand A = m1 (else mb for MAC.L)
      signd     := '1';
      v.width   := 32;
      v.mach_en := '0';
      v.macl_en := '0';
      v.accum   := '0';
      v.use_h   := '1';

      case cmd is
        when MULL =>                       -- MUL.L: 32x32 -> MACL (low 32)
          v.width := 32; signd := '1'; v.macl_en := '1'; v.use_h := '0';
        when MULSW =>                      -- MULS.W: signed 16x16 -> MACL
          v.width := 16; signd := '1'; v.macl_en := '1'; v.use_h := '0';
        when MULUW =>                      -- MULU.W: unsigned 16x16 -> MACL
          v.width := 16; signd := '0'; v.macl_en := '1'; v.use_h := '0';
        when DMULSL =>                     -- DMULS.L: signed 32x32 -> 64
          v.width := 32; signd := '1'; v.mach_en := '1'; v.macl_en := '1';
        when DMULUL =>                     -- DMULU.L: unsigned 32x32 -> 64
          v.width := 32; signd := '0'; v.mach_en := '1'; v.macl_en := '1';
        when MACL =>                       -- MAC.L: (Rn)x(Rm)+MAC -> MAC (64)
          use_mb := '1'; v.width := 32; signd := '1';
          v.mach_en := '1'; v.macl_en := '1'; v.accum := '1';
        when MACW =>                       -- MAC.W: signed 16x16 + MAC -> MAC (64)
          v.width := 16; signd := '1';
          v.mach_en := '1'; v.macl_en := '1'; v.accum := '1';
        when MACWS =>                      -- MAC.W saturating: 16x16 + MACL -> MACL(32)
          v.width := 16; signd := '1';
          v.macl_en := '1'; v.accum := '1'; v.use_h := '0';
        when others =>
          null;
      end case;

      -- Pick operand A (multiplicand).  For MAC.L it is the previously
      -- captured mb; otherwise the freshly loaded m1.  in2/m2 is operand B.
      if use_mb = '1' then
        opa := v.mb;           -- saved old m1 (captured above for MAC ops)
      else
        opa := v.m1;           -- newly loaded multiplicand
      end if;

      -- Extract magnitudes and signs.  For signed ops the sign comes from the
      -- top significant bit; the engine then multiplies absolute values and
      -- applies the product sign at the end.
      mcand0  := unsigned(opa);
      mplier0 := unsigned(v.m2);
      if v.width = 16 then
        mcand0(31 downto 16)  := (others => '0');
        mplier0(31 downto 16) := (others => '0');
      end if;

      a_neg := '0';
      b_neg := '0';
      if signd = '1' then
        if v.width = 32 then
          if opa(31) = '1'  then a_neg := '1'; mcand0  := unsigned(-signed(mcand0));  end if;
          if v.m2(31) = '1' then b_neg := '1'; mplier0 := unsigned(-signed(mplier0)); end if;
        else -- width = 16
          if opa(15) = '1'  then a_neg := '1'; mcand0  := x"0000" & unsigned(-signed(mcand0(15 downto 0)));  end if;
          if v.m2(15) = '1' then b_neg := '1'; mplier0 := x"0000" & unsigned(-signed(mplier0(15 downto 0))); end if;
        end if;
      end if;

      -- Preload the sequential datapath.
      v.mcand   := resize(mcand0, 64);
      v.mplier  := mplier0;
      v.acc     := (others => '0');
      v.res_neg := a_neg xor b_neg;
      v.count   := to_unsigned(v.width, 6);

      -- Clear MACH/MACL exactly as mult.vhm does at command start.
      if a.command = DMULSL or a.command = DMULUL then
        v.mach := (others => '0');
      end if;
      if a.command /= NOP and a.command /= MACL and a.command /= MACW then
        v.macl := (others => '0');
      end if;
    end if;

    -------------------------------------------------------------------
    -- RUN: ONE shift-add iteration per cycle (gated by slot, as the real
    -- datapath advances on slot).  This is the sequential heart of J1: a
    -- single 64-bit adder reused 'width' times -- NOT an unrolled tree, NOT
    -- the '*' operator.
    -------------------------------------------------------------------
    if r.sstate = S_RUN then
      if slot = '1' then
        if r.mplier(0) = '1' then
          v.acc := r.acc + r.mcand;       -- the ONE reused adder
        end if;
        v.mcand  := r.mcand sll 1;
        v.mplier := r.mplier srl 1;
        v.count  := r.count - 1;
        if r.count = 1 then               -- last iteration completes here
          v.sstate := S_DONE;
        end if;
      end if;
    end if;

    -------------------------------------------------------------------
    -- DONE: finalise.  Apply product sign, add the MAC seed, saturate, and
    -- write MACH/MACL.  One cycle, then back to idle.
    -------------------------------------------------------------------
    if r.sstate = S_DONE then
      if r.res_neg = '1' then
        prod := std_logic_vector((not r.acc) + 1);
      else
        prod := std_logic_vector(r.acc);
      end if;

      -- Seed from current MAC value for accumulating ops; zero otherwise
      -- (MACH/MACL were zeroed at command start for plain multiplies).
      --
      -- IMPORTANT: the seed must be SIGN-CORRECT for the running MAC value.
      -- mult.vhm forms acc = c + (mach & macl) where c is the SIGN-EXTENDED
      -- product (so the running 64-bit MAC value is treated as signed); the
      -- low half of the seed is macl regardless of use_h, and the high half is
      -- gated by use_h.  prod above is already the sign-extended product (it is
      -- a sign-correct 64-bit two's-complement value), matching c exactly.
      if r.accum = '1' then
        if r.use_h = '1' then
          seed := unsigned(r.mach & r.macl);
        else
          -- SATURATE32 (MACWS) / MACW low-only path.  The high half of the
          -- seed is zero (use_h='0', exactly mult.vhm's "mach AND 0"); the low
          -- half is macl.  Overflow is decided below by the SIGNS of the two
          -- 32-bit addends (product and prior macl) and the 32-bit result --
          -- NOT by magnitude -- so a NEGATIVE prior macl is handled correctly.
          seed := unsigned(x"00000000" & r.macl);
        end if;
      else
        seed := (others => '0');
      end if;

      sum    := unsigned(prod) + seed;
      result := std_logic_vector(sum);

      -- Saturation, mirroring mult.vhm SATURATE32 / SATURATE64 semantics.
      sat32 := false;
      case r.result_op is
        when IDENTITY =>
          null;
        when SATURATE32 =>
          -- Signed-overflow detection on the 32-bit add of the product addend
          -- (prod[31:0], sign = prod(31)) and the prior accumulator macl
          -- (sign = macl(31)), producing sum[31:0] (sign = sum(31)).
          -- This is mult.vhm lines 101-113: region = macl(31) & acc(31) & '0',
          -- with the decision keyed on c(31) (= prod(31) here):
          --   product +  (prod(31)='0'): overflow only when macl(31)='0' and
          --                              sum(31)='1'   -> clamp to P32MAX.
          --   product -  (prod(31)='1'): overflow only when macl(31)='1' and
          --                              sum(31)='0'   -> clamp to N32MAX.
          -- No magnitude comparison, so a negative running macl is preserved.
          if prod(31) = '0' then
            if r.macl(31) = '0' and result(31) = '1' then
              result := P32MAX; sat32 := true;
            end if;
          else
            if r.macl(31) = '1' and result(31) = '0' then
              result := N32MAX; sat32 := true;
            end if;
          end if;
        when SATURATE64 =>
          if signed(result) > signed(P48MAX) then
            result := P48MAX;
          elsif signed(result) < signed(N48MAX) then
            result := N48MAX;
          end if;
      end case;

      if r.mach_en = '1' then
        v.mach := result(63 downto 32);
      end if;
      if r.macl_en = '1' then
        v.macl := result(31 downto 0);
      end if;

      -- MACWS carry-out: on saturation the J2 sets MACH bit 0 (mult.vhm 131).
      -- Note this ORs into the EXISTING mach (mult.vhm: this.mach := this.mach
      -- or x"00000001"); mach is not otherwise written on the MACWS path
      -- (mach_en='0'), so it preserves the high bits of the prior MACH.
      if r.cmd = MACWS and r.result_op = SATURATE32 and sat32 then
        v.mach := r.mach or x"00000001";
      end if;

      v.sstate := S_IDLE;
      v.cmd    := NOP;
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
