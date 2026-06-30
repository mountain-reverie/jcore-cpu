library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package mult_pkg is
  type mult_state_t is (NOP, DMULSL, DMULSL1, DMULSL2, DMULUL, DMULUL1, DMULUL2, MACL, MACL1, MACL2, MACW, MACW1, MACWS, MACWS1, MULL, MULL1, MULL2, MULSW, MULSW1, MULUW, MULUW1);
  type mult_result_op_t is (IDENTITY, SATURATE32, SATURATE64);
  type mult_sela_t is ( M1, MB );

  type mult_size_t is ( B16, B32 );
  constant P48MAX : std_logic_vector(63 downto 0) := x"00007fffffffffff";
  constant N48MAX : std_logic_vector(63 downto 0) := x"ffff800000000000";
  constant P32MAX : std_logic_vector(63 downto 0) := x"000000007fffffff";
  constant N32MAX : std_logic_vector(63 downto 0) := x"ffffffff80000000";

  type mult_codeline_t is record
    state    : mult_state_t;
    busy     : std_logic;
    sela     : mult_sela_t;
    shift    : std_logic;
    sign     : integer range 0 to 1;
    size     : mult_size_t;
    mach_en  : std_logic;
    macl_en  : std_logic;
    use_h    : std_logic;
  end record;

  type mult_microcode_t is array (mult_state_t) of mult_codeline_t;

  constant MULT_CODE : mult_microcode_t := (
--    state    busy sela shft sign size h_en l_en use_h
    ( NOP,     '0', M1,  '0',  0,  B16, '0', '0', '1' ), -- NOP
    ( DMULSL1, '1', M1,  '0',  1,  B32, '0', '0', '1' ), -- DMULSL
    ( DMULSL2, '1', M1,  '1',  1,  B32, '1', '1', '1' ), -- DMULSL1
    ( NOP,     '0', M1,  '1',  1,  B32, '1', '1', '1' ), -- DMULSL2
    ( DMULUL1, '1', M1,  '0',  0,  B32, '0', '0', '1' ), -- DMULUL
    ( DMULUL2, '1', M1,  '1',  0,  B32, '1', '1', '1' ), -- DMULUL1
    ( NOP,     '0', M1,  '1',  0,  B32, '1', '1', '1' ), -- DMULUL2
    ( MACL1,   '1', MB,  '0',  1,  B32, '0', '0', '1' ), -- MACL
    ( MACL2,   '1', MB,  '1',  1,  B32, '1', '1', '1' ), -- MACL1
    ( NOP,     '0', MB,  '1',  1,  B32, '1', '1', '1' ), -- MACL2
    ( MACW1,   '1', M1,  '0',  1,  B16, '0', '0', '1' ), -- MACW
    ( NOP,     '0', M1,  '0',  1,  B16, '1', '1', '1' ), -- MACW1
    ( MACWS1,  '1', M1,  '0',  1,  B16, '0', '0', '0' ), -- MACWS
    ( NOP,     '0', M1,  '0',  1,  B16, '0', '1', '0' ), -- MACWS1
    ( MULL1,   '1', M1,  '0',  1,  B32, '0', '0', '0' ), -- MULL
    ( MULL2,   '1', M1,  '1',  1,  B32, '0', '1', '0' ), -- MULL1
    ( NOP,     '0', M1,  '1',  1,  B32, '0', '1', '0' ), -- MULL2
    ( MULSW1,  '1', M1,  '0',  1,  B16, '0', '0', '0' ), -- MULSW
    ( NOP,     '0', M1,  '0',  1,  B16, '0', '1', '0' ), -- MULSW1
    ( MULUW1,  '1', M1,  '0',  0,  B16, '0', '0', '0' ), -- MULUW
    ( NOP,     '0', M1,  '0',  0,  B16, '0', '1', '0' )  -- MULUW1
  );

  type mult_i_t is record
    wr_m1   : std_logic;
    command : mult_state_t;
    s       : std_logic;
    wr_mach : std_logic;
    wr_macl : std_logic;
    in1     : std_logic_vector(31 downto 0);
    in2     : std_logic_vector(31 downto 0);
    -- Squash the MAC accumulate-commit (mach/macl latch) on a faulting
    -- MAC @Rm+,@Rn+ pass: driven by the datapath tlb_squash export
    -- (MMU_ARCH-gated, '0' on J1/J2). The FSM still sequences/drains busy;
    -- only the register write is suppressed so the clean restart accumulates
    -- exactly once. See core/datapath.vhm tlb_squash.
    acc_squash : std_logic;
  end record;

  type mult_o_t is record
    mach    : std_logic_vector(31 downto 0);
    macl    : std_logic_vector(31 downto 0);
    busy    : std_logic;
    -- slot_stall: J1 only. mult(seq) holds this high while it iterates so the
    -- datapath stretches the execution slot (freezing the WHOLE pipeline --
    -- including the writeback stage, where MAC.L issues its command). Without
    -- it, back-to-back MAC.L stream their WB-stage commands faster than the
    -- ~32-cycle sequential multiplier can accept them and get silently dropped.
    -- mult(stru) ties it to '0' (it finishes in a few cycles, so J2/J4 are
    -- unaffected -- the next mult op always finds the unit free).
    slot_stall : std_logic;
  end record;

  type mult_reg_t is record
    state : mult_state_t;
    result_op : mult_result_op_t;
    m1, m2, mb : std_logic_vector(31 downto 0);
    p23 : std_logic_vector(31 downto 0);
    mach, macl : std_logic_vector(31 downto 0);
    shift : std_logic;
    abh : std_logic_vector(46 downto 0);
    -- latched accumulate-squash: the external tlb_squash pulse drops ~1 cycle
    -- before the MACL1/MACL2 commit, so hold it for the in-flight MAC sequence.
    acc_sq : std_logic;
  end record;

  constant MULT_RESET : mult_reg_t := (state      => NOP,
                                       result_op  => IDENTITY,
                                       m1         => (others => '0'),
                                       m2         => (others => '0'),
                                       mb         => (others => '0'),                                   
                                       p23        => (others => '0'),
                                       mach       => (others => '0'),
                                       macl       => (others => '0'),
                                       shift => '0',
                                       abh => (others => '0'),
                                       acc_sq => '0'
                                       );

  component mult is

    port (
    clk : in std_logic;
    rst : in std_logic;
    slot : in std_logic;
    a    : in mult_i_t;
    y    : out mult_o_t);
    end component mult;

  -- Shared SH multiply decode/finalize, used by BOTH mult(seq) and
  -- mult(ice40dsp). The two architectures differ only in how they form the
  -- 64-bit magnitude product; everything else (operand/command decode, sign,
  -- MAC seed, saturation, MACH/MACL write) is these pure functions.
  type mult_decode_t is record
    cmd       : mult_state_t;            -- post MAC.W+S -> MACWS rewrite
    result_op : mult_result_op_t;
    mag_a     : std_logic_vector(31 downto 0); -- |operand A| (multiplicand)
    mag_b     : std_logic_vector(31 downto 0); -- |operand B| (multiplier)
    res_neg   : std_logic;               -- product magnitude must be negated
    accum     : std_logic;               -- accumulate into MACH:MACL (MAC ops)
    use_h     : std_logic;               -- high word participates in seed/result
    mach_en   : std_logic;
    macl_en   : std_logic;
    clr_mach  : std_logic;               -- zero MACH at command start (DMULxL)
    clr_macl  : std_logic;               -- zero MACL at command start
    width     : integer range 16 to 32;  -- 16 or 32 significant bits
  end record;

  type mult_macout_t is record
    mach : std_logic_vector(31 downto 0);
    macl : std_logic_vector(31 downto 0);
  end record;

  constant MULT_DECODE_NOP : mult_decode_t := (
    cmd => NOP, result_op => IDENTITY,
    mag_a => (others => '0'), mag_b => (others => '0'),
    res_neg => '0', accum => '0', use_h => '1',
    mach_en => '0', macl_en => '0', clr_mach => '0', clr_macl => '0',
    width => 32);

  function mult_decode(command : mult_state_t; s : std_logic;
                       m1, mb, m2 : std_logic_vector(31 downto 0))
    return mult_decode_t;

  function mult_finalize(dec : mult_decode_t; prod_mag : unsigned(63 downto 0);
                         cur_mach, cur_macl : std_logic_vector(31 downto 0))
    return mult_macout_t;

  function to_slv(b : std_logic; s : integer) return std_logic_vector;
