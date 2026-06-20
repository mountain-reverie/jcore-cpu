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

configuration cpu_timing_j4 of cpu_timing_top is
  for timing
    for u_cpu : cpu use configuration work.cpu_synth_j4
      generic map(PRIV_ARCH => true);
    end for;
  end for;
end configuration;
