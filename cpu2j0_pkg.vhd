-- Interface Library for the HS-2J0 CPU core

library ieee;
use ieee.std_logic_1164.all;

package cpu2j0_pack is 
   type cpu_instruction_o_t is record
      en   : std_logic;
      a    : std_logic_vector(31 downto 1);
      jp   : std_logic;
   end record;
   constant NULL_INST_O : cpu_instruction_o_t := (en => '0', a => (others => '0'), jp => '0');

   type cpu_instruction_i_t is record
      d    : std_logic_vector(15 downto 0);
      ack  : std_logic;
   end record;

   type cpu_data_o_t is record
      en   : std_logic;
      a    : std_logic_vector(31 downto 0);
      rd   : std_logic;
      wr   : std_logic;
      we   : std_logic_vector(3 downto 0);
      d    : std_logic_vector(31 downto 0);
   end record;
   constant NULL_DATA_O : cpu_data_o_t := (en => '0', a => (others => '0'), rd => '0', wr => '0', we => "0000", d => (others => '0'));

   type cpu_data_i_t is record
      d    : std_logic_vector(31 downto 0);
      ack  : std_logic;
   end record;

   type cpu_debug_o_t is record
      ack  : std_logic;
      d    : std_logic_vector(31 downto 0);
      rdy  : std_logic;
   end record;

   -- TLB output from cpu to SoC cache wrappers (J4+MMU_ARCH).
   -- Carries the PA tag (PA[27:13] = 15 bits, matches CACHE_PA_TAG_WIDTH), the
   -- AT-translated flag, and the PTE C-bit (cacheable) for both I-cache and
   -- D-cache ports. All-zero / at='0' / c='0' when MMU_ARCH=false.
   type cpu_mmu_o_t is record
      i_pa_tag : std_logic_vector(14 downto 0);  -- PA[27:13], 15 b (matches CACHE_PA_TAG_WIDTH)
      i_at     : std_logic;
      i_c      : std_logic;                       -- I-side PTE C-bit
      d_pa_tag : std_logic_vector(14 downto 0);
      d_at     : std_logic;
      d_c      : std_logic;                       -- D-side PTE C-bit
   end record;
   constant NULL_MMU_O : cpu_mmu_o_t :=
     (i_pa_tag => (others => '0'), i_at => '0', i_c => '0',
      d_pa_tag => (others => '0'), d_at => '0', d_c => '0');

   -- SH-4 exception-cause export (J4). All zero on a non-PRIV_ARCH build; the
   -- PM3-SoC companion maps these as P4 MMIO. Left open on non-J4 boards.
   type cpu_priv_o_t is record
      expevt : std_logic_vector(11 downto 0);
      intevt : std_logic_vector(11 downto 0);
      tra    : std_logic_vector(9 downto 0);
   end record;
   constant NULL_PRIV_O : cpu_priv_o_t := (others => (others => '0'));

   -- External restartable page fault (PAGE_FAULT_ARCH; no MMU/PRIV). Driven by
   -- SoC bus glue during the faulting access cycle: PF_IFETCH -> restart at the
   -- faulting fetch PC (like IMISS); PF_DREAD -> restart the faulting PC-relative
   -- load via the datapath ma_pc latch (like DMISS_R). Tied inert
   -- (NULL_PAGE_FAULT_I) when PAGE_FAULT_ARCH is false, so builds are unchanged.
   type page_fault_kind_t is (PF_IFETCH, PF_DREAD);
   type cpu_page_fault_i_t is record
      en   : std_logic;
      kind : page_fault_kind_t;
   end record;
   constant NULL_PAGE_FAULT_I : cpu_page_fault_i_t := (en => '0', kind => PF_IFETCH);

   type cpu_debug_cmd_t is (BREAK, STEP, INSERT, CONTINUE);

   type cpu_debug_i_t is record
      en   : std_logic;
      cmd  : cpu_debug_cmd_t;
      ir   : std_logic_vector(15 downto 0);
      d    : std_logic_vector(31 downto 0);
      d_en : std_logic;
   end record;
   constant CPU_DEBUG_NOP : cpu_debug_i_t := (en => '0', cmd => BREAK, ir => (others => '0'), d => (others => '0'), d_en => '0');

   type cpu_event_cmd_t is (INTERRUPT, ERROR, BREAK, RESET_CPU);

   type cpu_event_i_t is record
      en   : std_logic;
      cmd  : cpu_event_cmd_t;
      vec  : std_logic_vector(7 downto 0);
      msk  : std_logic;
      lvl  : std_logic_vector(3 downto 0);
   end record;
   constant NULL_CPU_EVENT_I : cpu_event_i_t := (en => '0',
                                                 cmd => INTERRUPT,
                                                 vec => (others => '0'),
                                                 msk => '0',
                                                 lvl => (others => '1'));

   type cpu_event_o_t is record
      ack  : std_logic;
      lvl  : std_logic_vector(3 downto 0);
      slp  : std_logic;
      dbg  : std_logic;
   end record;

   type cop_o_t is record
      d    : std_logic_vector(31 downto 0);
      rna  : std_logic_vector( 3 downto 0);
      rnb  : std_logic_vector( 3 downto 0);
      op   : std_logic_vector( 4 downto 0);
      en   : std_logic;
      stallcp : std_logic;
   end record;
   constant NULL_COPR_O : cop_o_t := ( d    => (others => '0'),
      rna  => (others => '0'),
      rnb  => (others => '0'),
      op   => (others => '0'),
      en   =>            '0' ,
      stallcp =>         '0'   );

   type cop_i_t is record
     d   : std_logic_vector(31 downto 0);
     ack : std_logic;
     t   : std_logic;
     exc : std_logic;
   end record;
   constant NULL_COPR_I : cop_i_t := ( d   => (others => '0'),
     ack => '1', t => '0', exc => '0');

   component cpu is generic (
      COPRO_DECODE    : boolean := true;
      PRIV_ARCH       : boolean := false;
      MMU_ARCH        : boolean := false;
      PAGE_FAULT_ARCH : boolean := false);
     port (
      clk          : in  std_logic;
      rst          : in  std_logic;
      db_o         : out cpu_data_o_t;
      db_lock      : out std_logic;
      db_i         : in  cpu_data_i_t;
      inst_o       : out cpu_instruction_o_t;
      inst_i       : in  cpu_instruction_i_t;
      debug_o      : out cpu_debug_o_t;
      debug_i      : in  cpu_debug_i_t;
      event_o      : out cpu_event_o_t;
      event_i      : in  cpu_event_i_t;
      cop_o        : out cop_o_t;
      cop_i        : in  cop_i_t;
      priv_o       : out cpu_priv_o_t := NULL_PRIV_O;
      mmu_o        : out cpu_mmu_o_t := NULL_MMU_O;
      page_fault_i : in  cpu_page_fault_i_t := NULL_PAGE_FAULT_I);
   end component cpu;

   function loopback_bus(b : cpu_data_o_t) return cpu_data_i_t;
end cpu2j0_pack;

package body cpu2j0_pack is
   function loopback_bus(b : cpu_data_o_t) return cpu_data_i_t is
   variable r : cpu_data_i_t;
   begin
      r.ack := b.en;
      r.d := (others => '0');
      return r;
   end function loopback_bus;
end cpu2j0_pack;
