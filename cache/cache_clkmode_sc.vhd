-- Cache clock mode: SINGLE-clock (FPGA, clk125=clk200). Selects the cache CDC
-- phase elements' synthesizable negedge-FF form. One of cache_clkmode_{sc,dc}.vhd
-- is analyzed per build (like the clkgen sim/ecp5 arch split); only the analyzed
-- one defines `package cache_clkmode`. ghdl bakes the constant into the cache's
-- generate statements (no generic, so no ghdl-yosys parametric-module friction).
package cache_clkmode is
  constant CACHE_SAME_CLOCK : boolean := true;
end package;
