-- An assemtric ram with a 16-bit wide read-only port and a 32-bit wide
-- read/write port.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity asymmetric_ram is
  generic (
    -- Bit width of the data addressed by the 16-bit read port. Addresses of
    -- the 32-bit read/write port have one less bits.
    addr_width : integer := 14
  );
  port (
    clka : in    std_logic;
    clkb : in    std_logic;

    ena   : in    std_logic;
    addra : in    std_logic_vector(addr_width - 1 downto 0);
    doa   : out   std_logic_vector(15 downto 0);

    enb   : in    std_logic;
    web   : in    std_logic_vector(3 downto 0);
    addrb : in    std_logic_vector(addr_width - 2 downto 0);
    dib   : in    std_logic_vector(31 downto 0);
    dob   : out   std_logic_vector(31 downto 0)
  );
end entity asymmetric_ram;

architecture behavioral of asymmetric_ram is

  constant num_words : integer := 2 ** addr_width;

  type ram_type is array (0 to num_words - 1) of std_logic_vector(15 downto 0);

  impure function load_binary (
    filename : string
  ) return ram_type is

    type binary_file is file of character;

    file     f   : binary_file;
    variable c   : character;
    variable mem : ram_type;

  begin

    file_open(f, filename, read_mode);

    for i in ram_type'range loop

      mem(i) := (others => '0');
      -- read 2 bytes and store in big endian order
      for bi in 1 downto 0 loop

        if (not endfile(f)) then
          read(f, c);
          mem(i)((bi + 1) * 8 - 1 downto bi * 8) := std_logic_vector(to_unsigned(character'pos(c), 8));
        end if;

      end loop;

    end loop;

    file_close(f);
    return mem;

  end function load_binary;

  signal ram : ram_type := load_binary("ram.img");

begin

  process (clka) is
  begin

    if (clka'event and clka = '1') then
      if (ena = '1') then
        doa <= ram(to_integer(unsigned(addra)));
      end if;
    end if;

  end process;

  process (clkb) is

    variable readb : std_logic_vector(31 downto 0);

  begin

    if (clkb'event and clkb = '1') then
      if (enb = '1') then
        if (web(3) = '1') then
          ram(to_integer(unsigned(addrb & '0')))(15 downto 8) <= dib(31 downto 24);
        end if;
        if (web(2) = '1') then
          ram(to_integer(unsigned(addrb & '0')))(7 downto 0) <= dib(23 downto 16);
        end if;
        if (web(1) = '1') then
          ram(to_integer(unsigned(addrb & '1')))(15 downto 8) <= dib(15 downto 8);
        end if;
        if (web(0) = '1') then
          ram(to_integer(unsigned(addrb & '1')))(7 downto 0) <= dib(7 downto 0);
        end if;
        readb(31 downto 16) := ram(to_integer(unsigned(addrb & '0')));
        readb(15 downto 0)  := ram(to_integer(unsigned(addrb & '1')));
        dob                 <= readb;
      end if;
    end if;

  end process;

end architecture behavioral;
