-- iCE40 block-RAM (SB_RAM40_4K/EBR) register file for J1. The registers live in
-- synchronous-read block RAM instead of LUTs/flops -- the largest single LUT4
-- saving for the up5k fit. Same entity/interface as register_file(flops) and
-- register_file(two_bank): a drop-in J1 architecture.
--
-- The crux: iCE40 EBR has a REGISTERED (synchronous) read -- data appears one
-- clock after the address -- but the datapath reads the register file
-- COMBINATIONALLY within a slot. So the RAM read is clocked on the FALLING
-- edge: the read address is stable from the slot's rising edge, the falling
-- edge (half a clock later) latches the RAM output q, and q is valid for the
-- ALU before the next rising edge -- no pipeline change. This is exactly the
-- trick decode/decode_table_rom.vhd uses for the microcode ROM, which infers
-- EBR on iCE40.
--
-- Two RAM copies (ram_a, ram_b) give the two independent read ports from
-- single-read-port block RAMs. Register 0 keeps a flop (reg0) for its always-on
-- dout_0. Writes are single-ported and muxed exactly as in two_bank (the
-- decoder guarantees EX and WB never write the same cycle) and commit to BOTH
-- copies on the rising edge. read_with_forwarding overlays the current-cycle
-- pipeline writes, identical to the other archs.
library ieee;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

architecture ebr of register_file is
  constant ZERO_ADDR : addr_t := (others => '0');

  type ram_type is array(0 to NUM_REGS - 1) of data_t;
  signal ram_a, ram_b : ram_type;
  signal reg0 : data_t;

  -- Rising-edge-latched (full-cycle) RAM read outputs (the "bank data" for forwarding).
  signal q_a, q_b : data_t;

  -- Bias yosys toward SB_RAM40_4K/BRAM inference (ignored by GHDL simulation
  -- and by backends without block RAM, e.g. the generic ASIC flow).
  attribute ram_style : string;
  attribute ram_style of ram_a : signal is "block";
  attribute ram_style of ram_b : signal is "block";

  signal ex_pipes : ex_pipeline_t;
  signal wb_pipe : reg_pipe_t;
begin
  wb_pipe.en   <= we_wb;
  wb_pipe.addr <= w_addr_wb;
  wb_pipe.data <= din_wb;

  ex_pipes(0).en   <= we_ex;
  ex_pipes(0).addr <= w_addr_ex;
  ex_pipes(0).data <= din_ex;

  -- The falling-edge-latched RAM output is the committed register value;
  -- read_with_forwarding overlays the in-flight EX/WB pipeline writes on top,
  -- identical to register_file(flops)/two_bank.
  dout_a <= read_with_forwarding(addr_ra, q_a, wb_pipe, ex_pipes);
  dout_b <= read_with_forwarding(addr_rb, q_b, wb_pipe, ex_pipes);
  -- reg0 is a rising-edge flop (vs q_a/q_b's falling-edge latch) on purpose:
  -- R0's just-committed value is always served by the forwarding overlay, never
  -- read straight from reg0 in the same slot it is written, so the half-clock
  -- difference in when reg0 updates is never observable -- same result as q.
  dout_0 <= read_with_forwarding(ZERO_ADDR, reg0, wb_pipe, ex_pipes);

  -- Full-cycle read: clock the block-RAM read on the RISING edge using the
  -- one-cycle-early addresses, so q_a/q_b are valid at the START of the EX slot
  -- (a full period for the downstream ALU/mult/shifter), not just the falling-
  -- edge half. The early address (decode's ex.regnum_{x,y}) is the value
  -- addr_ra/addr_rb take one cycle later, so q matches the EX instruction.
  read_proc : process(clk)
  begin
    if rising_edge(clk) then
      q_a <= ram_a(to_reg_index(addr_ra_early));
      q_b <= ram_b(to_reg_index(addr_rb_early));
    end if;
  end process;

  -- Single muxed write on the rising edge, committed to both RAM copies (and
  -- reg0 for R0). Identical to register_file(two_bank).
  write_proc : process(clk, rst)
    variable addr : integer;
    variable data : data_t;
  begin
    if rst = '1' then
      wr_data_o <= (others => '0');
      reg0 <= (others => '0');
      ex_pipes(1) <= REG_PIPE_RESET;
      ex_pipes(2) <= REG_PIPE_RESET;
    elsif (rising_edge(clk) and ce = '1') then
      -- the decoder should never schedule a write to a register for both Z and
      -- W bus at the same time
      assert (wb_pipe.en and ex_pipes(2).en) = '0'
        report "Write clash detected" severity warning;

      addr := to_reg_index(wb_pipe.addr);
      data := wb_pipe.data;
      if (ex_pipes(2).en = '1') then
        addr := to_reg_index(ex_pipes(2).addr);
        data := ex_pipes(2).data;
      end if;
      wr_data_o <= (others => '0');
      if ((wb_pipe.en or ex_pipes(2).en) = '1') then
        wr_data_o <= data;
        ram_a(addr) <= data;
        ram_b(addr) <= data;
        if (addr = 0) then
          reg0 <= data;
        end if;
      end if;
      ex_pipes(2) <= ex_pipes(1);
      ex_pipes(1) <= ex_pipes(0);
    end if;
  end process;
end architecture;
