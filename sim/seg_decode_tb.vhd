library ieee;
  use ieee.std_logic_1164.all;
  use work.datapath_pack.all;

entity seg_decode_tb is
end entity seg_decode_tb;

architecture sim of seg_decode_tb is

begin

  process is
  begin

    assert seg_decode(x"00000000") = SEG_P0
      report "P0 low"
      severity failure;
    assert seg_decode(x"7FFFFFFF") = SEG_P0
      report "P0 high"
      severity failure;
    assert seg_decode(x"80000000") = SEG_P1
      report "P1 low"
      severity failure;
    assert seg_decode(x"9FFFFFFF") = SEG_P1
      report "P1 high"
      severity failure;
    assert seg_decode(x"A0000000") = SEG_P2
      report "P2 low"
      severity failure;
    assert seg_decode(x"BFFFFFFF") = SEG_P2
      report "P2 high"
      severity failure;
    assert seg_decode(x"C0000000") = SEG_P3
      report "P3 low"
      severity failure;
    assert seg_decode(x"FEFFFFFF") = SEG_P3
      report "P3 high"
      severity failure;
    assert seg_decode(x"FF000000") = SEG_P4
      report "P4 MMUCR"
      severity failure;
    assert seg_decode(x"FF000008") = SEG_P4
      report "P4 TTB"
      severity failure;
    assert seg_decode(x"FF00000C") = SEG_P4
      report "P4 TEA"
      severity failure;
    assert seg_decode(x"FF800000") = SEG_P4
      report "P4 other"
      severity failure;
    report "seg_decode_tb: all tests passed"
      severity note;
    wait;

  end process;

end architecture sim;
