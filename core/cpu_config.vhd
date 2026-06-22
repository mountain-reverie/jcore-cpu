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
          MMU_ARCH => true);
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

configuration cpu_j1 of cpu is
  for stru
    for u_mult : mult use entity work.mult(seq); end for;
    for u_decode : decode use configuration work.cpu_decode_rom; end for;
    for u_datapath : datapath use entity work.datapath(stru)
      generic map (EARLY_REGFILE_READ => true);
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
