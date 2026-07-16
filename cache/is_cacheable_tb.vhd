library ieee;
  use ieee.std_logic_1164.all;
  use work.cache_pack.all;

entity is_cacheable_tb is
end entity is_cacheable_tb;

architecture tb of is_cacheable_tb is

begin

  process is

    procedure chk (
      a    : std_logic_vector(31 downto 0);
      want : boolean;
      nm   : string
    ) is
    begin

      assert is_cacheable(a) = want
        report "is_cacheable(" & nm & ") = " & boolean'image(is_cacheable(a)) &
               " want " & boolean'image(want)
        severity failure;

    end procedure chk;

    procedure chkm (
      a    : std_logic_vector(31 downto 0);
      at,
      c    : std_logic;
      want : boolean;
      nm   : string
    ) is
    begin

      assert is_cacheable_mmu(a, at, c) = want
        report "is_cacheable_mmu(" & nm & ") = " &
               boolean'image(is_cacheable_mmu(a, at, c)) &
               " want " & boolean'image(want)
        severity failure;

    end procedure chkm;

  begin

    chk(x"00010000", true,  "P0 0x0001_0000");         -- P0 cached
    chk(x"7FFFFFFC", true,  "P0 top");                 -- P0 cached
    chk(x"80010000", true,  "P1 0x8001_0000");         -- P1 cached
    chk(x"9FFFFFFC", true,  "P1 top");                 -- P1 cached
    chk(x"A0000000", false, "P2 base");                -- P2 uncached
    chk(x"BCDE0010", false, "P2 TEST_RESULT");         -- P2 uncached (result addr)
    chk(x"ABCD0104", false, "P2 UART");                -- P2 uncached (MMIO)
    chk(x"C0000000", true,  "P3 base");                -- P3 cached
    chk(x"DFFFFFFC", true,  "P3 top");                 -- P3 cached
    chk(x"E0000000", false, "P4 base");                -- P4 uncached
    chk(x"FF000010", false, "P4 MMUCR");               -- P4 uncached (control)
    -- AT=0: identical to region decode (C ignored)
    chkm(x"00010000", '0', '0', true,  "AT0 P0 c0");   -- region cached, c ignored
    chkm(x"A0000000", '0', '1', false, "AT0 P2 c1");   -- region uncached, c ignored
    -- AT=1: C-bit authoritative (translated addr always cacheable region)
    chkm(x"00011000", '1', '1', true,  "AT1 c1");      -- cacheable page
    chkm(x"00011000", '1', '0', false, "AT1 c0");      -- uncacheable page (override)
    report "is_cacheable_tb: all tests passed"
      severity note;
    wait;

  end process;

end architecture tb;
