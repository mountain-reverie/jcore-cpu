-- J1 synthesis configuration (no hardware multiplier).
-- Identical to cpu_synth_direct (synth/cpu_synth_config.vhd) EXCEPT u_mult
-- binds mult(seq) -- the sequential shift-add multiplier from core/mult_seq.vhd
-- -- instead of the 31x16 array multiplier mult(stru).  The result is a
-- significantly smaller design: the sequential unit trades latency for area.
configuration cpu_synth_j1 of cpu is
  for stru
    for u_mult : mult
      use entity work.mult(seq);
    end for;
    for u_decode : decode
      use configuration work.cpu_decode_direct;
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
