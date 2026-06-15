-- J1 sequential shifter: one 1-bit shift per slot cycle, reusing a single
-- 1-bit datapath `count` times instead of a barrel network. Alternative
-- architecture of entity `shifter`; results are bit-identical to comb
-- (bshifter) for every b, op and direction. Mirrors core/mult_seq.vhd: slow
-- is the GOAL (area is the prize). busy stalls the CPU pipeline; single-bit
-- (and zero) shifts finish in the accept cycle and never stall.
--
-- ROTCL/ROTCR are 1-bit ops in the ISA (count=1, accept-cycle path); the
-- multi-step ROTC carry chain below is self-consistent and cross-checked
-- against comb, but is not reachable from a real SH-2 instruction.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu2j0_components_pack.all;

architecture seq of shifter is
  type st_t is (IDLE, RUN);
  type reg_t is record
    st    : st_t;
    val   : std_logic_vector(31 downto 0);
    count : unsigned(5 downto 0);
    dir   : std_logic;                 -- '0' left, '1' right
    sop   : shiftfunc_t;
    carry : std_logic;                 -- ROTC running bit
    tout  : std_logic;                 -- latched shifted-out bit
  end record;
  constant RESET_R : reg_t :=
    (IDLE, (others => '0'), (others => '0'), '0', LOGIC, '0', '0');
  signal r, rin : reg_t;

  -- One reused 1-bit shift (NOT a barrel).
  function step1(v : std_logic_vector(31 downto 0); dir : std_logic;
                 op : shiftfunc_t; cin : std_logic)
    return std_logic_vector is
  begin
    if dir = '0' then          -- left
      case op is
        when ROTATE => return v(30 downto 0) & v(31);
        when ROTC   => return v(30 downto 0) & cin;
        when others => return v(30 downto 0) & '0';     -- LOGIC, ARITH
      end case;
    else                       -- right
      case op is
        when ARITH  => return v(31) & v(31 downto 1);
        when ROTATE => return v(0)  & v(31 downto 1);
        when ROTC   => return cin   & v(31 downto 1);
        when others => return '0'   & v(31 downto 1);   -- LOGIC
      end case;
    end if;
  end function;

  function bitout(v : std_logic_vector(31 downto 0); dir : std_logic)
    return std_logic is
  begin
    if dir = '0' then return v(31); else return v(0); end if;
  end function;
begin
  comb : process(r, sel, a, b, t_in, op)
    variable v      : reg_t;
    variable left   : std_logic;
    variable mag5   : unsigned(5 downto 0);
    variable cnt    : unsigned(5 downto 0);
    variable accept : boolean;
    variable y1     : std_logic_vector(31 downto 0);
    variable yf     : std_logic_vector(31 downto 0);  -- final-step result
    variable t1     : std_logic;
  begin
    v := r;
    left := not b(5);
    mag5 := unsigned('0' & b(4 downto 0));
    if left = '1' then cnt := mag5; else cnt := to_unsigned(32, 6) - mag5; end if;
    -- step1/bitout use dir='0'=left (the b(5) convention); `left` is its inverse.
    y1 := step1(a, not left, op, t_in);
    if left = '1' then t1 := a(31); else t1 := a(0); end if;
    -- Accept on `sel` (the registered EX shift-select), NOT on `start`/slot:
    -- busy must depend only on registered signals so it can drive the
    -- combinational slot-stretch (busy -> slot_o=0) without forming a loop
    -- through slot_o. The FSM steps one bit every CLOCK while the slot is
    -- stretched (the pipeline, including this shift in EX, is frozen).
    accept := (r.st = IDLE) and (sel = '1');

    -- defaults (don't-care when not a shift / not selected)
    busy  <= '0';
    y     <= y1;
    t_out <= t1;

    if r.st = RUN then
      t_out <= r.tout;
      if r.count > 1 then
        busy <= '1';                                -- iterating: stall (slot=0)
        y    <= r.val;                              -- intermediate (not committed)
        v.val   := step1(r.val, r.dir, r.sop, r.carry);
        v.carry := bitout(r.val, r.dir);
        v.count := r.count - 1;
      else                                          -- last step: finish now
        yf   := step1(r.val, r.dir, r.sop, r.carry);
        busy <= '0';                                -- done: slot fires, commits yf
        y    <= yf;                                 -- final value, written this slot
        v.val := yf;
        v.st  := IDLE;
      end if;
    elsif accept then
      if cnt = 0 then
        y <= a;                                     -- identity, no stall
      elsif cnt = 1 then
        y <= y1;                                    -- single bit, no stall
      else
        busy <= '1';                                -- multi-bit: stall now
        y    <= y1;                                 -- intermediate (suppressed)
        v.st    := RUN;
        v.val   := y1;
        v.count := cnt - 1;
        v.dir   := not left;        -- store in step1's dir convention (0=left)
        v.sop   := op;
        v.carry := t1;
        v.tout  := t1;
      end if;
    end if;

    rin <= v;
  end process;

  reg : process(clk, rst)
  begin
    if rst = '1' then r <= RESET_R;
    elsif rising_edge(clk) then r <= rin; end if;
  end process;
end seq;
