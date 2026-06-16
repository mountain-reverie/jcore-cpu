-- J1 synthesis configuration (no hardware multiplier).
-- Differs from cpu_synth_direct (synth/cpu_synth_config.vhd) in three ways:
--   * u_mult binds mult(seq) -- the sequential shift-add multiplier from
--     core/mult_seq.vhd -- instead of the 31x16 array multiplier mult(stru);
--   * u_decode binds the ROM-based decoder (cpu_decode_rom) instead of the
--     direct logic decoder -- it moves ~301 iCE40 LUT4 of decode logic into 5
--     EBR blocks (SB_RAM40_4KNR);
--   * u_regfile/u_shifter bind the EBR register file and sequential shifter.
-- The result is a significantly smaller design: the sequential units and the
-- ROM decoder trade latency / block RAM for LUT4 area.
configuration cpu_synth_j1 of cpu is
  for stru
    for u_mult : mult
      use entity work.mult(seq);
    end for;
    for u_decode : decode
      use configuration work.cpu_decode_rom;
    end for;
    for u_datapath : datapath
      use entity work.datapath(stru);
      for stru
        for u_regfile : register_file
          use entity work.register_file(ebr);
        end for;
        for u_shifter : shifter
          use entity work.shifter(seq);
        end for;
      end for;
    end for;
  end for;
end configuration;
