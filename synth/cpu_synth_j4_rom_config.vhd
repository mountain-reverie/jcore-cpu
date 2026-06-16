-- J4 synth, ROM decoder variant (for the direct-vs-rom ECP5 measurement only).
configuration cpu_synth_j4_rom of cpu is
  for stru
    for u_mult : mult
      use entity work.mult(stru);
    end for;
    for u_decode : decode
      use configuration work.cpu_decode_rom;
    end for;
    for u_datapath : datapath
      use entity work.datapath(stru);
      for stru
        for u_regfile : register_file
          use entity work.register_file(two_bank);
        end for;
        for u_shifter : shifter
          use entity work.shifter(comb);
        end for;
      end for;
    end for;
  end for;
end configuration;
