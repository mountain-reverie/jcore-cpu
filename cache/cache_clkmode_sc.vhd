-- Cache clock mode: SINGLE-clock (FPGA, clk125=clk200). Selects the cache CDC
-- phase elements' synthesizable POSEDGE-FF (full-cycle) form. One of
-- cache_clkmode_{sc,dc}.vhd is analyzed per build (like the clkgen sim/ecp5 arch
-- split); only the analyzed one defines `package cache_clkmode`. ghdl bakes the
-- constant into the cache's generate statements (no generic, so no ghdl-yosys
-- parametric-module friction).
--
-- CDC phase elements (bcen_value_halfcb0, bmen_value_halfcb2): the dual-clock
-- (_dc) form is a transparent latch giving a metastability-safe T/2 sample of
-- the other domain. With one clock net that hardening is vestigial, so this _sc
-- form clocks them on the POSEDGE (full cycle) instead of the negedge. That
-- removes the T/2 half-cycle timing path (the cache Fmax limiter on the ULX3S),
-- at the cost of +1 cycle latency per phase-element path: a cache MISS crosses
-- both dcache phase elements (cpu->mem request + mem->cpu critical word), so a
-- miss is +2 cycles vs the negedge form; a cache HIT is unaffected. Verified by
-- the dcache scoreboard (sim/cache_sim.sh sc): hit=2, cold-miss 10->12 cycles.
package cache_clkmode is

  constant cache_same_clock : boolean := true;

end package cache_clkmode;
