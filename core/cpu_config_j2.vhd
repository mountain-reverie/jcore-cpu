configuration cpu_j2 of cpu is
  for stru
    for u_mult : mult use entity work.mult(stru); end for;
    for u_decode : decode use configuration work.cpu_decode_direct; end for;
    for u_datapath : datapath use entity work.datapath(stru);
      for stru
        for u_regfile : register_file use entity work.register_file(two_bank); end for;
        for u_shifter : shifter use entity work.shifter(comb); end for;
      end for;
    end for;
  end for;
end configuration;

-- SH-2A ("J2A") variant: mirrors cpu_j2 but binds the SH2A-enabled decode
-- configuration and sets the cpu-level SH2A_ARCH generic true. Task 1.1 is
-- inert plumbing only, so this build is behaviorally identical to cpu_j2.
configuration cpu_j2a of cpu is
  for stru
    for u_mult : mult use entity work.mult(stru); end for;
    for u_decode : decode use configuration work.cpu_decode_direct_sh2a; end for;
    for u_datapath : datapath use entity work.datapath(stru)
generic map (
  sh2a_arch => true
);
      for stru
        for u_regfile : register_file use entity work.register_file(two_bank); end for;
        for u_shifter : shifter use entity work.shifter(comb); end for;
      end for;
    end for;
  end for;
end configuration;
