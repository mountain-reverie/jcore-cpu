configuration cpu_sim of cpu is
  for stru
    for u_decode : decode
-- MMU-enabled decode binding: cpu_sim is the functional build that runs
-- with the cpu's PRIV_ARCH generic = true (set by the testbench), so the
-- decoder must keep the TLB exception dispatch. Synth/non-MMU configs use
-- plain cpu_decode_direct (PRIV_ARCH defaults false, TLB logic pruned).
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

-- Decoder-symmetry sim variant of cpu_sim: identical to cpu_sim (MMU-enabled,
-- two-bank regfile, comb shifter) EXCEPT u_decode binds the ROM decoder
-- (cpu_decode_rom) instead of the direct one. Base J2 only -- the ROM
-- decoder cannot runtime-discriminate the ext_word of two-word SH-2A ops, so
-- this variant must never be used with SH2A_ARCH. Selected by sim/cpu_tb.vhd
-- when CONFIG_DECODE_ROM=1, to enforce that the direct and ROM decoders --
-- generated from the same microcode model -- stay behaviorally identical for
-- base instructions.
configuration cpu_sim_rom of cpu is
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
