library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.cpu2j0_pack.all;

package cpu2j0_components_pack is

constant bits_exp : natural := 5;
constant bits     : natural := 2**bits_exp;

type arith_func_t is (ADD, SUB);
type arith_sr_func_t is (ZERO,
                         OVERUNDERFLOW,
                         UGRTER_EQ, SGRTER_EQ,
                         UGRTER, SGRTER,
                         DIV0S, DIV1);
type logic_func_t is (LOGIC_NOT, LOGIC_AND, LOGIC_OR, LOGIC_XOR);
type logic_sr_func_t is (ZERO, BYTE_EQ);
type shiftfunc_t is (LOGIC, ARITH, ROTATE, ROTC);
type alumanip_t is (SWAP_BYTE, SWAP_WORD, EXTEND_UBYTE, EXTEND_UWORD, EXTEND_SBYTE, EXTEND_SWORD, EXTRACT, SET_BIT_7);

type sr_t is record
   t, s, q, m : std_logic;
   int_mask : std_logic_vector(3 downto 0);
   md, rb, bl : std_logic;   -- SH-4 privileged-arch bits (MD=30, RB=29, BL=28)
end record;

-- SH-4 exception cause registers (J4). All zero on a non-PRIV_ARCH build.
type priv_reg_t is record
   expevt : std_logic_vector(11 downto 0);  -- general-exception code
   intevt : std_logic_vector(11 downto 0);  -- interrupt code
   tra    : std_logic_vector(9 downto 0);   -- TRAPA imm << 2
end record;
constant PRIV_REG_RESET : priv_reg_t := (others => (others => '0'));

-- SH-4 MMU control registers (J4 + MMU_ARCH). A dedicated flop block, NOT the
-- regfile: these are CSRs read/written broadside by the TLB/fault logic.
-- All-0 at reset (hardware-spec §9). M1 wires PTEH/PTEL/ASIDR to LDC/STC;
-- MMUCR/TEA/TTB exist (reset 0) but get their software path in M2 (P4 decode).
type mmu_reg_t is record
  pteh   : std_logic_vector(31 downto 0);
  ptel   : std_logic_vector(31 downto 0);
  asidr  : std_logic_vector(31 downto 0);
  mmucr  : std_logic_vector(31 downto 0);
  tea    : std_logic_vector(31 downto 0);
  ttb    : std_logic_vector(31 downto 0);
  -- TSB pointer assist (M5, hardware-spec §2.6-2.8). tsbbr/tsbcfg are MMIO
  -- config (0xFF000014/18); tsbptr is hardware-computed on every TLB miss and
  -- is read-only (STC TSBPTR,Rn / MMIO 0xFF00001C).
  tsbbr  : std_logic_vector(31 downto 0);
  tsbcfg : std_logic_vector(31 downto 0);
  tsbptr : std_logic_vector(31 downto 0);
end record;
constant MMU_REG_RESET : mmu_reg_t := (others => (others => '0'));

-- TLB entry and array types (MMU_ARCH). ppn is PA[31:10] = 22-bit PFN at 4 KB
-- granularity; i_pa_tag/d_pa_tag use ppn(27 downto 13) = PA[27:13] = 15 bits
-- (matches CACHE_PA_TAG_WIDTH for the 28-bit cache region).
type tlb_entry_t is record
  valid     : std_logic;
  global    : std_logic;
  used      : std_logic;
  vpn       : std_logic_vector(31 downto 12);
  asid_tag  : std_logic_vector(15 downto 0);
  page_mask : std_logic_vector(3 downto 0);
  ppn       : std_logic_vector(31 downto 10);
  w         : std_logic;
  x         : std_logic;
  u         : std_logic;
  d         : std_logic;
  c         : std_logic;
  stale     : std_logic;
end record;
constant TLB_ENTRY_RESET : tlb_entry_t := (
  valid => '0', global => '0', used => '0',
  vpn => (others => '0'), asid_tag => (others => '0'),
  page_mask => (others => '0'), ppn => (others => '0'),
  w => '0', x => '0', u => '0', d => '0', c => '0', stale => '0'
);
type tlb_array_t is array(0 to 31) of tlb_entry_t;

type tlb_exc_kind_t is (IMISS, DMISS_R, DMISS_W, IPROT, DPROT_R, DPROT_W);

