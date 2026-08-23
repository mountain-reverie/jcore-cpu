# Group-C contract locks (task A1c)

**Status:** IMPLEMENTED. Companion to
[`pagemask-walker-contract.md`](pagemask-walker-contract.md) §7.2.
**Branch:** `test/contract-group-c` (jcore-cpu), base `9fdfaf6`.
**Measured:** first on 2026-08-22 against base `6475932`; **every number in
this file re-measured from source on 2026-08-23 after the rebase onto
`9fdfaf6`**, which carries `a68c765` "shadow an ITLB fill into the DTLB, one
way only". Container `ghcr.io/mountain-reverie/jcore-cpu-ci:latest`,
`CPU_VARIANT=j4`, `SIM_TOP=cpu_tb`, `--stop-time=120us`.
The values that moved, and why, are §4b.

---

## 1. What a Group-C lock is, and why this file exists

Group-B guards fail today and pass after the fix; their non-vacuity is the
red/green transition. **Group-C guards pass today.** They exist to turn red if
someone "fixes" the TSB tag defect the wrong way, so *a green run tells you
nothing on its own* — their entire evidential content is the **stated mutation**
(contract **P4**).

That evidence is per-guard in each `.S` header. This file is the cross-table:
which mutation turns which lock red, and — just as important — which locks stay
**green** under a mutation aimed elsewhere, which is what shows a lock is
specific rather than merely fragile.

**If you change `core/tlb_walk.vhd`'s `st_tag_hi`, `core/tlb.vhd`'s install
path, or either mask function in `core/components_pkg.vhd`, re-run this
table.** A green suite after such a change means the locks were not exercised,
not that the change is safe.

## 2. The seven locks

