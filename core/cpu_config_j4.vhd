-- J4: the multi-tenant variant -- privileged architecture + MMU (PRIV_ARCH
-- implies MMU; there is no separate knob). Its decoder is NOT the J2 decoder:
-- decode tables are regenerated with the sh4 overlay into DECODE_GEN_DIR (see
-- Makefile.inc), which adds LDTLB, the PTEH/PTEL/ASIDR LDC/STC family, the
-- R*_BANK moves and the exception ops.
configuration cpu_j4 of cpu is
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
