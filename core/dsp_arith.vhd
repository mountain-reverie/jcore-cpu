-- J1 iCE40 DSP-offloaded 32-bit add/sub, reproducing components_pkg.arith_unit
-- bit-for-bit using TWO free SB_MAC16 DSP blocks in pure-adder mode (no
-- multiplier product is used -- A/B/C/D ports and the BOT/TOP post-multiply
-- adder are all that's exercised).  Fully combinational (all *_REG generics
-- left at their default '0'; PIPELINE_16x16_MULT_REG1 is also left '0' since
-- we never read the registered product): CLK is wired in only because
-- SB_MAC16 is a real clocked primitive, but no output of this design depends
-- on it.
--
-- Reference semantics (components_pkg.vhd, function arith_unit):
--   is_sub  = (func = SUB)
--   b2      = b xor (is_sub replicated across all 32 bits)     -- bitwise NOT of b when SUB
--   carry0  = is_sub xor ci                                    -- LSB carry-in into the chain
--   sum(32 downto 0) = ('0'&a) + ('0'&b2) + carry0
--   sum(32) := sum(32) xor is_sub                               -- carry->borrow fixup on the top bit only
--   return sum
--
-- Design choice / why we do NOT use SB_MAC16's native ADDSUBBOT/ADDSUBTOP
-- input-negate feature for is_sub:
--   Per the transcription in core/sb_mac16_sim.vhd (itself transcribed from
--   yosys cells_sim.v, the authoritative synthesis-sim model), when
--   BOTOUTPUT_SELECT/TOPOUTPUT_SELECT = "00" the adder's *output* is ALSO
--   XORed with the replicated ADDSUBBOT/ADDSUBTOP bit (iR := YZ xor
--   addsubbot_rep), on top of the input-side XOR that negates the operand.
--   That double-XOR (once on the operand going in, once on the sum coming
--   out) does NOT correspond to arith_unit's algorithm, which XORs is_sub
--   into ci once (bit 0 of the chain) and again only on the very final
--   result bit 32 (the carry/borrow fixup) -- never on every intermediate
--   sum bit. Using ADDSUBBOT/TOP="1" here would silently invert every
--   output bit of a SUB result, which is wrong.
--
--   Instead we pre-invert b externally (b2 = b xor is_sub, 32 cheap XOR2
--   gates -- negligible next to the 32/33-bit adder+carry-chain in LUTs
--   that is the actual thing being removed from the fabric) and drive
--   ADDSUBBOT/ADDSUBTOP = '0' everywhere, i.e. SB_MAC16 is used ONLY in its
--   proven-correct pure-adder configuration -- the exact same
--   BOTADDSUB_LOWERINPUT="00"(B)/BOTADDSUB_UPPERINPUT='1'(D)/
--   TOPADDSUB_CARRYSELECT="10"(HCI=LCO, carry captured into a routable
--   O[16]) idiom that core/mult_ice40dsp.vhd already uses (DSP_C1/DSP_C23)
--   and that is validated by components/cpu/tests/sb_mac16_tap.vhd. The
--   carry/borrow fixup (xor is_sub) is then applied just once, on the final
--   33rd output bit, in plain VHDL outside the DSP -- exactly mirroring
--   arith_unit's own single top-bit fixup.
--
-- Wiring:
--   DSP_LO : B=a(15:0), D=b2(15:0), CI=carry0        -> O(15:0)=result(15:0)
--                                                        O(16)=cB (carry out of low half)
--   DSP_HI : B=a(31:16), D=b2(31:16), CI=cB          -> O(15:0)=result(31:16)
--                                                        O(16)=c32 (raw carry out of the
--                                                        full 32-bit a+b2+carry0 addition)
--   result(32) = c32 xor is_sub   (carry -> borrow fixup, same as arith_unit)
--
-- SB_MAC16 is left as an UNBOUND component (like core/mult_ice40dsp.vhd) so
-- synthesis (--syn-binding via yosys) maps it to the real DSP, while
-- GHDL simulation binds core/sb_mac16_sim.vhd.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dsp_arith is
  port (
    clk    : in  std_logic;
    a      : in  std_logic_vector(31 downto 0);
    b      : in  std_logic_vector(31 downto 0);
    is_sub : in  std_logic;
    ci     : in  std_logic;
    result : out std_logic_vector(32 downto 0));
end entity dsp_arith;

