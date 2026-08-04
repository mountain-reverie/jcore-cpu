# cache_clkmode_{sc,dc} define `package cache_clkmode`; only one is analyzed
# per build (like the clkgen sim/ecp5 arch split). _sc (single-clock, FPGA) is
# the one every current build (sim + FPGA/ASIC boards) wants; it must precede
# dcache.vhd/dcache_ram.vhd/icache.vhd, which all reference the package.
$(VHDLS) += cache_clkmode_sc.vhd
$(VHDLS) += cache_pkg.vhd
$(VHDLS) += dcache.vhd
$(VHDLS) += dcache_ccl.vhd
$(VHDLS) += dcache_mcl.vhd
$(VHDLS) += dcache_ram.vhd
$(VHDLS) += dcache_adapter.vhd
# dcache_cacheable_mux directly instantiates entity work.dcache_adapter, so it
# must be analyzed after dcache_adapter.vhd.
$(VHDLS) += dcache_cacheable_mux.vhd
$(VHDLS) += icache_modereg.vhd
$(VHDLS) += icache_modereg_wsbu.vhd
$(VHDLS) += icache.vhd
$(VHDLS) += icache_ccl.vhd
$(VHDLS) += icache_mcl.vhd
$(VHDLS) += icache_ram.vhd
$(VHDLS) += icache_adapter.vhd
# icache_cacheable_mux directly instantiates entity work.icache_adapter, so it
# must be analyzed after icache_adapter.vhd.
$(VHDLS) += icache_cacheable_mux.vhd
