-- Synthesis-only timing harness for the cpu core.
--
-- The bare `cpu` entity exposes ~348 ports as top-level IO. Synthesized alone
-- on a large sparse ECP5, those pads scatter across the die and inflate routing,
-- so the reported Fmax is dominated by a placement artifact rather than the
-- core's true register->register timing.
--
-- This wrapper collapses the boundary to 4 real IO (clk, rst, ti, to): every
-- cpu input is driven from a registered scramble word and every cpu output is
-- folded back into it, so (a) nothing is optimized to a constant, (b) the whole
-- core is preserved, and (c) nextpnr can place the core compactly and report the
-- true register->core->register Fmax. It is NOT a functional model.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu2j0_pack.all;

entity cpu_timing_top is
  port ( clk : in  std_logic;
         rst : in  std_logic;
         ti  : in  std_logic;     -- serial entropy in (keeps inputs non-constant)
         sout : out std_logic );   -- serial reduction out (keeps outputs observed)
end entity;

architecture timing of cpu_timing_top is
  -- pad/normalize any vector to 32 bits (zero-extended)
  function pad32(v : std_logic_vector) return std_logic_vector is
    variable vv : std_logic_vector(v'length-1 downto 0) := v;
    variable r  : std_logic_vector(31 downto 0) := (others => '0');
  begin
    r(vv'high downto 0) := vv;
    return r;
  end function;

  signal acc : std_logic_vector(31 downto 0);

  -- cpu outputs
  signal db_o    : cpu_data_o_t;
  signal db_lock : std_logic;
  signal inst_o  : cpu_instruction_o_t;
  signal debug_o : cpu_debug_o_t;
  signal event_o : cpu_event_o_t;
  signal cop_o   : cop_o_t;

  -- cpu inputs (combinationally derived from the registered acc word)
  signal db_i    : cpu_data_i_t;
  signal inst_i  : cpu_instruction_i_t;
  signal debug_i : cpu_debug_i_t;
  signal event_i : cpu_event_i_t;
  signal cop_i   : cop_i_t;

  -- bind the core instance to the synthesis configuration (binds u_mult etc.)
  for u_cpu : cpu use configuration work.cpu_synth_direct;
begin
  -- Drive every cpu input field from acc so none fold to a constant.
  db_i.d    <= acc;
  db_i.ack  <= acc(0);
  inst_i.d  <= acc(15 downto 0);
  inst_i.ack<= acc(1);
  debug_i.en   <= acc(2);
  debug_i.cmd  <= cpu_debug_cmd_t'val(to_integer(unsigned(acc(4 downto 3))));
  debug_i.ir   <= acc(15 downto 0);
  debug_i.d    <= acc;
  debug_i.d_en <= acc(5);
  event_i.en   <= acc(6);
  event_i.cmd  <= cpu_event_cmd_t'val(to_integer(unsigned(acc(8 downto 7))));
  event_i.vec  <= acc(7 downto 0);
  event_i.msk  <= acc(9);
  event_i.lvl  <= acc(13 downto 10);
  cop_i.d   <= acc;
  cop_i.ack <= acc(14);
  cop_i.t   <= acc(15);
  cop_i.exc <= acc(16);

  u_cpu : cpu
    port map ( clk => clk, rst => rst,
               db_o => db_o, db_lock => db_lock, db_i => db_i,
               inst_o => inst_o, inst_i => inst_i,
               debug_o => debug_o, debug_i => debug_i,
               event_o => event_o, event_i => event_i,
               cop_o => cop_o, cop_i => cop_i );

  -- Fold ALL cpu outputs into acc each cycle (every output bit influences acc,
  -- so the whole core is preserved), shifting in ti for liveness.
  process(clk) begin
    if rising_edge(clk) then
      if rst = '1' then
        acc <= (others => '0');
      else
        acc <= (acc(30 downto 0) & ti)
             xor db_o.a xor db_o.d xor debug_o.d xor cop_o.d
             xor pad32(inst_o.a)
             xor pad32(db_o.we) xor pad32(event_o.lvl)
             xor pad32(cop_o.rna) xor pad32(cop_o.rnb) xor pad32(cop_o.op)
             xor pad32(db_o.en & db_o.rd & db_o.wr & db_lock
                       & inst_o.en & inst_o.jp
                       & debug_o.ack & debug_o.rdy
                       & event_o.ack & event_o.slp & event_o.dbg
                       & cop_o.en & cop_o.stallcp);
      end if;
    end if;
  end process;

  sout <= acc(31);
end architecture;