architecture ice40dsp of dsp_arith is

  signal b2       : std_logic_vector(31 downto 0);
  signal is_sub32 : std_logic_vector(31 downto 0);
  signal carry0   : std_logic;

  signal o_lo, o_hi : std_logic_vector(31 downto 0);
  -- o_lo(16) = cB  (carry out of the low 16-bit half)
  -- o_hi(16) = c32 (raw carry out of the full 32-bit addition, pre-fixup)

  component SB_MAC16 is
    generic (
      NEG_TRIGGER : std_logic := '0';
      C_REG : std_logic := '0'; A_REG : std_logic := '0';
      B_REG : std_logic := '0'; D_REG : std_logic := '0';
      TOP_8x8_MULT_REG : std_logic := '0'; BOT_8x8_MULT_REG : std_logic := '0';
      PIPELINE_16x16_MULT_REG1 : std_logic := '0';
      PIPELINE_16x16_MULT_REG2 : std_logic := '0';
      TOPOUTPUT_SELECT : std_logic_vector(1 downto 0) := "00";
      TOPADDSUB_LOWERINPUT : std_logic_vector(1 downto 0) := "00";
      TOPADDSUB_UPPERINPUT : std_logic := '0';
      TOPADDSUB_CARRYSELECT : std_logic_vector(1 downto 0) := "00";
      BOTOUTPUT_SELECT : std_logic_vector(1 downto 0) := "00";
      BOTADDSUB_LOWERINPUT : std_logic_vector(1 downto 0) := "00";
      BOTADDSUB_UPPERINPUT : std_logic := '0';
      BOTADDSUB_CARRYSELECT : std_logic_vector(1 downto 0) := "00";
      MODE_8x8 : std_logic := '0';
      A_SIGNED : std_logic := '0'; B_SIGNED : std_logic := '0');
    port (
      CLK : in std_logic; CE : in std_logic;
      A : in std_logic_vector(15 downto 0); B : in std_logic_vector(15 downto 0);
      C : in std_logic_vector(15 downto 0); D : in std_logic_vector(15 downto 0);
      AHOLD : in std_logic; BHOLD : in std_logic;
      CHOLD : in std_logic; DHOLD : in std_logic;
      IRSTTOP : in std_logic; IRSTBOT : in std_logic;
      ORSTTOP : in std_logic; ORSTBOT : in std_logic;
      OLOADTOP : in std_logic; OLOADBOT : in std_logic;
      ADDSUBTOP : in std_logic; ADDSUBBOT : in std_logic;
      OHOLDTOP : in std_logic; OHOLDBOT : in std_logic;
      CI : in std_logic; ACCUMCI : in std_logic; SIGNEXTIN : in std_logic;
      O : out std_logic_vector(31 downto 0);
      CO : out std_logic; ACCUMCO : out std_logic; SIGNEXTOUT : out std_logic);
  end component;

begin

  is_sub32 <= (others => is_sub);
  b2       <= b xor is_sub32;          -- bitwise NOT of b when is_sub='1', else b unchanged
  carry0   <= is_sub xor ci;           -- LSB carry-in into the chain, per arith_unit

  -- DSP_LO: bottom adder computes a(15:0) + b2(15:0) + carry0.
  -- Top adder is used only to capture the bottom adder's carry-out into a
  -- routable O[16] bit (0 + 0 + HCI(=LCO)), exactly the idiom used by
  -- core/mult_ice40dsp.vhd's DSP_C1/DSP_C23.
  DSP_LO : SB_MAC16
    generic map (
      BOTADDSUB_LOWERINPUT  => "00",   -- iZ = B port
      BOTADDSUB_UPPERINPUT  => '1',    -- iY = D port
      BOTADDSUB_CARRYSELECT => "11",   -- LCI = CI port
      BOTOUTPUT_SELECT      => "00",   -- Ol = bottom adder result (no product used)
      TOPADDSUB_LOWERINPUT  => "00",   -- iX = A port (tied 0)
      TOPADDSUB_UPPERINPUT  => '0',    -- iW = 0 (accumulator reg, unused)
      TOPADDSUB_CARRYSELECT => "10",   -- HCI = LCO -> captures bottom carry
      TOPOUTPUT_SELECT      => "00",   -- Oh = 0 + 0 + HCI = carry, in O(16)
      A_SIGNED => '0', B_SIGNED => '0')
    port map (
      CLK => clk, CE => '1',
      A => (others => '0'), B => a(15 downto 0),
      C => (others => '0'), D => b2(15 downto 0),
      AHOLD => '0', BHOLD => '0', CHOLD => '0', DHOLD => '0',
      IRSTTOP => '0', IRSTBOT => '0', ORSTTOP => '0', ORSTBOT => '0',
      OLOADTOP => '0', OLOADBOT => '0', ADDSUBTOP => '0', ADDSUBBOT => '0',
      OHOLDTOP => '0', OHOLDBOT => '0', CI => carry0, ACCUMCI => '0',
      SIGNEXTIN => '0', O => o_lo, CO => open, ACCUMCO => open,
      SIGNEXTOUT => open);

  -- DSP_HI: bottom adder computes a(31:16) + b2(31:16) + cB (carry from LO).
  -- Top adder captures the final 32-bit-addition carry-out into O[16].
  DSP_HI : SB_MAC16
    generic map (
      BOTADDSUB_LOWERINPUT  => "00",
      BOTADDSUB_UPPERINPUT  => '1',
      BOTADDSUB_CARRYSELECT => "11",
      BOTOUTPUT_SELECT      => "00",
      TOPADDSUB_LOWERINPUT  => "00",
      TOPADDSUB_UPPERINPUT  => '0',
      TOPADDSUB_CARRYSELECT => "10",
      TOPOUTPUT_SELECT      => "00",
      A_SIGNED => '0', B_SIGNED => '0')
    port map (
      CLK => clk, CE => '1',
      A => (others => '0'), B => a(31 downto 16),
      C => (others => '0'), D => b2(31 downto 16),
      AHOLD => '0', BHOLD => '0', CHOLD => '0', DHOLD => '0',
      IRSTTOP => '0', IRSTBOT => '0', ORSTTOP => '0', ORSTBOT => '0',
      OLOADTOP => '0', OLOADBOT => '0', ADDSUBTOP => '0', ADDSUBBOT => '0',
      OHOLDTOP => '0', OHOLDBOT => '0', CI => o_lo(16), ACCUMCI => '0',
      SIGNEXTIN => '0', O => o_hi, CO => open, ACCUMCO => open,
      SIGNEXTOUT => open);

  result(15 downto 0)  <= o_lo(15 downto 0);
  result(31 downto 16) <= o_hi(15 downto 0);
  result(32)           <= o_hi(16) xor is_sub;   -- carry->borrow fixup, matches arith_unit

end architecture ice40dsp;
