-- Generic behavioral simulation entity+architecture for ram_1rw.
-- Replaces the jcore-soc lib entity: no fixed-dimension assertion,
-- supports arbitrary SUBWORD_WIDTH/SUBWORD_NUM/ADDR_WIDTH.
-- Included in VHDS INSTEAD OF the jcore-soc lib version.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.memory_pack.all;

entity ram_1rw is
  generic (
    SUBWORD_WIDTH    : natural;
    SUBWORD_NUM      : natural;
    ADDR_WIDTH       : natural;
    CHECK_DIMENSIONS : boolean := false);
  port (
    rst : in  std_logic;
    clk : in  std_logic;
    en  : in  std_logic;
    wr  : in  std_logic;
    we  : in  std_logic_vector(SUBWORD_NUM-1 downto 0);
    a   : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    dw  : in  std_logic_vector(SUBWORD_WIDTH*SUBWORD_NUM-1 downto 0);
    dr  : out std_logic_vector(SUBWORD_WIDTH*SUBWORD_NUM-1 downto 0);
    margin : in std_logic_vector(1 downto 0));
end entity;

architecture sim of ram_1rw is
  constant W : natural := SUBWORD_WIDTH * SUBWORD_NUM;
  constant D : natural := 2 ** ADDR_WIDTH;
  type mem_t is array (0 to D-1) of std_logic_vector(W-1 downto 0);
  signal mem : mem_t := (others => (others => '0'));
  signal dr_r : std_logic_vector(W-1 downto 0) := (others => '0');
begin
  process(clk)
    variable idx : integer;
    variable word : std_logic_vector(W-1 downto 0);
  begin
    if rising_edge(clk) then
      if en = '1' then
        idx := to_integer(unsigned(a));
        if wr = '1' then
          word := mem(idx);
          for s in 0 to SUBWORD_NUM-1 loop
            if we(s) = '1' then
              word(SUBWORD_WIDTH*(s+1)-1 downto SUBWORD_WIDTH*s) :=
                dw(SUBWORD_WIDTH*(s+1)-1 downto SUBWORD_WIDTH*s);
            end if;
          end loop;
          mem(idx) <= word;
        else
          dr_r <= mem(idx);
        end if;
      end if;
    end if;
  end process;
  dr <= dr_r;
end architecture;
