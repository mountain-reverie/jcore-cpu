configuration cpu_j1 of cpu is
  for stru
    for u_mult : mult use entity work.mult(seq); end for;
    for u_decode : decode use configuration work.cpu_decode_rom; end for;
    for u_datapath : datapath use entity work.datapath(stru)
generic map (
  early_regfile_read => true
);
      for stru
        for u_regfile : register_file use entity work.register_file(ebr); end for;
        for u_shifter : shifter use entity work.shifter(seq); end for;
      end for;
    end for;
  end for;
end configuration;
