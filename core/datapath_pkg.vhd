library ieee;
use ieee.std_logic_1164.all;

use work.cpu2j0_pack.all;
use work.decode_pack.all;
use work.cpu2j0_components_pack.all;
use work.mult_pkg.all;

package datapath_pack is

   -- SR bit Positions
   constant T   : integer range 0 to 30 := 0;
   constant S   : integer range 0 to 30 := 1;
   constant I0  : integer range 0 to 30 := 4;
   constant I1  : integer range 0 to 30 := 5;
   constant I2  : integer range 0 to 30 := 6;
   constant I3  : integer range 0 to 30 := 7;
   constant Q   : integer range 0 to 30 := 8;
   constant M   : integer range 0 to 30 := 9;
   constant BL  : integer range 0 to 30 := 28;
   constant RB  : integer range 0 to 30 := 29;
   constant MD  : integer range 0 to 30 := 30;

   component datapath is
     generic (
       PRIV_ARCH : boolean := false;
       EARLY_REGFILE_READ : boolean := false );
     port (
      clk         : in  std_logic;
      rst         : in  std_logic;
      debug       : in  std_logic;
      enter_debug : out std_logic;
      slot        : out std_logic;
      reg         : in  reg_ctrl_t;
      func        : in  func_ctrl_t;
      sr_ctrl     : in  sr_ctrl_t;
      mac         : in  mac_ctrl_t;
      mem         : in  mem_ctrl_t;
      instr       : in  instr_ctrl_t;
      pc_ctrl     : in  pc_ctrl_t;
      buses       : in  buses_ctrl_t;
      coproc      : in coproc_ctrl_t;
      db_lock     : out std_logic;
      db_o        : out cpu_data_o_t;
      db_i        : in  cpu_data_i_t;
      inst_o      : out cpu_instruction_o_t;
      inst_i      : in  cpu_instruction_i_t;
      debug_o     : out cpu_debug_o_t;
      debug_i     : in  cpu_debug_i_t;
      macin1      : out std_logic_vector(31 downto 0);
      macin2      : out std_logic_vector(31 downto 0);
      mach        : in std_logic_vector(31 downto 0);
      macl        : in std_logic_vector(31 downto 0);
      -- J1: high while mult(seq) iterates -> stretch the slot. '0' for mult(stru).
      mult_stall  : in std_logic;
      mac_s       : out std_logic;
      t_bcc       : out std_logic;
      ibit        : out std_logic_vector(3 downto 0);
      if_dr       : out std_logic_vector(15 downto 0);
      if_stall    : out std_logic;
      mask_int    : out std_logic;
      illegal_delay_slot : out std_logic;
      illegal_instr : out std_logic;
      copreg      : in std_logic_vector(7 downto 0);
      cop_i       : in cop_i_t;
      cop_o       : out cop_o_t;
      priv_o      : out cpu_priv_o_t := NULL_PRIV_O);  -- SH-4 EXPEVT/INTEVT/TRA (J4)
   end component datapath;
end package;
