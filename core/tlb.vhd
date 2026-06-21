library ieee;
use ieee.std_logic_1164.all;
use work.cpu2j0_components_pack.all;

entity tlb is
  port (
    clk      : in  std_logic;
    i_va     : in  std_logic_vector(31 downto 0);
    i_pa_tag : out std_logic_vector(18 downto 0);
    i_hit    : out std_logic;
    i_prot   : out std_logic;
    d_va     : in  std_logic_vector(31 downto 0);
    d_we     : in  std_logic;
    d_pa_tag : out std_logic_vector(18 downto 0);
    d_hit    : out std_logic;
    d_prot   : out std_logic;
    asid     : in  std_logic_vector(15 downto 0);
    md       : in  std_logic;
    at       : in  std_logic;
    tlb_wr   : in  std_logic;
    pteh_vpn : in  std_logic_vector(31 downto 12);
    ptel     : in  std_logic_vector(31 downto 0);
    asidr    : in  std_logic_vector(15 downto 0);
    ti       : in  std_logic
  );
end entity;

architecture rtl of tlb is
  signal ram : tlb_array_t := (others => TLB_ENTRY_RESET);
begin
  i_pa_tag <= (others => '0');
  i_hit    <= '0';
  i_prot   <= '0';
  d_pa_tag <= (others => '0');
  d_hit    <= '0';
  d_prot   <= '0';
end architecture;
