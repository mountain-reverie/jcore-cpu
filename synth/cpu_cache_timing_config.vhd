-- Per-variant configurations of the cpu_cache_timing_top harness. Each binds the
-- harness's u_cpu to the matching cpu synth configuration (J2 baseline / J4
-- placeholder) and binds u_icache/u_dcache to the fpga adapter configs (which
-- bind the inferred RAMs). The SAME_CLOCK generic flows from the harness generic
-- map (set by cpu_synth.sh per backend: true on ecp5, false on asic), not here.
-- cpu_synth.sh elaborates cpu_cache_timing_<variant>.
configuration cpu_cache_timing_j2 of cpu_cache_timing_top is
  for timing
    for u_cpu : cpu use configuration work.cpu_synth_direct; end for;
    for u_icache : icache_adapter use configuration work.icache_adapter_fpga; end for;
    for u_dcache : dcache_adapter use configuration work.dcache_adapter_fpga; end for;
  end for;
end configuration;

configuration cpu_cache_timing_j4 of cpu_cache_timing_top is
  for timing
    for u_cpu : cpu use configuration work.cpu_synth_j4; end for;
    for u_icache : icache_adapter use configuration work.icache_adapter_fpga; end for;
    for u_dcache : dcache_adapter use configuration work.dcache_adapter_fpga; end for;
  end for;
end configuration;

-- M0: J4+cache asic/ecp5 area build with PRIV_ARCH=true (real SH-4 privileged
-- datapath).  Identical to cpu_cache_timing_j4 except u_cpu uses cpu_synth_j4
-- with generic map(PRIV_ARCH => true), exactly as cpu_timing_j4 does for the
-- bare-cpu timing backend.  Used by cpu_synth.sh AREA_TOP for j4c asic/ecp5.
configuration cpu_cache_timing_j4_priv of cpu_cache_timing_top is
  for timing
    for u_cpu : cpu
      use configuration work.cpu_synth_j4
        generic map (PRIV_ARCH => true);
    end for;
    for u_icache : icache_adapter use configuration work.icache_adapter_fpga; end for;
    for u_dcache : dcache_adapter use configuration work.dcache_adapter_fpga; end for;
  end for;
end configuration;

-- M3: J4+cache asic/ecp5 area build with PRIV_ARCH=true AND MMU_ARCH=true (real
-- SH-4 MMU: TLB/CAM, D-store fault squash, MMU control-register file, VIPT seam).
-- Identical to cpu_cache_timing_j4_priv except u_cpu also sets MMU_ARCH => true,
-- so the MMU hardware is actually synthesized and timing-checked. Used by
-- cpu_synth.sh AREA_TOP for j4c asic/ecp5. Requires the J4 overlay decoder
-- (make -C decode generate-j4) which exposes the mmu_reg_* control signals.
configuration cpu_cache_timing_j4_priv_mmu of cpu_cache_timing_top is
  for timing
    for u_cpu : cpu
      use configuration work.cpu_synth_j4
        generic map (PRIV_ARCH => true, MMU_ARCH => true);
    end for;
    for u_icache : icache_adapter use configuration work.icache_adapter_fpga; end for;
    for u_dcache : dcache_adapter use configuration work.dcache_adapter_fpga; end for;
  end for;
end configuration;
