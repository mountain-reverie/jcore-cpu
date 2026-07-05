-- J1 synthesis configuration using the iCE40 SB_MAC16 DSP multiplier.
-- Identical to cpu_synth_j1 (synth/cpu_synth_j1_config.vhd) except u_mult binds
-- mult(ice40dsp) (core/mult_ice40dsp.vhd) instead of the sequential mult(seq):
-- the product moves from ~1200 LUT4 onto the iCE40 DSP blocks. ROM decode, the
-- EBR register file and the sequential shifter are unchanged.
--
-- DSP_ALU => true: J1-DSP-ALU (see core/dsp_arith.vhd and the DSP_ALU generic
-- on entity datapath, core/datapath.vhm). Offloads the 32-bit arith_unit
-- add/sub onto a third free SB_MAC16 DSP pair instead of LUT adder logic.
-- This is the default up5k J1 build (`cpu_synth.sh ice40`, via
-- cpu_timing_j1_dsp in synth/cpu_timing_config.vhd): the up5k has 8 free
-- SB_MAC16 blocks and no ASIC/ECP5 equivalent to trade away, so J1 spends
-- them here. Every other cpu_synth_* configuration (and cpu_sim) leaves
-- datapath's DSP_ALU at its default false, so J2/J4/ECP5-J1/ASIC-J1/sim
-- VHDL elaborates byte-identically to before this config existed.
configuration cpu_synth_j1_dsp of cpu is
  for stru
    for u_mult : mult
      use entity work.mult(ice40dsp);
    end for;
    for u_decode : decode
      use configuration work.cpu_decode_rom;
    end for;
    for u_datapath : datapath
      use entity work.datapath(stru)
        generic map (EARLY_REGFILE_READ => true, DSP_ALU => true);
      for stru
        for u_regfile : register_file
          use entity work.register_file(ebr);
        end for;
        for u_shifter : shifter
          use entity work.shifter(seq);
        end for;
        -- Explicit binding for the DSP_ALU=>true generate branch's dsp_arith
        -- instance. Needed so ghdl --syn-binding (targets/boards/icesugar/
        -- synth.sh) does not blackbox it: --syn-binding only blackboxes
        -- components left UNBOUND, and an explicit binding here also removes
        -- any dependency on dsp_arith.vhd's position in the synth filelist.
        for dsp_alu_gen
          for u_dsp_arith : dsp_arith
            use entity work.dsp_arith(ice40dsp);
          end for;
        end for;
      end for;
    end for;
  end for;
end configuration;
