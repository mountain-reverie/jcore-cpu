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
    test_plan(29,"test manip()");
    -- Existing manip cases ignore the t argument (only BITSET uses it); pass '0'.
    test_equal(manip(x"ffffffff", x"12345678", '0', SWAP_BYTE, true), x"12347856", "swap byte");
    test_equal(manip(x"ffffffff", x"12345678", '0', SWAP_WORD, true), x"56781234", "swap word");
    test_equal(manip(x"ffffffff", x"12345678", '0', EXTEND_UBYTE, true), x"00000078", "ext ubyte");
    test_equal(manip(x"ffffffff", x"12345678", '0', EXTEND_UWORD, true), x"00005678", "ext uword");
    test_equal(manip(x"ffffffff", x"12345678", '0', EXTEND_SBYTE, true), x"00000078", "ext sbyte 0");
    test_equal(manip(x"ffffffff", x"123456C8", '0', EXTEND_SBYTE, true), x"FFFFFFC8", "ext sbyte 1");
    test_equal(manip(x"ffffffff", x"12345678", '0', EXTEND_SWORD, true), x"00005678", "ext sword 0");
    test_equal(manip(x"ffffffff", x"1234C678", '0', EXTEND_SWORD, true), x"FFFFC678", "ext sword 1");
    test_equal(manip(x"abcdef09", x"12345678", '0', EXTRACT, true), x"5678abcd", "extract");
    test_equal(manip(x"ffffffff", x"12345678", '0', SET_BIT_7, true), x"123456F8", "set bit 7 0");
    test_equal(manip(x"ffffffff", x"12345698", '0', SET_BIT_7, true), x"12345698", "set bit 7 1");
    -- BITSET (SH-2A BST #imm3,Rn): x=Rn, y=one-hot mask (1<<imm3), t=sr.t.
    -- Insert t at the masked bit, all other bits of x pass through.
    test_equal(manip(x"00000000", x"00000008", '1', BITSET, true), x"00000008", "bitset set bit3");
    test_equal(manip(x"ffffffff", x"00000008", '0', BITSET, true), x"fffffff7", "bitset clr bit3");
    test_equal(manip(x"abcd1234", x"00000080", '1', BITSET, true), x"abcd12b4", "bitset set bit7");
    test_equal(manip(x"abcd12b4", x"00000080", '0', BITSET, true), x"abcd1234", "bitset clr bit7");
    -- SH-2A CLIPS/CLIPU saturation (manip() ignores y,t for CLIP_* funcs).
    -- clips.b: signed clamp to [-128,127]
    test_equal(manip(x"00000005", x"00000000", '0', CLIP_SB, true), x"00000005", "clips.b in-range");
    test_equal(manip(x"000000FF", x"00000000", '0', CLIP_SB, true), x"0000007F", "clips.b sat hi"); -- 255 -> +127
    test_equal(manip(x"FFFFFF00", x"00000000", '0', CLIP_SB, true), x"FFFFFF80", "clips.b sat lo"); -- -256 -> -128
    test_equal((0 => clip_saturated(x"00000005", CLIP_SB)), "0", "clips.b flag in-range");
    test_equal((0 => clip_saturated(x"000000FF", CLIP_SB)), "1", "clips.b flag sat");
    -- clips.w: signed clamp to [-32768,32767]
    test_equal(manip(x"00008000", x"00000000", '0', CLIP_SW, true), x"00007FFF", "clips.w sat hi"); -- 32768 -> 32767
    test_equal(manip(x"FFFF7FFF", x"00000000", '0', CLIP_SW, true), x"FFFF8000", "clips.w sat lo"); -- -32769 -> -32768
    test_equal((0 => clip_saturated(x"00001234", CLIP_SW)), "0", "clips.w flag in-range");
    -- clipu.b: unsigned clamp [0,255], no lower bound
    test_equal(manip(x"00000042", x"00000000", '0', CLIP_UB, true), x"00000042", "clipu.b in-range");
    test_equal(manip(x"00000100", x"00000000", '0', CLIP_UB, true), x"000000FF", "clipu.b sat hi"); -- 256 -> 255
    test_equal(manip(x"FFFFFFFF", x"00000000", '0', CLIP_UB, true), x"000000FF", "clipu.b neg sat"); -- large unsigned -> 255
    test_equal((0 => clip_saturated(x"00000100", CLIP_UB)), "1", "clipu.b flag sat");
    -- clipu.w: unsigned clamp [0,65535]
    test_equal(manip(x"00010000", x"00000000", '0', CLIP_UW, true), x"0000FFFF", "clipu.w 65536 -> 65535");
    test_equal((0 => clip_saturated(x"0000FFFF", CLIP_UW)), "0", "clipu.w 65535 no sat");
    test_finished("done");
    wait;
    end process;
end;