-- if size becomes part of the bus, mem_size_t will move into cpu2j0_pack
type mem_size_t is (BYTE, WORD, LONG);

type debug_state_t is ( RUN, READY, AWAIT_IF, AWAIT_BREAK );

type bus_val_t is record
  en : std_logic;
  d  : std_logic_vector(bits-1 downto 0);
end record;

constant BUS_VAL_RESET : bus_val_t := ('0', (others => '0'));

type ybus_val_pipeline_t is array (2 downto 0) of bus_val_t;

type datapath_reg_t is record
   pc         : std_logic_vector(bits-1 downto 0);
   sr         : sr_t;
   priv       : priv_reg_t;   -- SH-4 EXPEVT/INTEVT/TRA (J4)
   mmu        : mmu_reg_t;   -- SH-4 MMU CSRs: PTEH/PTEL/ASIDR/MMUCR/TEA/TTB (J4+MMU_ARCH)
   -- High after TEA/PTEH have been captured for the current TLB-fault episode,
   -- so the capture happens once (on the first faulting cycle) and is not
   -- overwritten by a later cycle of the same fault. Needed for IMISS, where the
   -- I-fetch stream advances a word while the miss persists (J4+MMU_ARCH).
   tlb_exc_captured : std_logic;
   -- Faulting-instruction restart-PC capture (J4+MMU_ARCH). ma_pc shadows the
   -- architectural PC of the instruction that launches each data access (a fixed
   -- pipeline point, so the offset to the access's own instruction is constant
   -- regardless of how far the fetch pointer later runs ahead). On the first
   -- cycle of a D-side TLB fault ma_pc is latched into tlb_exc_pc and routed to
   -- the SPC computation, so RTE/LDTLB.R re-executes the faulting access even
   -- under back-to-back faults (where the frozen fetch PC's lead is variable).
   -- It is read onto xbus via SEL_TLBPC for the D-fault exception entry only
   -- (I-fetch faults keep SEL_PC / the live PC); the decoder scopes the use.
   ma_pc      : std_logic_vector(31 downto 0);
   tlb_exc_pc : std_logic_vector(31 downto 0);
   -- User SR captured at the first D-fault cycle, read onto ybus via SEL_TLBSR
   -- for the D-fault entry's SSR save. The shared SEL_EXCEPTION SSR slot reads
   -- the live SR, which under back-to-back faults can re-evaluate after this
   -- entry already set RB=1 -> SSR.RB=1 -> the handler's LDTLB.R/RTE resumes in
   -- bank 1 and user code reads uninitialised bank-1 registers. The captured
   -- value is stable across the stalled slot's re-evaluations.
   tlb_exc_sr : sr_t;
   -- Precise-exception squash (J4+MMU_ARCH). Set on the first cycle a D/I-side
   -- TLB fault is detected and held until the handler is entered (SR.RB=1). The
   -- faulting access stalls/redirects a slot late, so the instruction(s) issued
   -- behind the faulting one would otherwise commit their GPR writeback before
   -- the exception is taken -- corrupting a base register the restarted faulting
   -- access depends on (e.g. a store whose base was loaded two instructions
   -- earlier). While tlb_squash is high the GPR write-enables (we_ex/we_wb) are
   -- forced low, so no post-fault instruction retires -> a precise restart.
   tlb_squash : std_logic;
   mac_s      : std_logic;
   data_o_size: mem_size_t;
   data_o_lock: std_logic;
   data_o     : cpu_data_o_t;
   inst_o     : cpu_instruction_o_t;
   pc_inc     : std_logic_vector(31 downto 0);
   if_dr      : std_logic_vector(15 downto 0);
   if_dr_next : std_logic_vector(15 downto 0);
   illegal_delay_slot : std_logic;
   illegal_instr : std_logic;
   if_en      : std_logic;
   m_dr       : std_logic_vector(31 downto 0);
   m_dr_next  : std_logic_vector(31 downto 0);
   m_en       : std_logic;
   slot       : std_logic;
   -- pipelines the enter_debug signal to delay it so that single stepping
   -- instructions works and debug mode is re-entered after one instruction.
   -- The length of this depends on how many microcode lines there are in the
   -- break instruction after it has raised the debug control line.
   enter_debug: std_logic_vector(3 downto 0);
   old_debug : std_logic;
   stop_pc_inc : std_logic;
   debug_state: debug_state_t;
   debug_o    : cpu_debug_o_t;
   -- pipeline of inserted values to override y-bus. Values go in at 'left and
   -- move downto 'right
   ybus_override : ybus_val_pipeline_t;
end record;

constant DATAPATH_RESET : datapath_reg_t := (pc => (others => '0'), sr => (int_mask => "1111", md => '1', rb => '1', bl => '1', others => '0'), priv => PRIV_REG_RESET, mmu => MMU_REG_RESET, tlb_exc_captured => '0', ma_pc => (others => '0'), tlb_exc_pc => (others => '0'), tlb_exc_sr => (int_mask => "1111", md => '1', rb => '1', bl => '1', others => '0'), tlb_squash => '0', mac_s => '0', data_o_size => BYTE, data_o_lock => '0', data_o => NULL_DATA_O, inst_o => NULL_INST_O, pc_inc => (others => '0'), if_dr => (others => '0'), if_dr_next => (others => '0'), illegal_delay_slot => '0', illegal_instr => '0', if_en => '0', m_dr => (others => '0'), m_dr_next => (others => '0'), m_en => '0', slot => '1', enter_debug => (others => '0'), old_debug => '0', stop_pc_inc => '0', debug_state => RUN, debug_o => (ack => '0', d => (others => '0'), rdy => '0'), ybus_override => (others => BUS_VAL_RESET));

subtype regnum_t is std_logic_vector(4 downto 0);
component register_file is
  generic ( ADDR_WIDTH : integer; NUM_REGS : integer; REG_WIDTH : integer );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    ce      : in  std_logic;

    addr_ra : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    dout_a  : out std_logic_vector(REG_WIDTH-1 downto 0);
    addr_rb : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    dout_b  : out std_logic_vector(REG_WIDTH-1 downto 0);
    dout_0  : out std_logic_vector(REG_WIDTH-1 downto 0);
    -- Bank-remapped index for the dedicated R0 read port (dout_0); defaulted to
    -- bank-0 R0 so two_bank/flops/J1 instantiations are unchanged.
    addr_r0 : in  std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    -- One-cycle-early read addresses (J1 architecture(ebr) full-cycle read);
    -- defaulted so two_bank/flops instantiations need not drive them.
    addr_ra_early : in std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    addr_rb_early : in std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');

    we_wb     : in  std_logic;
    w_addr_wb : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    din_wb    : in  std_logic_vector(REG_WIDTH-1 downto 0);

    we_ex     : in  std_logic;
    w_addr_ex : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    din_ex    : in  std_logic_vector(REG_WIDTH-1 downto 0);

    wr_data_o : out std_logic_vector(REG_WIDTH-1 downto 0)
    );
