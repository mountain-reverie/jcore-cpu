-- J1 synthesis configuration using the iCE40 SB_MAC16 DSP multiplier.
-- Identical to cpu_synth_j1 (synth/cpu_synth_j1_config.vhd) except u_mult binds
-- mult(ice40dsp) (core/mult_ice40dsp.vhd) instead of the sequential mult(seq):
-- the product moves from ~1200 LUT4 onto the iCE40 DSP blocks. ROM decode, the
-- EBR register file and the sequential shifter are unchanged.
configuration cpu_synth_j1_dsp of cpu is
  for stru
    for u_mult : mult
      use entity work.mult(ice40dsp);
    end for;
    for u_decode : decode
      use configuration work.cpu_decode_rom;
    end for;
    for u_datapath : datapath
      use entity work.datapath(stru)
        generic map (EARLY_REGFILE_READ => true);
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
