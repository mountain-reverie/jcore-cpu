configuration cpu_decode_direct_fpga of cpu is
  for stru
    for u_decode : decode
      use configuration work.cpu_decode_direct;
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

configuration cpu_decode_rom_fpga of cpu is
  for stru
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

  -- MMU-enabled decode binding (used by cpu_sim below). Mirrors the generated
  -- cpu_decode_direct but sets decode_core's PRIV_ARCH generic true, keeping the
  -- TLB miss/protection exception dispatch. Lives here (hand-written) rather than
  -- in the generated decode_table_direct_config.vhd. Synth builds do not compile
  -- cpu_config.vhd and use plain cpu_decode_direct (PRIV_ARCH defaults false), so
  -- the TLB decode logic is pruned from the non-MMU j1/j2 critical path.
  use work.decode_pack.all;
configuration cpu_decode_direct_mmu of decode is
  for arch
    for core : decode_core
      use entity work.decode_core(arch)
generic map (
  decode_type => DIRECT,
  reset_vector => DEC_CORE_RESET,
  priv_arch => true
);
    end for;
    for table : decode_table
      use entity work.decode_table(direct_logic);
    end for;
  end for;
end configuration;

-- SH2A-enabled decode binding (used by cpu_j2a below). Mirrors
-- cpu_decode_direct_mmu but sets decode_core's SH2A_ARCH generic true instead
-- of PRIV_ARCH. Task 1.1 is inert plumbing only, so SH2A_ARCH has no gated
-- logic yet; this configuration exists so later SH-2A tasks have a build
-- target to extend.
configuration cpu_decode_direct_sh2a of decode is
  for arch
    for core : decode_core
      use entity work.decode_core(arch)
generic map (
  decode_type => DIRECT,
  reset_vector => DEC_CORE_RESET,
  sh2a_arch => true
);
    end for;
    for table : decode_table
      use entity work.decode_table(direct_logic);
    end for;
  end for;
end configuration;

-- MMU+SH2A decode binding: like cpu_decode_direct_mmu but ALSO turns on
-- decode_core's SH2A_ARCH so the ext_word capture register is instantiated.
-- Used by cpu_sim_sh2a (the CONFIG_SH2A_ARCH functional sim, which is MMU-on
-- like cpu_sim). Without this, the cpu-level SH2A_ARCH generic reaches the
-- datapath but NOT decode_core (which is bound by configuration, not generic
-- map), leaving ext_word ungated.
configuration cpu_decode_direct_mmu_sh2a of decode is
  for arch
    for core : decode_core
      use entity work.decode_core(arch)
generic map (
  decode_type => DIRECT,
  reset_vector => DEC_CORE_RESET,
  priv_arch => true,
  sh2a_arch => true
);
    end for;
    for table : decode_table
      use entity work.decode_table(direct_logic);
    end for;
  end for;
end configuration;