end component register_file;

-- Adds or subtracts a and b with carry-in and carry-out. The carry-out
-- (borrow for subtraction) bit is in the left-most bit of the result, which is
-- one bit wider than the inputs
function arith_unit(
  a : std_logic_vector;
  b : std_logic_vector;
  func : arith_func_t;
  ci : std_logic)
  return std_logic_vector;

-- based on the input and output of the arith_unit, update the SR register
-- flags for different operations
function arith_update_sr(
  sr_in : sr_t;
  a_msb : std_logic;
  b_msb : std_logic;
  value : std_logic_vector;
  co_or_borrow : std_logic;
  arithfunc : arith_func_t;
  func : arith_sr_func_t)
  return sr_t;

-- Returns either the bitwise AND, OR or XOR of a and b or the NOT of b
function logic_unit(
  a : std_logic_vector;
  b : std_logic_vector;
  func : logic_func_t)
  return std_logic_vector;

-- based on the output of the logic_unit, update the SR register flags for
-- different operations
function logic_update_sr(
  sr_in : sr_t;
  value : std_logic_vector;
  func : logic_sr_func_t;
  constant byte_width : integer := 8)
  return sr_t;

function is_zero(a : std_logic_vector) return std_logic;

function bshifter(a,b : std_logic_vector; c : std_logic; ops : shiftfunc_t) return std_logic_vector;
function manip(x, y : std_logic_vector(31 downto 0); func : alumanip_t)
  return std_logic_vector;

component shifter is
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    start : in  std_logic;
    sel   : in  std_logic;
    a     : in  std_logic_vector(31 downto 0);
    b     : in  std_logic_vector(5 downto 0);
    t_in  : in  std_logic;
    op    : in  shiftfunc_t;
    y     : out std_logic_vector(31 downto 0);
    t_out : out std_logic;
    busy  : out std_logic);
