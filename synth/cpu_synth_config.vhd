-- Synthesis-only configuration of the cpu.
-- Identical to cpu_decode_direct_fpga (core/cpu_config.vhd) EXCEPT it adds the
-- explicit u_mult binding the committed FPGA configs omit. Without it, ghdl
-- default-binding leaves `mult` an unbound black box, which (a) drops the
-- multiplier from synthesis and (b) makes abc9 see false combinational loops.
-- Kept in synth/ so the committed configs stay untouched.
configuration cpu_synth_direct of cpu is
  for stru
    for u_mult : mult
      use entity work.mult(stru);
    end for;
    for u_decode : decode
      use configuration work.cpu_decode_direct;
    end for;
    for u_datapath : datapath
      use entity work.datapath(stru);
      for stru
        for u_regfile : register_file
          use entity work.register_file(two_bank);
        end for;
      end for;
    end for;
  end for;
end configuration;