| contract case | guard | pins |
|---|---|---|
| **C1** | `sim/tests/mmuwalkcoarsetag.S` | the canonical 4 KB tag: a 16 KB-granular tag (what today's kernel writes) must be REJECTED |
| **C2** | `sim/tests/mmuwalktagmbz.S` | `tag_hi[11:0]` MBZ — the `bus_d(11 downto 0) = x"000"` term (**R2**) |
| **C3** | `core/tlb_walk.vhd` `p_walk_read_order` + `sim/tests/mmuwalkreadorder.S` | the commit-point protocol: per way, `+0`, `+4`, `+8`, in that order |
| **C4** | `sim/tests/mmupmtlbmask.S` | PageMask governs `tlb_match()` and the relocation (pm=4, the middle of the range) |
| **C5** | `sim/tests/mmupmrawvpn.S` | the TLB stores the RAW VPN and masks at MATCH time |
| **C6g** | `sim/tests/mmupmreservedpm.S` | **C8**: the reserved PageMask range 9..15, pinned as the hazard it is |
| **C7g** | `sim/tests/mmupmmixzero.S` | pm=0/1/2/4 co-resident, and two ADJACENT 4 KB pages staying distinct |

**C3's monitor asserts its own precondition rather than gating on it.** It
decodes the word offset from `bus_a(3 downto 2)` and the way select from
`bus_a(4)`, which is the entry layout only at `entry_bytes = 16` — the
normative layout (contract §4) and the only value `core/cpu.vhd:688`
instantiates. An earlier revision carried `and entry_bytes = 16` in the sample
condition, which would have **silently switched the monitor off** at any other
width instead of failing. That is a guard that stops checking when its
precondition moves — the exact vacuity pattern this contract exists to
eliminate — so the width is now an unconditional `severity failure` assertion
inside the same process. Widening the TSB entry must break loudly and be
reworked.

**Two guards are constrained to a single 4 KB image, and that is now a build
error rather than a comment.** `mmupmrawvpn` and `mmupmreservedpm` map their
code page at VPN 0 with no trailing pad page, so the whole image must fit in
VA `0x0000..0x0FFF`; overflow does not fail, it takes a silent IMISS storm that
reads as a hang. `sim/tests/Makefile`'s `SINGLE_PAGE_LIMIT` rule fails the build
on the **linked** `_etext`, following the M8 scratch-block rule already in that
file. Both currently link at `_etext = 0x800`, half the budget; padded past the
limit the build stops with a named error and produces no `.img`.

An in-file `.if . > 0x1000` was tried first and rejected on measurement: gas
refuses it (`non-constant expression in .if statement` — `.` is not absolute in
a relocatable section), and it would also have been wrong by the `0x118` the
linker puts ahead of `.text` for `*(.vect)`. The deliberately overflowing image
ends at `_etext = 0x1100`, where `.` reads `0xFE8` — under the limit — so that
form would have passed the very overflow it was meant to catch.

C1 and C2 share one harness (`mmuwalktagmbz.S` is `#define` + `#include`), the
same pattern as `mmudspcprobe_late{b,w,c,m,mw}`.

All seven are registered in **both** `sim/mmu_sim.sh` and
`.github/workflows/full-regression.yml`; `scripts/guard_list_drift.sh` reports
`OK: no stop-time drift between the guard lists`. The Lane-2 inventory (`mmulinux`, `mmulinuxexc`,
`mmuboot`, `mmuhuge`) is mirrored as a comment in `sim/mmu_sim.sh` so the two
lists stay diffable.

## 3. The mutations

| id | change | file |
|---|---|---|
| **M1** | `st_tag_hi` ALSO accepts a 16 KB-granular tag (rejected alternatives §3(a)/(b)) | `core/tlb_walk.vhd` |
| **M2** | delete the `bus_d(11 downto 0) = x"000"` term | `core/tlb_walk.vhd` |
| **M3** | `ram(idx).page_mask <= "0000"` on install — the "assume one page size" fix | `core/tlb.vhd` |
| **M4** | `vpn_compare_mask("0000")`: `n := 0` → `n := 2` | `core/components_pkg.vhd` |
| **M5a** | `tlb_vpn_mx and vpn_compare_mask(walk_ptel(11 downto 8))` — mask by the entry's OWN mask | `core/cpu.vhd` |
| **M5c** | `tlb_vpn_mx and vpn_compare_mask("0101")` — mask by a hardwired coarser mask | `core/cpu.vhd` |
| **M6** | read `data` (+8) before `tag_hi` (+0) — rejected alternative §3(d) | `core/tlb_walk.vhd` |
| **M7** | make `vpn_compare_mask()` agree with `page_offset_mask()` above pm=8 | `core/components_pkg.vhd` |

Every mutation run **rebuilt** the cosim. `sim/mmu_sim.sh -n` skips the build
entirely, so an RTL A/B under `-n` measures stale hardware; `-n` was used only
to run a *second* guard against an already-rebuilt tree in the same batch.

## 4. Cross-table

`RED nn` is the guard's own result code, decimal as the harness prints it, hex
in parentheses. **Every cell is measured**: the table has no `—` left.

| | C1 | C2 | C3 | C4 | C5 | C7g | C6g |
|---|---|---|---|---|---|---|---|
| **pristine** | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| **M1** | **RED 17 (0x11)** | PASS | PASS | PASS | PASS | PASS | PASS |
| **M2** | PASS | **RED 33 (0x21)** | PASS | PASS | PASS | PASS | PASS |
| **M3** | RED 23 (0x17) | RED 39 (0x27) | PASS | **RED 54 (0x36)** | **RED 65 (0x41)** | **RED 95 (0x5F)** | RED 145 (0x91) |
| **M4** | PASS | PASS | PASS | PASS | PASS | **RED 84 (0x54)** | PASS |
| **M5a** | PASS | PASS | PASS | PASS | PASS *(provable no-op)* | PASS | PASS |
| **M5c** | wedge | wedge | wedge | wedge | wedge *(see §5)* | wedge | PASS *(see below)* |
| **M6** | RED (assert) @0.89 µs | RED (assert) @0.89 µs | **RED (assert) @3.76 µs** | RED (assert) @0.97 µs | RED (assert) @1.06 µs | RED (assert) @4.02 µs | RED (assert) @2.15 µs |
| **M7** | PASS | PASS | PASS | PASS | PASS | PASS | **RED 147 (0x93)** |

Bold = the case's own stated mutation.

**Provenance — this whole table is now doubly sourced.** It was first measured
on 2026-08-22 against base `6475932`. On **2026-08-23** every one of the eight
mutation rows was re-applied from §3 and re-run from source against base
`9fdfaf6` — a full 7×8 sweep, each mutation rebuilding the cosim. **Every
result code matched**: 17, 33, (23/39/54/65/95/145), 84, 147, and both M6
timings. The two rows the earlier record flagged as singly sourced — **M2 and
M3** — are now independently confirmed.

**Three cells that were `—` are now measured, and one of them is not what the
row's shorthand predicts.** C6g under M2 is PASS, under M5a is PASS, and under
**M5c is PASS — not a wedge.** That is consistent rather than surprising: M5c
wedges by masking the *stored* VPN more coarsely than the entry's own compare
mask, and C6g's entries carry pm=9/pm=10, whose compare masks already ignore
those bits, so the mis-mask cannot make them fail to match. C6g is the one lock
M5c structurally cannot livelock. C6g under M6 fails via the assertion at
**2.15 µs**, earlier than the driver's own 3.76 µs, which is expected: the
monitor is a global invariant and C6g reaches its first walk sooner.

**M6 fails every lock, and that is correct rather than sloppy.**
`p_walk_read_order` is a *global* invariant asserted on every walk, so it fires
on the first walk of any image. Its evidential value is the named report
string, which cannot be conflated with anything else:

```
../core/tlb_walk.vhd:444:15:@3760ns:(assertion failure):
WALK READ ORDER VIOLATED: data (+8) read before ...
instance: /cpu_tb/cpu1/g_tlb_walk/u_tlb_walk/p_walk_read_order
```

At 3.76 µs against a 120 µs stop-time that is the assertion firing, not a
timeout — the distinction `jcore-cpu/CLAUDE.md` insists on.

**Measured completion times** (VCD final timestamps, pristine RTL, base
`9fdfaf6`): `mmupmrawvpn` 2.20 µs, `mmupmtlbmask` 2.45, `mmuwalkcoarsetag`
2.55, `mmuwalktagmbz` 2.56, `mmupmreservedpm` 4.03, `mmuwalkreadorder` 6.37,
`mmupmmixzero` 8.53. The registered 120 µs is ~14× the slowest. **All seven
moved on the rebase; §4b has the A/B and the reason.**

## 4a. Whole-suite regression

`p_walk_read_order` is a **permanently asserted** invariant, so it runs against
every image in the suite, not only against its own driver. A full
`sim/mmu_sim.sh` run on the pristine tree with the monitor in place:

**Current**, 2026-08-23, base `9fdfaf6`, full `sim/mmu_sim.sh`, everything the
script runs:

```
==> all guards PASSED
```

**114 PASS lines, 0 FAIL lines** — 107 pre-existing guards (the count
`a68c765`'s own commit message records for master) plus these seven. On the old
base the same arithmetic gave 111; master added `mmuishadow`, `mmudshadow` and
`slotillset` in between.

**How that count is obtained, stated precisely, because the earlier revision of
this file got it wrong.** `sim/mmu_sim.sh` prints one `  PASS <name>` or
`  FAIL <name>` line per guard and a single trailing `==> all guards PASSED`.
**It has never printed an `N PASS, 0 FAIL` summary line** — no revision of it
in this repository contains such a string. An earlier revision of this section
showed

```
111 PASS, 0 FAIL   ==> all guards PASSED
```

as a verbatim capture and then explained a later capture's missing count by
saying "the runner emitted its `N PASS, 0 FAIL` line as usual". Both were
wrong: that line was a hand-tallied count formatted to look like runner output,
and the runner it was attributed to cannot produce it. **The count above is a
`grep -c '^  PASS'` over the run's own log**, and it is written that way here so
that nobody re-derives a fictional transcript from it. The 111 remains correct
as an arithmetic tally of the old guard list; only its presentation as a
capture was false.

**The same correction applies to this branch's commit log, which the paragraph
above did not reach.** Two messages still in history are wrong in the same way,
and a reviewer reading `git log` will meet them:

* `b9ccfcb` — "the full suite, not just its own driver: 111 PASS / 0 FAIL".
* `2f831a5` — claims this file was fixed to say "plainly that its `N PASS /
  0 FAIL` line was lost to a `tail -6`". **There was no such line to lose.**
  That is the fabricated *explanation* built on top of the fabricated format,
  and it is recorded here because it cannot be edited out of a message that is
  already committed.

Both are superseded by this section. The counts in them are sound arithmetic;
the format, and `2f831a5`'s account of a truncated summary, are not.
`35682a0`'s "114 PASS, 0 FAIL" is the same tally stated in the same unfortunate
shape, though that message does at least say where the number comes from.

That green run is also the empirical half of §4b's C3 argument: master's
`mmuishadow` and `mmudshadow` are in it, so `p_walk_read_order` has now run
against the shadow-fill guards themselves without firing.

**Read that claim precisely.** A green suite proves the monitor does not
false-fire on the walk shapes those images actually *take*. It says nothing
about a path no image drives, and **nothing here demonstrates that any image
reaches the walker's timeout exit** (`core/tlb_walk.vhd:334-345`). For that path
the argument is structural, not empirical: the timeout exit sets `state <=
st_idle`, and `st_idle` unconditionally clears `v_seen`/`v_have` at the top of
the monitor, so the next walk begins from an empty record and a false-fire is
unreachable by construction. The give-up, re-arm and way-1 paths *are*
exercised — `mmuwalkreadorder` drives the way-1 and both-ways-miss shapes by
construction, and `mmuwalkrearm` and `mmuwalkmiss` drive re-arm and give-up —
so those three are empirical and only the timeout one is argued.

## 4b. What the I→D shadow fill (`a68c765`) did to this table

`a68c765` makes every ITLB install also install the same PTE into the DTLB one
cycle later, speculatively. That is exactly the class of change that can make a
lock keep passing *for a different reason than it was written for*, because
every one of these locks asserts exact `TSBCNT` deltas alongside its data
checks. It was therefore checked directly rather than inferred from a green
run.

**No result code moved, and no lock's premise moved.** All eight mutation rows
above were re-applied and re-run on the new base and every result code came out
identical. What moved is timing only:

| | old base `6475932` | new base `9fdfaf6` | Δ |
|---|---|---|---|
| `mmupmrawvpn` | 2.38 µs | 2.20 | −0.18 |
| `mmuwalkcoarsetag` | 2.66 | 2.55 | −0.11 |
| `mmuwalktagmbz` | 2.69 | 2.56 | −0.13 |
| `mmupmreservedpm` | 4.37 | 4.03 | −0.34 |
| `mmuwalkreadorder` | 6.46 | 6.37 | −0.09 |
| `mmupmmixzero` | 7.96 | **8.53** | **+0.57** |
| `mmupmtlbmask` | *"~3"* | 2.45 | — |
| M5c wedge onset (§5) | 1.49 | **1.32** | **−0.17** |

`mmupmtlbmask` has no honest Δ: the old record carried "~3", an estimate rather
than a VCD reading, so 2.45 µs is its first measured value.

**Four of these were A/B'd against the shadow fill itself; three were not, and
the distinction is stated rather than smoothed over.** The A/B holds everything
else and reduces `core/cpu.vhd`'s
`dtlb_wr <= (walk_install and not walk_side_i) or shadow_wr` to
`dtlb_wr <= walk_install and not walk_side_i` (shadow fill off), rebuilding the
tree — never under `-n`. With the fill off:

| A/B'd | fill off | fill on | old record |
|---|---|---|---|
| `mmupmmixzero` | 7.95 µs | 8.53 | 7.96 |
| `mmuwalkcoarsetag` | 2.68 | 2.55 | 2.66 |
| `mmupmreservedpm` | 4.37 | 4.03 | 4.37 |
| M5c wedge onset | 1490 ns | 1320 ns | 1.49 µs |

Each "fill off" column reproduces the old record, so for those four the
attribution to `a68c765` is **measured**. `mmuwalktagmbz`, `mmupmrawvpn` and
`mmuwalkreadorder` were re-measured on the new base but **not** A/B'd; their
shifts are small, same-signed and same-shaped as the four that were, so
attributing them to the same cause is an inference — a reasonable one, and
labelled as one.

Six of the seven got faster for the obvious reason: the shadow fill removes the
second full TSB walk a code page's literal-pool load used to cost.
**`mmupmmixzero` got slower**, and it is the only one that did. It is also the
only guard that deliberately keeps four page sizes co-resident in the DTLB, so
it is the one whose slot pressure a speculative install can actually raise;
speculative entries land `used = '0'` and are taken as the next NRU victim, so
the code page's shadow-installed entry is repeatedly re-taken and re-installed.
That mechanism is the *reading* of the +0.57 µs, not a second measurement — the
measurement is the A/B above. Either way it is a run-time cost, not an
assertion: `mmupmmixzero` still passes, still reports `cnt_hits` +5 in round 0,
and 8.53 µs still sits 14× inside the registered 120 µs.

**Why no counter assertion moved.** The shadow install performs no bus
transaction and no walk, so `cnt_walks`/`cnt_hits` cannot move because of it;
the P4 install counters `a68c765` added are a separate alias these guards do
not read. And it installs only what an ITLB install already fetched — i.e.
code pages — while every page *under test* in these seven locks is reached from
the D side. The one place the two could meet is C6g, whose pm ≥ 9 wildcard
overlaps everything: there the shadow fill's dedup scan finds the wildcard
resident and **skips the install entirely**, so the wildcard survives and C6g's
"the wildcard swallows the code page" note in `mmupmreservedpm.S` still holds,
now for a second, independent reason.

**C3 was checked against the new code path specifically.** `p_walk_read_order`
samples `bus_en_int and bus_ack`, which only the walker drives; the shadow fill
is a TLB write with no bus cycle, and it lands the cycle after `st_install`,
by which time the FSM is in `st_idle` and the monitor has already cleared
`v_seen`/`v_have`. So it is unreachable by construction — and empirically,
master's two new guards `mmuishadow` and `mmudshadow` now run under the
monitor and are green (§4a).

## 5. C5's stated mutation is not constructible as a reportable proof

**Proposed contract amendment.** §7.2's C5 row says the mutation is "make
`core/cpu.vhd` mask `tlb_vpn_mx` by anything before the install". On this RTL
that mutation is **either a provable no-op or a hardware livelock, never a
reportable guard failure**, and the contract should say so.

* A mask **at or finer than** the entry's own `vpn_compare_mask(pm)` clears
  only bits the match path already ignores. It cannot change any outcome. This
  is C5's own argument — the clause rejects store-time masking on **cost**, not
  correctness — and **M5a** measures it: all seven locks stay green.
* A mask **coarser** than the entry's own makes the installed entry fail to
  match *the very VA the walk was armed for*. `core/tlb_walk.vhd` sets `tried`
  only when a walk **gives up**, never after a successful install, and
  `giveups` likewise counts only give-ups — so the walker re-arms without
  bound: walk, install, still miss, walk, … The core is stalled throughout and
  no instruction retires, so **no software guard can report anything**. **M5c**
  measures it: the run stalls at **1.32 µs** with `Address changed but did
  not see ACK` and never reports a code. (It was 1.49 µs before `a68c765`; the
  onset moved with the shadow fill and the A/B is in §4b. The wedge itself is
  unchanged — only when it starts.)

There is no middle case, so C5's mutation proof is **M3** (`page_mask`
hardwired), under which `mmupmrawvpn` reports its own code 65 (0x41).

**Derived RTL follow-up, filed rather than fixed here.** The walker has no
bound on *install-then-still-miss* re-arming. Today nothing can produce a
non-matching install — C5 is exactly the clause that guarantees it — but a
future install-path change of that shape would present as an unrecoverable
wedge rather than a diagnosable fault, which is the same failure *class* as the
livelock this whole contract exists to close. A `giveup_limit`-style bound on
installs within one `req` assertion would convert it into a normal miss
exception. Out of scope for A1c under **R5** ("the walker adds no state").

## 6. C6g was believed unbuildable and is not

A first pass concluded C6g could not be built: pm=9/pm=10 differ from pm=8 only
at a VA ≥ `0x1000_0000`, and **P5** binds the raw VA on any access that can
miss, while the cosim backs only `[0, 0x0100_0000)`.

That was wrong, and the reason is worth recording because it widens what P5
permits. `core/cpu.vhd`'s relocation arm forces **`db_o.a(31 downto 28) <=
"0000"`** on every translated hit and splices only `PA[27:12]`, so VA
`0x1060_0000` resolves to PA `0x0060_0000` — inside the backed window — even
though the VA is not. On this RTL the probe **hits** the resident wildcard, so
there is no miss window and the raw VA never reaches the bus.

The mutation would create a miss at that VA, which *would* strand an unbacked
raw VA. The guard therefore gives the probe VA **its own TSB row, pointing at a
different frame**, provably never read on this RTL (that is exactly what the
counter assertion claims). Under **M7** the probe misses, the walk resolves
from that row, and the guard reports 147 (0x93) — a code, not a wedge — and
fails the *data* check as well as the counter check.

**Proposed clarification to P5.** The rule is stated as binding on "every VA a
guard touches", justified by "a TLB entry can always be evicted". The stronger,
checkable form is: *a VA outside the backed window is admissible only if (a) it
provably hits a resident entry, and (b) a TSB row exists for it whose walk
resolves to a backed PA, so that an eviction or a mutation degrades to a walk
rather than to a wedge.* C6g satisfies both.

**Clause (b) is not a hypothesis — it is the measured difference between this
case and C5.** Under **M7** the probe VA `0x1060_0000` genuinely misses, its raw
unbacked VA genuinely reaches the bus, and the guard nonetheless **reports 147
(0x93) rather than wedging**, because the row put there under clause (b)
resolves the walk. C5's M5c, which has no such escape, wedges at 1.32 µs with
no code (§5). Same environment, same P5 pressure, opposite outcome — and the
only structural difference is clause (b). That is the empirical case for
adopting the relaxation rather than merely permitting it.

## 7. The Group-P condition: P1g was not needed

§7.3 requires that a non-increment assertion written outside the company of a
Group-B guard be backed by P1g. **Every one of the seven locks pairs its
non-increment assertions with an exact positive `cnt_hits` delta in the same
run**, which is the remedy §7.3 itself prefers:

| guard | the increment half |
|---|---|
| C1 / C2 | phase 1 asserts `cnt_walks` moved while `cnt_hits` did not; phase 2 asserts `cnt_hits` +1 |
| C3 | cases A..D assert `cnt_hits` +4 exactly; case E asserts `cnt_walks` moved while `cnt_hits` did not |
| C4 | phase 1 asserts `cnt_hits` +1 exactly, before phase 2's non-increment |
| C5 | phase 1 asserts `cnt_hits` +1 exactly, before phases 2 and 3's non-increments |
| C6g | phases 1 and 3 each assert `cnt_hits` +1 exactly, before phases 2 and 4's non-increments |
| C7g | round 0 asserts `cnt_hits` +5 exactly, before rounds 1 and 2's non-increments |

Every delta is taken **before** the access under test, not after it, so it
attributes the walk to that access — the stronger form **P1** asks for and the
one `mmupage16k.S` does not have. **P1g remains retired.**

None of the seven identity-maps its page under test except where identity is
forced by `pm ≥ 6` arithmetic (C6g's V1 and V3), and there the header names the
witness. Every VA-as-physical address is seeded with poison, so an inert MMU
fails the first data check in every guard.

## 8. The `__update_tlb()` coverage decision

§7.4 asks A1b/A1c to either add a case driving a real fault through
`do_page_fault()` to `update_mmu_cache()` and asserting the primed row, **or
record a decision not to**. A1b deferred it here.

**Decision: NOT ADDED on this branch. Two independent reasons, one
environmental and one about attribution.**

1. **`do_page_fault()` is not reachable in Lane 2, and that is a property of
   the environment.** Reaching `update_mmu_cache()` through the generic fault
   path needs `handle_mm_fault()`, a live `mm_struct`, a vma tree, `current`,
   and the page allocator — i.e. a booted kernel. Every Lane-2 harness stubs
   `jcore_handle_exception` for exactly that reason (`mmulinux.S:992`,
   `mmuhuge.S:552-557`). §7.4 already records that "nothing in this environment
   boots a kernel". A harness that faked those structures would be testing the
   fake.

   `mmuhuge.S:550-551` says the quiet part out loud, and it is the sharpest
   single citation for this decision: it stubs `arch_local_irq_restore()` /
   `arch_local_save_flags()` as *"referenced by `tlb-jcore.o`'s
   `__update_tlb()`; **never actually called here**"*. So the fill site is
   already linked into Lane 2 and already unreached — the gap §7.4 names is
   confirmed from the harness side, not only inferred from the kernel side.
2. **A guard for that fill site is a Group-B case, not a Group-C lock, and it
   belongs with A1a.** `__update_tlb()` writes the *second* of the two TSB fill
   sites **K1** governs. On any tree whose `LINUX_SRC` lacks A1a's
   `JCORE_TSB_TAG_MASK` change, a guard asserting the canonical tag there is
   RED — which is the correct Group-B behaviour, but it is A1a's red, not a
   Group-C lock. CI's `LINUX_SRC` is a fresh checkout of `mountain-reverie/linux`
   at ref `jcore` (`.github/workflows/full-regression.yml:148-153`), so landing such a guard
   from this branch would break CI until A1a's kernel change merges. A1b's
   warning — "a guard written there would have encoded the bug as its expected
   value" — does **not** dissolve on this branch, because this branch is a
   jcore-cpu branch and carries no kernel at all.

**The reachable substitute, specified for whoever owns the A1a merge.** The
`do_page_fault()` half is unreachable, but `__update_tlb()` **itself is directly
callable from a bare-metal Lane-2 harness** — verified by reading it, and worth
recording because it is not obvious:

* its only `vma` dereference is guarded by `if (vma && current->active_mm !=
  vma->vm_mm) return;`, which **short-circuits entirely at `vma == NULL`**;
* everything after that is `local_irq_save()`, `jcore_pte_to_ptel()`, an
  `__raw_readl(JCORE_ASIDR)`, `jcore_tsb_slot_addr()`, `jcore_tsb_pick_way()`
  and `jcore_tsb_write_entry()` — **no mm structure is touched at all.**

So a harness linking the real `arch/sh/mm/tlb-jcore.o` can call
`__update_tlb(NULL, addr, pte)` with a hand-built pte and a VA whose
`VA[13:12] != 0`, then (a) read back the row at `jcore_tsb_slot_addr(addr)` and
assert `tag_hi == (addr & 0xFFFF_F000)`, and (b) — the stronger form — enable
`MMUCR.AT` and take an access at that VA, asserting the walker resolves it with
a `cnt_hits` delta of +1 and the correct relocated PA. That is "assert the
primed row" with a live witness, and it covers **K1**'s second site and
**K8**'s correct-but-partial hugetlb behaviour. It should land on the branch
that carries A1a's kernel change, where it is red before and green after.

## 9. Reproducing the table

```bash
docker run --rm \
  -v <worktree>:/w \
  -v <jcore-workspace>/jcore-soc:/jcore-soc \
  -v <jcore-workspace>/jcore-soc/tools:/tools \
  -e JCORE_SOC=/jcore-soc -w /w \
  ghcr.io/mountain-reverie/jcore-cpu-ci:latest \
  bash -lc 'sim/mmu_sim.sh mmuwalkcoarsetag cpu_tb 120us'
```

`sim/mmu_sim.sh`'s `TOOLS_DIR` wildcard does not resolve inside the image, which
is why `jcore-soc/tools` is mounted at `/tools` as well as at `/jcore-soc/tools`.
Apply a mutation, rebuild **without** `-n`, run, revert, rebuild, confirm green.
