-- J1 sequential shift-and-add multiplier.
--
-- This is an alternative architecture of entity 'mult' (declared in
-- core/mult.vhm / core/mult_pkg.vhd).  It has the exact same port
-- interface and reproduces the observable results (MACH/MACL) of the J2
-- multiplier 'stru', but it computes the product with a shift-and-add
-- loop instead of the 31x16 hardware multiplier.
--
-- The shift-add loop is unrolled inside the clocked process (one bit per
-- iteration, no '*' operator), so the whole product is formed in the same
-- cycle the operands are captured.  The surrounding protocol -- how
-- operands are latched (a.wr_m1 / a.in1 / a.in2), how 'mb' is captured for
-- MAC ops, how MACH/MACL are zeroed / written, the slot gating, the busy
-- handshake and the saturation -- mirrors core/mult.vhm exactly.
--
-- Only work.mult_pkg types are used.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mult_pkg.all;

architecture seq of mult is

  -- A compact register set for the sequential engine.  We do not reuse
  -- mult_reg_t (that record is tailored to the pipelined 'stru'); instead
  -- we keep the architecturally visible state plus the operand latches.
  type seq_state_t is (S_IDLE, S_RUN, S_DONE);

  type seq_reg_t is record
    sstate    : seq_state_t;
    cmd       : mult_state_t;            -- command being executed
    result_op : mult_result_op_t;        -- IDENTITY / SATURATE32 / SATURATE64
    m1        : std_logic_vector(31 downto 0); -- multiplicand latch (Rn)
    m2        : std_logic_vector(31 downto 0); -- multiplier latch   (Rm / in2)
    mb        : std_logic_vector(31 downto 0); -- saved m1 for MAC ops
    mach      : std_logic_vector(31 downto 0);
    macl      : std_logic_vector(31 downto 0);
  end record;

  constant SEQ_RESET : seq_reg_t := (
    sstate    => S_IDLE,
    cmd       => NOP,
    result_op => IDENTITY,
    m1        => (others => '0'),
    m2        => (others => '0'),
    mb        => (others => '0'),
    mach      => (others => '0'),
    macl      => (others => '0'));

  signal r, rin : seq_reg_t;

  -- Compute the signed/unsigned product of two operands by shift-and-add.
  --   mcand : multiplicand (the "a" operand, m1 or mb)
  --   mplier: multiplier   (the "b" operand, m2)
  --   width : number of significant bits (16 for B16, 32 for B32)
  --   signd : '1' for signed, '0' for unsigned
  -- Returns a full 64-bit product (sign/zero extended as appropriate).
  function shift_add_mul(mcand  : std_logic_vector(31 downto 0);
                         mplier : std_logic_vector(31 downto 0);
                         width  : integer;
                         signd  : std_logic) return std_logic_vector is
    variable ua    : unsigned(63 downto 0) := (others => '0'); -- shifting multiplicand
    variable ub    : unsigned(63 downto 0) := (others => '0'); -- shifting multiplier
    variable acc   : unsigned(63 downto 0) := (others => '0');
    variable a_neg : boolean := false;
    variable b_neg : boolean := false;
    variable amag  : unsigned(31 downto 0); -- magnitude of multiplicand
    variable bmag  : unsigned(31 downto 0); -- magnitude of multiplier
  begin
    -- Take the relevant 'width' bits of each operand.
    amag := unsigned(mcand);
    bmag := unsigned(mplier);
    if width = 16 then
      amag(31 downto 16) := (others => '0');
      bmag(31 downto 16) := (others => '0');
    end if;

    -- For signed ops, record the sign (from the top significant bit) and
    -- replace each operand with its magnitude (absolute value).
    if signd = '1' then
      if width = 32 then
        if mcand(31) = '1'  then a_neg := true; amag := unsigned(-signed(amag)); end if;
        if mplier(31) = '1' then b_neg := true; bmag := unsigned(-signed(bmag)); end if;
      else -- width = 16: sign bit is bit 15, keep magnitude in low 16 bits
        if mcand(15) = '1'  then a_neg := true; amag := (x"0000" & unsigned(-signed(amag(15 downto 0)))); end if;
        if mplier(15) = '1' then b_neg := true; bmag := (x"0000" & unsigned(-signed(bmag(15 downto 0)))); end if;
      end if;
    end if;

    ua := resize(amag, 64);
    ub := resize(bmag, 64);

    -- Shift-and-add: for each multiplier bit, conditionally add the shifted
    -- multiplicand to the accumulator.
    for i in 0 to 31 loop
      if i < width then
        if ub(0) = '1' then
          acc := acc + ua;
        end if;
        ua := ua sll 1;
        ub := ub srl 1;
      end if;
    end loop;

    -- Apply the product sign: negate if exactly one operand was negative.
    if (a_neg xor b_neg) then
      acc := (not acc) + 1;
    end if;

    return std_logic_vector(acc);
  end function shift_add_mul;

