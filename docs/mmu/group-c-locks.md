# Group-C contract locks (task A1c)

**Status:** IMPLEMENTED. Companion to
[`pagemask-walker-contract.md`](pagemask-walker-contract.md) §7.2.
**Branch:** `test/contract-group-c` (jcore-cpu), base `6475932`.
**Measured:** 2026-08-22, container
`ghcr.io/mountain-reverie/jcore-cpu-ci:latest`, `CPU_VARIANT=j4`,
`SIM_TOP=cpu_tb`, `--stop-time=120us`.

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

C1 and C2 share one harness (`mmuwalktagmbz.S` is `#define` + `#include`), the
same pattern as `mmudspcprobe_late{b,w,c,m,mw}`.

All seven are registered in **both** `sim/mmu_sim.sh` and
`.github/workflows/full-regression.yml`; `scripts/guard_list_drift.sh` reports
`OK: no stop-time drift`. The Lane-2 inventory (`mmulinux`, `mmulinuxexc`,
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
in parentheses. `—` = not run in that combination.

| | C1 | C2 | C3 | C4 | C5 | C7g | C6g |
|---|---|---|---|---|---|---|---|
| **pristine** | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| **M1** | **RED 17 (0x11)** | PASS | PASS | PASS | PASS | PASS | — |
| **M2** | PASS | **RED 33 (0x21)** | PASS | PASS | PASS | PASS | — |
| **M3** | RED 23 (0x17) | RED 39 (0x27) | PASS | **RED 54 (0x36)** | **RED 65 (0x41)** | **RED 95 (0x5F)** | RED 145 (0x91) |
| **M4** | PASS | PASS | PASS | PASS | PASS | **RED 84 (0x54)** | PASS |
| **M5a** | PASS | PASS | PASS | PASS | PASS *(provable no-op)* | PASS | — |
| **M5c** | wedge | wedge | wedge | wedge | wedge *(see §5)* | wedge | — |
| **M6** | RED (assert) | RED (assert) | **RED (assert) @3.76 µs** | RED (assert) | RED (assert) | RED (assert) | PASS-n/a |
| **M7** | — | — | PASS | — | — | PASS | **RED 147 (0x93)** |

Bold = the case's own stated mutation.

**M6 fails every lock, and that is correct rather than sloppy.**
`p_walk_read_order` is a *global* invariant asserted on every walk, so it fires
on the first walk of any image. Its evidential value is the named report
string, which cannot be conflated with anything else:

```
../core/tlb_walk.vhd:427:15:@3760ns:(assertion failure):
WALK READ ORDER VIOLATED: data (+8) read before ...
instance: /cpu_tb/cpu1/g_tlb_walk/u_tlb_walk/p_walk_read_order
```

At 3.76 µs against a 120 µs stop-time that is the assertion firing, not a
timeout — the distinction `jcore-cpu/CLAUDE.md` insists on.

**Measured completion times** (VCD final timestamps, pristine RTL):
`mmupmrawvpn` 2.38 µs, `mmuwalkcoarsetag` 2.66, `mmuwalktagmbz` 2.69,
`mmupmreservedpm` 4.37, `mmuwalkreadorder` 6.46, `mmupmmixzero` 7.96. The
registered 120 µs is ~15× the slowest.

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
  measures it: the run stalls at 1.49 µs with `Address changed but did not see
  ACK` and never reports a code.

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
   `jcore_handle_exception` for exactly that reason (`mmulinux.S:967`,
   `mmuhuge.S:563`). §7.4 already records that "nothing in this environment
   boots a kernel". A harness that faked those structures would be testing the
   fake.
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
