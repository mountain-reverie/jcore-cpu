-- Shifter functional unit. Extracted verbatim from the inline barrel-shift
-- logic in core/datapath.vhm so its architecture can be swapped per variant
-- (J1 binds a multi-cycle seq architecture; J2/J4 keep comb). The comb
-- architecture is a thin wrapper over the proven bshifter() function in
-- cpu2j0_components_pack; clk/rst/start/busy exist for the future seq
-- architecture and are dead logic here (synthesis prunes them).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu2j0_components_pack.all;

entity shifter is
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    start : in  std_logic;
    a     : in  std_logic_vector(31 downto 0);
    b     : in  std_logic_vector(5 downto 0);
    t_in  : in  std_logic;
    op    : in  shiftfunc_t;
    y     : out std_logic_vector(31 downto 0);
    t_out : out std_logic;
    busy  : out std_logic);
end shifter;

architecture comb of shifter is
begin
  y     <= bshifter(a, b, t_in, op);
  t_out <= a(a'left) when b(b'left) = '0' else a(a'right);
  busy  <= '0';
end comb;
