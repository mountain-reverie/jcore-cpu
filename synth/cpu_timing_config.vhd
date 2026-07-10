-- Per-variant configurations of the cpu_timing_top representative-Fmax harness.
-- Each binds the harness's u_cpu instance to the matching cpu synth configuration
-- so the ECP5 representative Fmax measured by `cpu_synth.sh timing` reflects the
-- selected variant (J2 baseline / J1 sequential multiplier / J4 placeholder),
-- not always J2. cpu_synth.sh elaborates cpu_timing_<variant>.
configuration cpu_timing_j2 of cpu_timing_top is
  for timing
    for u_cpu : cpu use configuration work.cpu_synth_direct; end for;
  end for;
end configuration;

configuration cpu_timing_j1 of cpu_timing_top is
  for timing
    for u_cpu : cpu use configuration work.cpu_synth_j1
      generic map(COPRO_DECODE => false);
    end for;
  end for;
end configuration;

-- iCE40-only: binds cpu_synth_j1_dsp (mult(ice40dsp) + DSP_ALU=>true
-- dsp_arith) instead of the LUT-only cpu_synth_j1. Used by `cpu_synth.sh
-- ice40` (the up5k fit gauge) so the default up5k J1 build spends its free
-- SB_MAC16 DSP blocks; NOT used by the `timing`/`ecp5`/`asic` backends since
-- ECP5/ASIC have no SB_MAC16 equivalent.
configuration cpu_timing_j1_dsp of cpu_timing_top is
  for timing
    for u_cpu : cpu use configuration work.cpu_synth_j1_dsp
      generic map(COPRO_DECODE => false);
    end for;
  end for;
end configuration;

configuration cpu_timing_j4 of cpu_timing_top is
  for timing
    for u_cpu : cpu use configuration work.cpu_synth_j4
      generic map(PRIV_ARCH => true);
    end for;
  end for;
end configuration;

configuration cpu_timing_j2a of cpu_timing_top is
  for timing
    for u_cpu : cpu use configuration work.cpu_synth_j2a
      generic map (SH2A_ARCH => true);
    end for;
  end for;
end configuration;
