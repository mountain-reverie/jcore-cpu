-- J1 iCE40 DSP-offloaded 32-bit add/sub, reproducing components_pkg.arith_unit
-- bit-for-bit using ONE free SB_MAC16 DSP block in pure-adder mode (no
-- multiplier product is used -- the A/B/C/D bypass ports and the BOT/TOP
-- post-multiply adders chained by the tile-local carry are all that is
-- exercised).  Fully combinational (all *_REG generics left at their default
-- '0'; PIPELINE_16x16_MULT_REG1 is also left '0' since we never read the
-- registered product): CLK is wired in only because SB_MAC16 is a real
-- clocked primitive, but no output of this design depends on it.
--
-- Reference semantics (components_pkg.vhd, function arith_unit):
--   is_sub  = (func = SUB)
--   b2      = b xor (is_sub replicated across all 32 bits)     -- bitwise NOT of b when SUB
--   carry0  = is_sub xor ci                                    -- LSB carry-in into the chain
--   sum(32 downto 0) = ('0'&a) + ('0'&b2) + carry0
--   sum(32) := sum(32) xor is_sub                               -- carry->borrow fixup on the top bit only
--   return sum
--
-- WHY ONE BLOCK IS ENOUGH:
--   A single SB_MAC16 contains TWO 16-bit post-multiply adders (BOT and TOP)
--   whose carry chains together inside the tile: with
--   TOPADDSUB_CARRYSELECT="10" the TOP adder's carry-in HCI is fed by the BOT
--   adder's carry-out LCO (a tile-local wire, no fabric routing needed). So
--   BOT computes the low 16-bit column and TOP the high 16-bit column of ONE
--   32-bit addition, and O[31:0] is the full 32-bit sum. This is the exact
--   idiom core/mult_ice40dsp.vhd's DSP_C23 already uses (F[15:0]+M[31:16]+cB in
--   BOT, F[31:16]+M[32]+carry in TOP) and that
--   components/cpu/tests/sb_mac16_tap.vhd validates. The previous two-block
--   version wasted a whole second DSP purely to re-add the high half; folding
--   it into this block's TOP adder frees one DSP (9/8 -> 8/8, fits iCESugar).
--
-- Design choice / why we do NOT use SB_MAC16's native ADDSUBBOT/ADDSUBTOP
-- input-negate feature for is_sub:
--   Per core/sb_mac16_sim.vhd (transcribed from yosys cells_sim.v), when
--   BOTOUTPUT_SELECT/TOPOUTPUT_SELECT = "00" the adder's *output* is ALSO
--   XORed with the replicated ADDSUBBOT/ADDSUBTOP bit (iR := YZ xor
--   addsubbot_rep), on top of the input-side XOR that negates the operand.
--   That double-XOR does NOT correspond to arith_unit's algorithm. So we
--   pre-invert b externally (b2 = b xor is_sub) and drive ADDSUBBOT/TOP='0'
--   everywhere, i.e. SB_MAC16 is used ONLY in its proven-correct pure-adder
--   configuration. The carry/borrow fixup (xor is_sub) is applied just once,
--   on the final 33rd output bit, in plain VHDL outside the DSP.
--
-- Port map (single block):
--   BOT: iZ=B=a(15:0), iY=D=b2(15:0),  LCI=CI=carry0   -> O(15:0)  = result(15:0)
--   TOP: iX=A=a(31:16), iW=C=b2(31:16), HCI=LCO        -> O(31:16) = result(31:16)
--   O(31:0) = ('0'&a) + ('0'&b2) + carry0, the full 32-bit sum.
--
-- Bit 32 (the 33rd carry/borrow) is computed in a FEW FABRIC LUTs, because a
-- DSP adder's carry-out (CO/ACCUMCO) cannot drive fabric on iCE40. We recover
-- it from the true full-adder relation on the MSB column:
--   cin31 = O(31) xor a(31) xor b2(31)               -- carry INTO bit 31
--   c32   = (a31 and b2_31) or (a31 and cin31) or (b2_31 and cin31)   -- majority carry-out
--   result(32) = c32 xor is_sub                       -- carry->borrow fixup, per arith_unit
-- (Note: the carry-out is majority(a31, b2_31, cin31) -- using the carry INTO
-- the bit, NOT the sum bit; majority(a,b,sum) is NOT a valid carry-out.)
--
-- SB_MAC16 is left as an UNBOUND component (like core/mult_ice40dsp.vhd) so
-- synthesis (--syn-binding via yosys) maps it to the real DSP, while GHDL
-- simulation binds core/sb_mac16_sim.vhd.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity dsp_arith is
  port (
    clk    : in    std_logic;
    a      : in    std_logic_vector(31 downto 0);
    b      : in    std_logic_vector(31 downto 0);
    is_sub : in    std_logic;
    ci     : in    std_logic;
    result : out   std_logic_vector(32 downto 0)
  );
end entity dsp_arith;

