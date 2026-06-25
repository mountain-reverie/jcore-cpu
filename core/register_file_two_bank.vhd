architecture two_bank of register_file is
  constant ZERO_ADDR : addr_t := (others => '0');

  type ram_type is array(0 to NUM_REGS - 1) of data_t;
  signal bank_a, bank_b : ram_type;
  signal reg0 : data_t;

  signal ex_pipes : ex_pipeline_t;
  signal wb_pipe : reg_pipe_t;

begin
  wb_pipe.en <= we_wb;
  wb_pipe.addr <= w_addr_wb;
  wb_pipe.data <= din_wb;

  ex_pipes(0).en <= we_ex;
  ex_pipes(0).addr <= w_addr_ex;
  ex_pipes(0).data <= din_ex;

  dout_a <= read_with_forwarding(addr_ra, bank_a(to_reg_index(addr_ra)), wb_pipe, ex_pipes);
  dout_b <= read_with_forwarding(addr_rb, bank_b(to_reg_index(addr_rb)), wb_pipe, ex_pipes);
  -- Bank-aware R0 read. reg0 is a rising-edge flop tracking the bank-0 R0 (the
  -- common, RB=0 case), reset to 0 -- identical to register_file(ebr) -- so the
  -- bank-0 path is bit-identical to ebr (register_ebr_tap cross-check). When
  -- addr_r0 selects a non-zero (bank-1 R0) index under RB=1, read the remapped
  -- value straight from bank_a (the write side writes the remapped index), so
  -- the R0-banking fix is unchanged. Forwarding overlays in-flight EX/WB writes.
  banked_r0: if BANKED generate
    dout_0 <= read_with_forwarding(ZERO_ADDR, reg0, wb_pipe, ex_pipes)
                when to_reg_index(addr_r0) = 0
              else read_with_forwarding(addr_r0, bank_a(to_reg_index(addr_r0)), wb_pipe, ex_pipes);
  end generate banked_r0;
  unbanked_r0: if not BANKED generate
    -- J1/J2: original bank-0 R0 read, no addr_r0 path (byte-identical netlist).
    dout_0 <= read_with_forwarding(ZERO_ADDR, reg0, wb_pipe, ex_pipes);
  end generate unbanked_r0;
  
  process (clk, rst, ce, wb_pipe, ex_pipes)
    variable addr : integer;
    variable data : data_t;
  begin
    if rst = '1' then
      addr := 0;
      data := (others => '0');
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
        bank_a(addr) <= data;
        bank_b(addr) <= data;
        if (addr = 0) then
          reg0 <= data;
        end if;
      end if;
      ex_pipes(2) <= ex_pipes(1);
      ex_pipes(1) <= ex_pipes(0);
    end if;
  end process;
end architecture;
