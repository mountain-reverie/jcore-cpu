#!/usr/bin/env python3
"""Reliable GHW signal resolver + settled-snapshot dumper for the jcore cpu_tb.

ghwdump assigns sequential signal IDs depth-first in VHDL declaration order and
prints records only as index *ranges* (`signal X: T: #lo-#hi`), not per-leaf. This
module models the record types so a dotted path like `this_r.data_o.en` resolves to
an absolute ghwdump signal index, and dumps values *settled* at clk-rising edges
(grouping all same-timestamp delta-cycle updates before snapshotting -- naive
per-line sampling races the clk against other signals at the same timestamp).

Usage:
  from ghwsig import Resolver, dump
  r = Resolver('/tmp/store.hier')
  idx = r.resolve('/cpu_tb/cpu1/u_datapath/this_r.data_o.en')
  dump('/tmp/store.ghw', r, {'do_en':'.../this_r.data_o.en', ...}, lo_ps, hi_ps)
"""
import re, subprocess, sys

# ---- Record/enum field models (width in leaf-signals). Order = VHDL decl order.
# Scalars (std_logic / enum) = width 1. Vectors = their bit count.
RECORDS = {
    'sr_t':        [('t',1),('s',1),('q',1),('m',1),('int_mask',4),('md',1),('rb',1),('bl',1)],
    'priv_reg_t':  [('expevt',12),('intevt',12),('tra',10)],
    'mmu_reg_t':   [('pteh',32),('ptel',32),('asidr',32),('mmucr',32),('tea',32),('ttb',32),('tsbbr',32),('tsbcfg',32),('tsbptr',32)],
    'cpu_data_o_t':[('en',1),('a',32),('rd',1),('wr',1),('we',4),('d',32)],
    'cpu_instruction_o_t':[('en',1),('a',31),('jp',1)],
    'cpu_data_i_t':[('d',32),('ack',1)],
    'cpu_instruction_i_t':[('d',16),('ack',1)],
    'cpu_debug_o_t':[('ack',1),('d',32),('rdy',1)],
    'bus_val_t':   [('en',1),('d',32)],
    # ybus_val_pipeline_t = array(2 downto 0) of bus_val_t -> handled specially
    'datapath_reg_t':[
        ('pc',32),('sr','sr_t'),('priv','priv_reg_t'),('mmu','mmu_reg_t'),
        ('tlb_exc_captured',1),
        ('ma_pc',32),('tlb_exc_pc',32),('tlb_exc_sr','sr_t'),('tlb_squash',1),
        ('mac_s',1),('data_o_size',1),('data_o_lock',1),
        ('data_o','cpu_data_o_t'),('inst_o','cpu_instruction_o_t'),
        ('pc_inc',32),('if_dr',16),('if_dr_next',16),
        ('illegal_delay_slot',1),('illegal_instr',1),('if_en',1),
        ('m_dr',32),('m_dr_next',32),('m_en',1),('slot',1),
        ('enter_debug',4),('old_debug',1),('stop_pc_inc',1),('debug_state',1),
        ('debug_o','cpu_debug_o_t'),('ybus_override','__ybus__')],
}

def field_width(t):
    if t == '__ybus__':
        return 3 * type_width('bus_val_t')
    if isinstance(t, int):
        return t
    return type_width(t)

def type_width(tname):
    return sum(field_width(w) for _, w in RECORDS[tname])

def field_offset(tname, field):
    """Offset (in leaf-signals) of `field` within record type `tname`, and its type."""
    off = 0
    for fn, w in RECORDS[tname]:
        if fn == field:
            return off, w
        off += field_width(w)
    raise KeyError(f'{field} not in {tname}')

class Resolver:
    def __init__(self, hier_path):
        # map full hierarchical signal name -> (base_index, type_name_or_None)
        self.base = {}
        rx = re.compile(r'(?:signal|port-in|port-out)\s+(\S+):\s+([^:]+):\s+#(\d+)(?:-#\d+)?')
        for line in open(hier_path):
            m = rx.search(line)
            if not m:
                continue
            name, typ, lo = m.group(1), m.group(2).strip(), int(m.group(3))
            self.base.setdefault(name, (lo, typ))

    def resolve(self, path):
        """path = '/full/hier/signal.field.subfield' or '...signal(bit)' or plain '#N'."""
        if path.startswith('#'):
            return int(path[1:])
        parts = path.split('.')
        head = parts[0]
        if head not in self.base:
            raise KeyError(f'no signal {head}')
        idx, typ = self.base[head]
        # normalize ghwdump type spelling -> our record keys
        typ = typ.split()[0]
        for f in parts[1:]:
            off, ft = field_offset(typ, f)
            idx += off
            typ = ft if isinstance(ft, str) else None
        return idx

def _vec(val, lo, n):
    s = ''.join(val.get(i, 'U') if val.get(i, 'U') in '01' else 'x' for i in range(lo, lo+n))
    return '?'*((n+3)//4) if 'x' in s else ('%0*x' % ((n+3)//4, int(s, 2)))

def dump(ghw, resolver, sigspec, lo_ps, hi_ps, clk='/cpu_tb/clk', pcsig=None, pcshift=1):
    """sigspec: dict name->(path, width). width 1 prints the bit; >1 prints hex.
    Snapshots settled values at each clk-rising timestamp in [lo_ps,hi_ps]."""
    idx = {n: (resolver.resolve(p), w) for n, (p, w) in sigspec.items()}
    clk_i = resolver.resolve(clk)
    pc_i = resolver.resolve(pcsig) if pcsig else None
    want = sorted({i for i, _ in idx.values()} |
                  {clk_i} | ({j for j in range(pc_i, pc_i+32)} if pc_i else set()) |
                  {j for (i, w) in idx.values() for j in range(i, i+w)})
    out = subprocess.run(['ghwdump', '-s', '-T', '-f', ','.join(map(str, want)), ghw],
                         capture_output=True, text=True).stdout
    val = {}; t = 0; clkp = '0'; pending = False; pend_t = 0
    names = list(sigspec)
    print('  t(ps)  ' + ('pc       ' if pc_i else '') + ' '.join('%-6s' % n for n in names))
    def emit(tt):
        row = []
        if pc_i:
            row.append(_vec(val, pc_i, 32))
            # pc field is 32b; show as byte addr
            pv = row[-1]
            if '?' not in pv:
                row[-1] = '%08x' % ((int(pv, 16) << pcshift) & 0xffffffff)
        for n in names:
            i, w = idx[n]
            row.append(val.get(i, 'U') if w == 1 else _vec(val, i, w))
        print('%8.0f ' % (tt/1000) + ' '.join('%-6s' % c for c in row))
    for line in out.splitlines():
        m = re.match(r'Time is (\d+)', line)
        if m:
            # a new timestamp begins: flush settled snapshot from the previous block
            if pending and lo_ps <= pend_t/1000 <= hi_ps:
                emit(pend_t)
            pending = False
            t = int(m.group(1)); continue
        m = re.match(r"#(\d+): '(.)'", line)
        if not m:
            continue
        i = int(m.group(1)); v = m.group(2); val[i] = v
        if i == clk_i:
            if clkp == '0' and v == '1':
                pending = True; pend_t = t
            clkp = v
    if pending and lo_ps <= pend_t/1000 <= hi_ps:
        emit(pend_t)

if __name__ == '__main__':
    # quick self-test: datapath_reg_t must be 650 leaves
    w = type_width('datapath_reg_t')
    print(f'datapath_reg_t width = {w} (expect 822)')
    assert w == 822, 'type model mismatch!'
    print('OK')
