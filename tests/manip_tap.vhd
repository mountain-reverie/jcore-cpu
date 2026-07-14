library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu2j0_components_pack.all;
use work.test_pkg.all;

entity manip_tap is
end;

architecture tb of manip_tap is
begin
  process
    begin
    test_plan(15,"test manip()");
    -- Existing manip cases ignore the t argument (only BITSET uses it); pass '0'.
    test_equal(manip(x"ffffffff", x"12345678", '0', SWAP_BYTE), x"12347856", "swap byte");
    test_equal(manip(x"ffffffff", x"12345678", '0', SWAP_WORD), x"56781234", "swap word");
    test_equal(manip(x"ffffffff", x"12345678", '0', EXTEND_UBYTE), x"00000078", "ext ubyte");
    test_equal(manip(x"ffffffff", x"12345678", '0', EXTEND_UWORD), x"00005678", "ext uword");
    test_equal(manip(x"ffffffff", x"12345678", '0', EXTEND_SBYTE), x"00000078", "ext sbyte 0");
    test_equal(manip(x"ffffffff", x"123456C8", '0', EXTEND_SBYTE), x"FFFFFFC8", "ext sbyte 1");
    test_equal(manip(x"ffffffff", x"12345678", '0', EXTEND_SWORD), x"00005678", "ext sword 0");
    test_equal(manip(x"ffffffff", x"1234C678", '0', EXTEND_SWORD), x"FFFFC678", "ext sword 1");
    test_equal(manip(x"abcdef09", x"12345678", '0', EXTRACT), x"5678abcd", "extract");
    test_equal(manip(x"ffffffff", x"12345678", '0', SET_BIT_7), x"123456F8", "set bit 7 0");
    test_equal(manip(x"ffffffff", x"12345698", '0', SET_BIT_7), x"12345698", "set bit 7 1");
    -- BITSET (SH-2A BST #imm3,Rn): x=Rn, y=one-hot mask (1<<imm3), t=sr.t.
    -- Insert t at the masked bit, all other bits of x pass through.
    test_equal(manip(x"00000000", x"00000008", '1', BITSET), x"00000008", "bitset set bit3");
    test_equal(manip(x"ffffffff", x"00000008", '0', BITSET), x"fffffff7", "bitset clr bit3");
    test_equal(manip(x"abcd1234", x"00000080", '1', BITSET), x"abcd12b4", "bitset set bit7");
    test_equal(manip(x"abcd12b4", x"00000080", '0', BITSET), x"abcd1234", "bitset clr bit7");
    test_finished("done");
    wait;
    end process;
end;