architecture ice40dsp of dsp_arith is

  signal b2       : std_logic_vector(31 downto 0);
  signal is_sub32 : std_logic_vector(31 downto 0);
  signal carry0   : std_logic;

  signal o          : std_logic_vector(31 downto 0);  -- O(31:0) = 32-bit sum
  signal cin31, c32 : std_logic;

  component sb_mac16 is
    generic (
      neg_trigger              : std_logic := '0';
      c_reg                    : std_logic := '0';
      a_reg                    : std_logic := '0';
      b_reg                    : std_logic := '0';
      d_reg                    : std_logic := '0';
      top_8x8_mult_reg         : std_logic := '0';
      bot_8x8_mult_reg         : std_logic := '0';
      pipeline_16x16_mult_reg1 : std_logic := '0';
      pipeline_16x16_mult_reg2 : std_logic := '0';
      topoutput_select         : std_logic_vector(1 downto 0) := "00";
      topaddsub_lowerinput     : std_logic_vector(1 downto 0) := "00";
      topaddsub_upperinput     : std_logic := '0';
      topaddsub_carryselect    : std_logic_vector(1 downto 0) := "00";
      botoutput_select         : std_logic_vector(1 downto 0) := "00";
      botaddsub_lowerinput     : std_logic_vector(1 downto 0) := "00";
      botaddsub_upperinput     : std_logic := '0';
      botaddsub_carryselect    : std_logic_vector(1 downto 0) := "00";
      mode_8x8                 : std_logic := '0';
      a_signed                 : std_logic := '0';
      b_signed                 : std_logic := '0'
    );
    port (
      clk        : in    std_logic;
      ce         : in    std_logic;
      a          : in    std_logic_vector(15 downto 0);
      b          : in    std_logic_vector(15 downto 0);
      c          : in    std_logic_vector(15 downto 0);
      d          : in    std_logic_vector(15 downto 0);
      ahold      : in    std_logic;
      bhold      : in    std_logic;
      chold      : in    std_logic;
      dhold      : in    std_logic;
      irsttop    : in    std_logic;
      irstbot    : in    std_logic;
      orsttop    : in    std_logic;
      orstbot    : in    std_logic;
      oloadtop   : in    std_logic;
      oloadbot   : in    std_logic;
      addsubtop  : in    std_logic;
      addsubbot  : in    std_logic;
      oholdtop   : in    std_logic;
      oholdbot   : in    std_logic;
      ci         : in    std_logic;
      accumci    : in    std_logic;
      signextin  : in    std_logic;
      o          : out   std_logic_vector(31 downto 0);
      co         : out   std_logic;
      accumco    : out   std_logic;
      signextout : out   std_logic
    );
  end component sb_mac16;

begin

  is_sub32 <= (others => is_sub);
  b2       <= b xor is_sub32; -- bitwise NOT of b when is_sub='1', else b unchanged
  carry0   <= is_sub xor ci;  -- LSB carry-in into the chain, per arith_unit

  -- Single SB_MAC16: BOT adds the low 16-bit column, TOP adds the high 16-bit
  -- column, chained by the tile-local BOT->TOP carry (TOPADDSUB_CARRYSELECT=
  -- "10" -> HCI=LCO). Same pure-adder idiom as mult_ice40dsp.vhd's DSP_C23.
  dsp : component sb_mac16
    generic map (
      botaddsub_lowerinput  => "00",
      botaddsub_upperinput  => '1',
      botaddsub_carryselect => "11",
      botoutput_select      => "00",
      topaddsub_lowerinput  => "00",
      topaddsub_upperinput  => '1',
      topaddsub_carryselect => "10",
      topoutput_select      => "00",
      a_signed              => '0', b_signed => '0'
    )
    port map (
      clk        => clk,
      ce         => '1',
      a          => a(31 downto 16),
      b          => a(15 downto 0),
      c          => b2(31 downto 16),
      d          => b2(15 downto 0),
      ahold      => '0',
      bhold      => '0',
      chold      => '0',
      dhold      => '0',
      irsttop    => '0',
      irstbot    => '0',
      orsttop    => '0',
      orstbot    => '0',
      oloadtop   => '0',
      oloadbot   => '0',
      addsubtop  => '0',
      addsubbot  => '0',
      oholdtop   => '0',
      oholdbot   => '0',
      ci         => carry0,
      accumci    => '0',
      signextin  => '0',
      o          => o,
      co         => open,
      accumco    => open,
      signextout => open
    );

  -- 33rd bit (carry/borrow) in fabric: true full-adder carry-out of the MSB.
  cin31 <= o(31) xor a(31) xor b2(31); -- carry into bit 31
  c32   <= (a(31) and b2(31))
           or (a(31) and cin31)
           or (b2(31) and cin31);      -- majority = carry out of bit 31

  result(31 downto 0) <= o;
  result(32)          <= c32 xor is_sub; -- carry->borrow fixup, matches arith_unit

end architecture ice40dsp;