end component shifter;
end package;

package body cpu2j0_components_pack is

  constant NO_WARNING: BOOLEAN := FALSE; -- default to emit warnings

function or_reduce(a : std_logic_vector) return std_logic is
  variable r : std_logic := '0';
begin
  for i in a'range loop
    r := r or a(i);
  end loop;
  return r;
end;

-- Like or_reduce, but doesn't not completely reduce to a single bit. Instead
-- it splits the input into bytes, reduces each, and returns a vector
function or_reduce_bytes(a : std_logic_vector; constant byte_width : integer)
  return std_logic_vector is
  constant num_bytes : integer := natural(floor(real(a'length) / real(byte_width)));
  variable r : std_logic_vector(num_bytes - 1 downto 0);
begin
  for i in r'range loop
    r(i) := or_reduce(a((i + 1) * byte_width - 1 downto i * byte_width));
  end loop;
  return r;
end;

function is_zero(a : std_logic_vector) return std_logic is
  variable r : std_logic := '0';
begin
  return not or_reduce(a);
end;

-- xor every bit in vector a by bit b
function xor_all(a : std_logic_vector; b : std_logic) return std_logic_vector is
  alias av : std_logic_vector(a'length - 1 downto 0) is a;
  variable bv : std_logic_vector(a'length - 1 downto 0) := (others => b);
begin
  return av xor bv;
end;

function to_bit(b: boolean) return std_logic is
begin
  if b then
    return '1';
  else
    return '0';
  end if;
end;

function arith_unit(
  a : std_logic_vector;
  b : std_logic_vector;
  func : arith_func_t;
  ci : std_logic)
return std_logic_vector is
  alias xa : std_logic_vector(a'length - 1 downto 0) is a;
  alias xb : std_logic_vector(b'length - 1 downto 0) is b;

  variable is_sub : std_logic;
  variable b2 : std_logic_vector(xb'range);
  variable sum : unsigned(a'length downto 0);
  variable carry_in : unsigned(a'length downto 0);
begin
  if a'length /= b'length then
    assert NO_WARNING
      report "arith_unit: Arg size mismatch. Returning 0"
      severity WARNING;
    sum := to_unsigned(0, sum'length);
    return std_logic_vector(sum);
  end if;
  is_sub := to_bit(func = SUB);
  -- if ADD, then r = A+B+ci
  -- if SUB, then r = A-B-ci = A+not(B)+1-ci

  -- Perform a subtraction by negating the B operand. Take the twos complement
  -- by first flipping the bits and then xor-ing the ci to implement the +1.
  b2 := xor_all(xb, is_sub);
  -- If is_sub=0, then ci behaves normally. If is_sub=1 then
  -- r = A+not(B)+1-ci = A+not(B)+1-1 = A+not(B) when ci = 1
  --                   = A+not(B)+1              when ci = 0
  -- Xor-ing the ci by is_sub gives the correct calculation.
  carry_in := (others => '0');
  carry_in(0) := is_sub xor ci;

  sum := ('0' & unsigned(xa)) + ('0' & unsigned(b2)) + carry_in;

  -- convert left-most bit to a borrow instead of carry out when doing a subtraction
  sum(sum'left) := sum(sum'left) xor is_sub;
  return std_logic_vector(sum);
end;

function logic_unit(
  a : std_logic_vector;
  b : std_logic_vector;
  func : logic_func_t)
return std_logic_vector is
  alias xa : std_logic_vector(a'length - 1 downto 0) is a;
  alias xb : std_logic_vector(b'length - 1 downto 0) is b;
  variable r : std_logic_vector(xa'range);
begin
  if a'length /= b'length then
    assert NO_WARNING
      report "logic_unit: Arg size mismatch. Returning 0"
      severity WARNING;
    r := (others => '0');
    return r;
  end if;
  case func is
    when LOGIC_NOT =>
      r := xor_all(xb, '1');
    when LOGIC_AND =>
      r := xa and xb;
    when LOGIC_OR =>
      r := xa or xb;
    when LOGIC_XOR =>
      r := xa xor xb;
  end case;
  return r;
end;

function arith_update_sr(
  sr_in : sr_t;
  a_msb : std_logic;
  b_msb : std_logic;
  value : std_logic_vector;
  co_or_borrow : std_logic;
  arithfunc : arith_func_t;
  func : arith_sr_func_t)
return sr_t is
  alias v : std_logic_vector(value'length - 1 downto 0) is value;
  variable sr_out : sr_t := sr_in;
  variable v_msb : std_logic := v(v'left);
  variable is_sub : std_logic := to_bit(arithfunc = SUB);
  variable value_zero : std_logic := is_zero(v);
  variable common_gr_eq, sign_gr_eq, unsign_gr_eq : std_logic;
begin
  -- logic common to both signed and unsigned comparisons.
  -- common_gr = '1' => a >= b, but not the converse
  common_gr_eq := (not(a_msb) and not(b_msb) and not(v_msb)) or
                  (a_msb and b_msb and not(v_msb));
  sign_gr_eq := common_gr_eq or (not(a_msb) and b_msb);
  unsign_gr_eq := common_gr_eq or (a_msb and not(b_msb));
  case func is
    when ZERO =>
      sr_out.t := is_zero(v);
    when OVERUNDERFLOW =>
      sr_out.t := (not(a_msb) and not(b_msb xor is_sub) and v_msb) or
                  (a_msb and (b_msb xor is_sub) and not(v_msb));
    when UGRTER =>
      sr_out.t := unsign_gr_eq and not(value_zero);
    when UGRTER_EQ =>
      sr_out.t := unsign_gr_eq;
    when SGRTER =>
      sr_out.t := sign_gr_eq and not(value_zero);
    when SGRTER_EQ =>
      sr_out.t := sign_gr_eq;
    when DIV0S =>
      sr_out.q := a_msb;
      sr_out.m := b_msb;
      sr_out.t := a_msb xor b_msb;
    when DIV1 =>
      sr_out.q := a_msb xor sr_in.m xor co_or_borrow;
      sr_out.t := not (sr_out.q xor sr_in.m);
  end case;
  return sr_out;
end;

function logic_update_sr(
  sr_in : sr_t;
  value : std_logic_vector;
  func : logic_sr_func_t;
  constant byte_width : integer := 8)
return sr_t is
  alias v : std_logic_vector(value'length - 1 downto 0) is value;
  variable sr_out : sr_t := sr_in;
begin
  case func is
    when ZERO =>
      sr_out.t := is_zero(v);
    when BYTE_EQ =>
      -- assumes the value is a xor b
      sr_out.t := or_reduce(xor_all(or_reduce_bytes(v, byte_width), '1'));
  end case;
  return sr_out;
end;

function left_rotate(a : std_logic_vector; b : std_logic_vector) return std_logic_vector is
   constant num_bits : integer := a'length;
   variable sr, yr : std_logic_vector(a'range);
   variable offset : integer range 0 to num_bits/2;
   variable k : integer;
   begin

   yr := a;
   offset := num_bits/2;

   for i in b'range loop
      if b(i) = '1' then
         for j in a'range loop
            if j + offset >= num_bits then k := j + offset - num_bits;
            else                           k := j + offset;            end if;

            sr(k) := yr(j);
         end loop;
      else
         for j in a'range loop
            sr(j) := yr(j);
         end loop;
      end if;

      offset := offset/2;
      yr := sr;
   end loop;

   return yr;
end function;

function calf_fcn(b : unsigned) return std_logic_vector is
   constant b_left : integer := b'length - 1;
   constant result_bits : integer := 2 ** b'length;
   --variable ib : natural range 0 to result_bits-1 := to_integer(b);
   variable ib : natural := to_integer(b);
   variable f : std_logic_vector(result_bits-1 downto 0) := (others => '0');
   begin

   for i in f'range loop
      if i < ib then f(i) := '1'; end if;
   end loop;
   return f;
end function;

function calp_fcn(f : std_logic_vector; rotate, left : std_logic) return std_logic_vector is
   variable p : std_logic_vector(f'range);
   begin

   for i in f'range loop
      p(i) := (f(i) xor left) or rotate;
   end loop;
   return p;
end function;

function caly_fcn(y, p : std_logic_vector; ops : shiftfunc_t; left, c, a : std_logic) return std_logic_vector is
   variable t : std_logic_vector(y'range);
   variable s : std_logic := '0';
   -- assumes y and p have the same range and that their 'right is 0
   constant num_bits : integer := p'length;
   begin

   if ops = arith and left = '0' then s := a; end if;

   if p(0) = '1'                   then t(0) := y(0);
   elsif left = '1' and ops = rotc then t(0) := c;
   else                                 t(0) := s;      end if;

   if p(num_bits-1) = '1'          then t(num_bits-1) := y(num_bits-1);
   elsif left = '0' and ops = rotc then t(num_bits-1) := c;
   else                                 t(num_bits-1) := s; end if;

   for i in 1 to num_bits-2 loop
      if p(i) = '1' then t(i) := y(i);
      else               t(i) := s;    end if;
   end loop;

   return t;
end function;

function bshifter(a,b : std_logic_vector; c : std_logic; ops : shiftfunc_t) return std_logic_vector is
   variable left, rot : std_logic := '0';
   constant a_left : integer := a'length - 1;
   constant b_left : integer := b'length - 1;
   alias xa : std_logic_vector(a_left downto 0) is a;
   alias xb : std_logic_vector(b_left downto 0) is b;
   variable b_mag : std_logic_vector(b_left-1 downto 0);
   variable f, p, y1, y : std_logic_vector(a_left downto 0);
   begin
   -- Verify argument lengths match. The b argument is a sign bit plus
   -- N bits, and the a arg must be 2^N bits.
   if integer(a'length) /= integer(2 ** (b'length - 1)) then
     assert NO_WARNING
       report "BSHIFTER: Arg size mismatch, returning A"
       severity WARNING;
     return a;
   end if;

   -- split b into a shift magnitude and shift direction
   b_mag := xb(b_mag'range);
   left := not xb(b_left);

   if ops = rotate then rot := '1'; end if;

   f  := calf_fcn(unsigned(b_mag));
   p  := calp_fcn(f, rot, left);
   y1 := left_rotate(xa, b_mag);

   y  := caly_fcn(y1, p, ops, left, c, xa(a_left));
   return y;
end function;

function manip(x, y : std_logic_vector(31 downto 0); func : alumanip_t)
  return std_logic_vector is
  variable b0, b1, b2, b3 : std_logic_vector(7 downto 0);
  variable sign_bit : std_logic;
  variable sign_byte : std_logic_vector(7 downto 0);
begin
  if func = EXTEND_SBYTE then
    sign_bit := y(7);
  else
    sign_bit := y(15);
  end if;
  sign_byte := (others => sign_bit);

  -- assign each byte of output separately to group same cases
  case func is
    when SWAP_BYTE
       | SET_BIT_7    => b3 := y(31 downto 24);
    when EXTEND_UBYTE
       | EXTEND_UWORD => b3 := (others => '0');
    when EXTEND_SBYTE
       | EXTEND_SWORD => b3 := sign_byte;
    -- others is SWAP_WORD or EXTRACT
    when others       => b3 := y(15 downto  8);
  end case;
  case func is
    when SWAP_BYTE
       | SET_BIT_7    => b2 := y(23 downto 16);
    when EXTEND_UBYTE
       | EXTEND_UWORD => b2 := (others => '0');
    when EXTEND_SBYTE
       | EXTEND_SWORD => b2 := sign_byte;
     -- others is SWAP_WORD  or EXTRACT
    when others       => b2 := y(7  downto  0);
  end case;
  case func is
    when SWAP_BYTE    => b1 := y(7  downto  0);
    when SWAP_WORD    => b1 := y(31 downto 24);
    when EXTEND_UBYTE => b1 := (others => '0');
    when EXTEND_UWORD
       | EXTEND_SWORD
       | SET_BIT_7    => b1 := y(15 downto  8);
    when EXTEND_SBYTE => b1 := sign_byte;
    -- others is EXTRACT
    when others       => b1 := x(31 downto 24);
  end case;
  case func is
    when SWAP_BYTE    => b0 := y(15 downto  8);
    when SWAP_WORD    => b0 := y(23 downto 16);
    when EXTEND_UBYTE
       | EXTEND_UWORD
       | EXTEND_SBYTE
       | EXTEND_SWORD => b0 := y(7  downto  0);
    when SET_BIT_7    => b0 := '1' & y(6  downto  0);
    -- others is EXTRACT
    when others       => b0 := x(23 downto 16);
  end case;
  return b3 & b2 & b1 & b0;
end function;

end cpu2j0_components_pack;
