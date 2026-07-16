-- Minimal `config` package for the cpu+cache synth variants (j2c/j4c). The cache
-- pulls in ddrc_cnt_pkg (via cache_pkg), which references work.config's
-- CFG_DDR_CK_CYCLE. The cache datapath does not depend on the exact value (the
-- ddr2 controller fsm is not part of the cpu+cache harness), so a nominal value
-- suffices. Only analyzed for the j2c/j4c (cpu+cache) synth variants.
package config is

  constant cfg_ddr_ck_cycle : integer := 20;

end package config;