begin

  -- busy: high while a command is in flight.  The testbench does not check
  -- busy, but we expose it per the interface contract.
  y.busy <= '1' when r.sstate /= S_IDLE else '0';
  y.mach <= r.mach;
  y.macl <= r.macl;

  comb : process(r, slot, a)
    variable v       : seq_reg_t;
    variable cmd     : mult_state_t;
    variable prod    : std_logic_vector(63 downto 0);
    variable seed    : unsigned(63 downto 0);
    variable sum     : unsigned(63 downto 0);
    variable use_mb  : std_logic;
    variable signd   : std_logic;
    variable width   : integer;
    variable mach_en : std_logic;
    variable macl_en : std_logic;
    variable accum   : std_logic;
    variable use_h   : std_logic;
    variable result  : std_logic_vector(63 downto 0);
    variable rop     : mult_result_op_t;
    variable accept  : boolean;
  begin
    v := r;

    -------------------------------------------------------------------
    -- Operand / accumulator load from the CPU, gated by slot.
    -- This mirrors mult.vhm lines 120-138 (the load section) for the
    -- inputs the testbench drives (wr_m1, in1, in2; wr_mach/wr_macl are
    -- '0' in the oracle but handled here for completeness).
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
    -- Command acceptance: latch the command and decode the result_op,
    -- matching mult.vhm lines 145-154 (MACW->MACWS / s-bit handling).
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

      -- For DMULxL / MULx / MULxW the MACH/MACL are cleared at start; for
      -- MAC ops they accumulate, so they are left untouched here.
      -- (mult.vhm lines 130, 136.)
      if a.command = DMULSL or a.command = DMULUL then
        v.mach := (others => '0');
      end if;
      if a.command /= NOP and a.command /= MACL and a.command /= MACW then
        v.macl := (others => '0');
      end if;
    end if;

    -------------------------------------------------------------------
    -- Run: compute the product by shift-add and write back MACH/MACL.
    -- We do the whole multiply combinationally in one RUN cycle.
    -------------------------------------------------------------------
    if r.sstate = S_RUN then
      -- Per-command decode of the terminal behaviour.  The microcode in
      -- MULT_CODE is spread over several pipeline states in 'stru'; here we
      -- collapse it into one combinational shot, so we decide width / sign /
      -- operand-A / which of MACH:MACL to write / whether to accumulate and
      -- whether the high word participates directly from the command.
      use_mb  := '0';                  -- operand A = m1 (else mb for MAC.L)
      width   := 32;                   -- B32 by default
      signd   := '1';                  -- signed by default
      mach_en := '0';
      macl_en := '0';
      accum   := '0';                  -- seed accumulator from MACH:MACL
      use_h   := '1';                  -- high word participates in the seed/result

      case r.cmd is
        when MULL =>                       -- MUL.L: 32x32 -> MACL (low 32)
          width := 32; signd := '1'; macl_en := '1'; use_h := '0';
        when MULSW =>                      -- MULS.W: signed 16x16 -> MACL
          width := 16; signd := '1'; macl_en := '1'; use_h := '0';
        when MULUW =>                      -- MULU.W: unsigned 16x16 -> MACL
          width := 16; signd := '0'; macl_en := '1'; use_h := '0';
        when DMULSL =>                     -- DMULS.L: signed 32x32 -> 64
          width := 32; signd := '1'; mach_en := '1'; macl_en := '1';
        when DMULUL =>                     -- DMULU.L: unsigned 32x32 -> 64
          width := 32; signd := '0'; mach_en := '1'; macl_en := '1';
        when MACL =>                       -- MAC.L: (Rn)x(Rm)+MAC -> MAC (64)
          use_mb := '1'; width := 32; signd := '1';
          mach_en := '1'; macl_en := '1'; accum := '1';
        when MACW =>                       -- MAC.W: signed 16x16 + MAC -> MAC (64)
          width := 16; signd := '1';
          mach_en := '1'; macl_en := '1'; accum := '1';
        when MACWS =>                      -- MAC.W saturating: 16x16 + MACL -> MACL(32)
          width := 16; signd := '1';
          macl_en := '1'; accum := '1'; use_h := '0';
        when others =>
          null;
      end case;

      if use_mb = '1' then
        prod := shift_add_mul(v.mb, v.m2, width, signd);
      else
        prod := shift_add_mul(v.m1, v.m2, width, signd);
      end if;

      -- Seed the accumulator from the current MAC value for accumulating
      -- ops; for plain multiplies the seed is zero (MACH/MACL were zeroed at
      -- command start).  use_h selects whether MACH participates.
      if accum = '1' then
        if use_h = '1' then
          seed := unsigned(v.mach & v.macl);
        else
          seed := unsigned(x"00000000" & v.macl);
        end if;
      else
        seed := (others => '0');
      end if;

      sum := unsigned(prod) + seed;
      result := std_logic_vector(sum);

      -- Saturation, mirroring mult.vhm SATURATE32 / SATURATE64 semantics:
      -- clamp the true signed sum to the representable range.
      case r.result_op is
        when IDENTITY =>
          null;
        when SATURATE32 =>
          if signed(result) > signed(P32MAX) then
            result := P32MAX;
          elsif signed(result) < signed(N32MAX) then
            result := N32MAX;
          end if;
        when SATURATE64 =>
          if signed(result) > signed(P48MAX) then
            result := P48MAX;
          elsif signed(result) < signed(N48MAX) then
            result := N48MAX;
          end if;
      end case;

      if mach_en = '1' then
        v.mach := result(63 downto 32);
      end if;
      if macl_en = '1' then
        v.macl := result(31 downto 0);
      end if;

      -- MACWS carry-out: on saturation the J2 sets MACH bit 0 (mult.vhm
      -- line 131).  Detect saturation as "the SATURATE32 clamp fired".
      if r.cmd = MACWS and r.result_op = SATURATE32 then
        if (signed(std_logic_vector(sum)) > signed(P32MAX)) or
           (signed(std_logic_vector(sum)) < signed(N32MAX)) then
          v.mach := r.mach or x"00000001";
        end if;
      end if;

      v.sstate := S_DONE;
    end if;

    -- After one cycle of DONE, return to idle.
    if r.sstate = S_DONE then
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
