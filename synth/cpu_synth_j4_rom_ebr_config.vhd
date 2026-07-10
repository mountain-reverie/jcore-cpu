-- J4 synth, ROM decoder, FPGA-optimised register file variant.
--
-- Identical to cpu_synth_j4_rom EXCEPT the register file lives in ECP5 block RAM
-- (register_file(ebr)) instead of ~1.4k LUT4 of distributed RAM. register_file
-- (ebr) supports BANKED (J4/PRIV_ARCH) via its banked_r0 branch, and requires
-- the datapath's EARLY_REGFILE_READ (its block-RAM read is clocked on the rising
-- edge from the one-cycle-early addresses -- same contract as the J1 cpu_j1
-- config).
--
-- Used for the FPGA-optimised core (core0) of the asymmetric dual: core0 binds
-- this config (cells reclaimed, less congestion), while core1 binds
-- cpu_synth_j4_rom (register_file(two_bank)) to keep validating the portable /
-- ASIC-representative register-file logic on the FPGA -- mirroring the turtle
-- board's per-core rodimix split.
configuration cpu_synth_j4_rom_ebr of cpu is
  for stru
    for u_mult : mult
      use entity work.mult(stru);
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
          use entity work.shifter(comb);
        end for;
      end for;
    end for;
  end for;
end configuration;
