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

  function to_slv(b : std_logic; s : integer) return std_logic_vector;
end package;

package body mult_pkg is

  function to_slv(b : std_logic; s : integer) return std_logic_vector is
   variable r : std_logic_vector(s-1 downto 0);
 begin
   r := (others => b);
   return r;
 end function to_slv;

end package body;
