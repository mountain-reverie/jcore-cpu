-- J4 synth placeholder == J2.
-- Identical to cpu_synth_direct (synth/cpu_synth_config.vhd) with u_mult
-- bound to mult(stru) (the 31x16 array multiplier).  SH-4 privilege/TLB/L2
-- units will hook in here once the J4 overlay is non-empty.
configuration cpu_synth_j4 of cpu is
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