end package;

package body mult_pkg is

  function to_slv(b : std_logic; s : integer) return std_logic_vector is
   variable r : std_logic_vector(s-1 downto 0);
 begin
   r := (others => b);
   return r;
 end function to_slv;

  function mult_decode(command : mult_state_t; s : std_logic;
                       m1, mb, m2 : std_logic_vector(31 downto 0))
    return mult_decode_t is
    variable d       : mult_decode_t;
    variable cmd     : mult_state_t;
    variable signd   : std_logic;
    variable use_mb  : std_logic;
    variable opa     : std_logic_vector(31 downto 0);
    variable mcand0  : unsigned(31 downto 0);
    variable mplier0 : unsigned(31 downto 0);
    variable a_neg   : std_logic;
    variable b_neg   : std_logic;
  begin
    cmd := command;
    d.result_op := IDENTITY;
    if command = MACL then
      if s = '1' then d.result_op := SATURATE64; end if;
    elsif command = MACW then
      if s = '1' then d.result_op := SATURATE32; cmd := MACWS; end if;
    end if;
    d.cmd := cmd;

    use_mb    := '0';
    signd     := '1';
    d.width   := 32;
    d.mach_en := '0';
    d.macl_en := '0';
    d.accum   := '0';
    d.use_h   := '1';

    case cmd is
      when MULL   => d.width := 32; signd := '1'; d.macl_en := '1'; d.use_h := '0';
      when MULSW  => d.width := 16; signd := '1'; d.macl_en := '1'; d.use_h := '0';
      when MULUW  => d.width := 16; signd := '0'; d.macl_en := '1'; d.use_h := '0';
      when DMULSL => d.width := 32; signd := '1'; d.mach_en := '1'; d.macl_en := '1';
      when DMULUL => d.width := 32; signd := '0'; d.mach_en := '1'; d.macl_en := '1';
      when MACL =>
        use_mb := '1'; d.width := 32; signd := '1';
        d.mach_en := '1'; d.macl_en := '1'; d.accum := '1';
      when MACW =>
        d.width := 16; signd := '1';
        d.mach_en := '1'; d.macl_en := '1'; d.accum := '1';
      when MACWS =>
        d.width := 16; signd := '1';
        d.macl_en := '1'; d.accum := '1'; d.use_h := '0';
      when others =>
        null;
    end case;

    if use_mb = '1' then opa := mb; else opa := m1; end if;

    mcand0  := unsigned(opa);
    mplier0 := unsigned(m2);
    if d.width = 16 then
      mcand0(31 downto 16)  := (others => '0');
      mplier0(31 downto 16) := (others => '0');
    end if;

    a_neg := '0';
    b_neg := '0';
    if signd = '1' then
      if d.width = 32 then
        if opa(31) = '1' then a_neg := '1'; mcand0  := unsigned(-signed(mcand0));  end if;
        if m2(31) = '1'  then b_neg := '1'; mplier0 := unsigned(-signed(mplier0)); end if;
      else
        if opa(15) = '1' then a_neg := '1'; mcand0  := x"0000" & unsigned(-signed(mcand0(15 downto 0)));  end if;
        if m2(15) = '1'  then b_neg := '1'; mplier0 := x"0000" & unsigned(-signed(mplier0(15 downto 0))); end if;
      end if;
    end if;

    d.mag_a   := std_logic_vector(mcand0);
    d.mag_b   := std_logic_vector(mplier0);
    d.res_neg := a_neg xor b_neg;

    d.clr_mach := '0';
    if command = DMULSL or command = DMULUL then d.clr_mach := '1'; end if;
    d.clr_macl := '0';
    if command /= NOP and command /= MACL and command /= MACW then d.clr_macl := '1'; end if;

    return d;
  end function;

  function mult_finalize(dec : mult_decode_t; prod_mag : unsigned(63 downto 0);
                         cur_mach, cur_macl : std_logic_vector(31 downto 0))
    return mult_macout_t is
    variable o      : mult_macout_t;
    variable prod   : std_logic_vector(63 downto 0);
    variable seed   : unsigned(63 downto 0);
    variable sum    : unsigned(63 downto 0);
    variable result : std_logic_vector(63 downto 0);
    variable sat32  : boolean;
  begin
    if dec.res_neg = '1' then
      prod := std_logic_vector((not prod_mag) + 1);
    else
      prod := std_logic_vector(prod_mag);
    end if;

    if dec.accum = '1' then
      if dec.use_h = '1' then
        seed := unsigned(cur_mach & cur_macl);
      else
        seed := unsigned(x"00000000" & cur_macl);
      end if;
    else
      seed := (others => '0');
    end if;

    sum    := unsigned(prod) + seed;
    result := std_logic_vector(sum);

    sat32 := false;
    case dec.result_op is
      when IDENTITY =>
        null;
      when SATURATE32 =>
        if prod(31) = '0' then
          if cur_macl(31) = '0' and result(31) = '1' then
            result := P32MAX; sat32 := true;
          end if;
        else
          if cur_macl(31) = '1' and result(31) = '0' then
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

    if dec.mach_en = '1' then
      o.mach := result(63 downto 32);
    else
      o.mach := cur_mach;
    end if;
    if dec.macl_en = '1' then
      o.macl := result(31 downto 0);
    else
      o.macl := cur_macl;
    end if;

    if dec.cmd = MACWS and dec.result_op = SATURATE32 and sat32 then
      o.mach := o.mach or x"00000001";
    end if;

    return o;
  end function;

end package body;
