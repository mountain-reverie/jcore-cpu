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
  -- cpu_decode_direct but sets decode_core's MMU_ARCH generic true, keeping the
  -- TLB miss/protection exception dispatch. Lives here (hand-written) rather than
  -- in the generated decode_table_direct_config.vhd. Synth builds do not compile
  -- cpu_config.vhd and use plain cpu_decode_direct (MMU_ARCH defaults false), so
  -- the TLB decode logic is pruned from the non-MMU j1/j2 critical path.
  use work.decode_pack.all;
configuration cpu_decode_direct_mmu of decode is
  for arch
    for core : decode_core
      use entity work.decode_core(arch)
generic map (
  decode_type => DIRECT,
  reset_vector => DEC_CORE_RESET,
  mmu_arch => true
);
    end for;
    for table : decode_table
      use entity work.decode_table(direct_logic);
    end for;
  end for;
end configuration;

-- SH2A-enabled decode binding (used by cpu_j2a below). Mirrors
-- cpu_decode_direct_mmu but sets decode_core's SH2A_ARCH generic true instead
-- of MMU_ARCH. Task 1.1 is inert plumbing only, so SH2A_ARCH has no gated
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
  mmu_arch => true,
  sh2a_arch => true
);
    end for;
    for table : decode_table
      use entity work.decode_table(direct_logic);
    end for;
  end for;
end configuration;

configuration cpu_sim of cpu is
  for stru
    for u_decode : decode
-- MMU-enabled decode binding: cpu_sim is the functional build that runs
-- with the cpu's MMU_ARCH generic = true (set by the testbench), so the
-- decoder must keep the TLB exception dispatch. Synth/non-MMU configs use
-- plain cpu_decode_direct (MMU_ARCH defaults false, TLB logic pruned).
      use configuration work.cpu_decode_direct_mmu;
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

-- CONFIG_SH2A_ARCH functional sim variant of cpu_sim: identical to cpu_sim
-- except u_decode binds cpu_decode_direct_mmu_sh2a (decode_core SH2A_ARCH=true)
-- so the ext_word capture register is elaborated. Selected by sim/cpu_tb.vhd
-- when CONFIG_SH2A_ARCH=1; the cpu-level SH2A_ARCH generic (set in the same
-- testbench) drives the datapath side.
configuration cpu_sim_sh2a of cpu is
  for stru
    for u_decode : decode
      use configuration work.cpu_decode_direct_mmu_sh2a;
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

-- J1/iCESugar DSP-ALU VERIFICATION-ONLY variant of cpu_sim: identical to
-- cpu_sim above except u_datapath's DSP_ALU generic is true, so
-- core/dsp_arith.vhd (SB_MAC16-offloaded add/sub) is elaborated and
-- exercised in place of the plain arith_unit call. Selected only when
-- sim/Makefile's CONFIG_DSP_ALU=1 (see sim/cpu_tb.vhd); the default
-- CONFIG_DSP_ALU=0 keeps using cpu_sim, so the standard sim regression is
-- completely unaffected by this prototype.
configuration cpu_sim_dsp_alu of cpu is
  for stru
    for u_decode : decode
      use configuration work.cpu_decode_direct_mmu;
    end for;
    for u_datapath : datapath
      use entity work.datapath(stru)
generic map (
  dsp_alu => true
);
      for stru
        for u_regfile : register_file
          use entity work.register_file(two_bank);
        end for;
        for u_shifter : shifter
          use entity work.shifter(comb);
        end for;
        for dsp_alu_gen
          for u_dsp_arith : dsp_arith
            use entity work.dsp_arith(ice40dsp);
          end for;
        end for;
      end for;
    end for;
  end for;
end configuration;

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

-- J4 placeholder == J2; SH-4 units (privilege/TLB/L2) attach here later
-- without touching J2.  Because the J4 decoder is byte-identical to J2 today,
-- cpu_j4 binds the existing `decode` entity -- no separate decoder needed yet.
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
