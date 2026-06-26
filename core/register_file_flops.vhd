-- Assuming we will infer flops for the register values, this architecture uses
-- a single bank array and no separate reg0 storage.
architecture flops of register_file is
  constant ZERO_ADDR : addr_t := (others => '0');

  type ram_type is array(0 to NUM_REGS - 1) of data_t;
  signal bank : ram_type;

  signal ex_pipes : ex_pipeline_t;
  signal wb_pipe : reg_pipe_t;

begin
  wb_pipe.en <= we_wb;
  wb_pipe.addr <= w_addr_wb;
  wb_pipe.data <= din_wb;

  ex_pipes(0).en <= we_ex;
  ex_pipes(0).addr <= w_addr_ex;
  ex_pipes(0).data <= din_ex;

  dout_a <= read_with_forwarding(addr_ra, bank(to_reg_index(addr_ra)), wb_pipe, ex_pipes);
  dout_b <= read_with_forwarding(addr_rb, bank(to_reg_index(addr_rb)), wb_pipe, ex_pipes);
  -- Bank-aware R0 read: bank holds the remapped R0 (writes use the remapped
  -- index), so reading bank(addr_r0) follows SR.RB.
  -- NOTE: this arch keeps the `generate` split because its bindings (ASIC, via
  -- cpu_asic.vhd) fold it cleanly on the generic yosys backend. The two_bank
  -- arch (ECP5 j2 binding) instead uses a const-foldable `r0_addr <= addr_r0
  -- when BANKED else ZERO_ADDR` form because synth_ecp5/abc9 does NOT fold this
  -- `generate` (it left +418 LUT4; see register_file_two_bank.vhd). If flops is
  -- ever bound for a synth_ecp5 target, switch it to that foldable form too.
  banked_r0: if BANKED generate
    dout_0 <= read_with_forwarding(addr_r0, bank(to_reg_index(addr_r0)), wb_pipe, ex_pipes);
  end generate banked_r0;
  unbanked_r0: if not BANKED generate
    -- J1/J2: original bank-0 R0 read, no addr_r0 path (byte-identical netlist).
    dout_0 <= read_with_forwarding(ZERO_ADDR, bank(0), wb_pipe, ex_pipes);
  end generate unbanked_r0;

  process (clk, rst, ce, wb_pipe, ex_pipes)
    variable addr : integer;
    variable data : data_t;
  begin
    if rst = '1' then
      addr := 0;
      data := (others => '0');
      wr_data_o <= (others => '0');
      bank <= (others => (others => '0'));
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
        bank(addr) <= data;
      end if;
      ex_pipes(2) <= ex_pipes(1);
      ex_pipes(1) <= ex_pipes(0);
    end if;
  end process;
end architecture;
