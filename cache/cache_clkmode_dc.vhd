-- Cache clock mode: DUAL-clock (ASIC, clk125 != clk200). Selects the original
-- transparent-latch CDC phase elements. One of cache_clkmode_{sc,dc}.vhd is
-- analyzed per build; only the analyzed one defines `package cache_clkmode`.
package cache_clkmode is

  constant cache_same_clock : boolean := false;

end package cache_clkmode;
