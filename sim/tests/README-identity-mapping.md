# Identity mapping in MMU guards

Companion to the "Never identity-map the page under test" bullet in
`jcore-cpu/CLAUDE.md` → *Writing a guard*. This file records **why** the rule
exists and **which guards in the current suite do not yet satisfy it**, so the
remediation can be worked through one file at a time.

Survey date: 2026-08-21, re-audited 2026-08-23 against `origin/master` after
`a68c765` ("shadow an ITLB fill into the DTLB") added `mmuishadow.S` and
`mmudshadow.S`. Corpus: all 87 `sim/tests/mmu*.S`.

---

## 1. The rule

**Default: do not identity-map the page under test.** Choose `PA != VA` so a
missing or wrong translation produces a *wrong or faulting* access rather than
a correct one. That is what makes the guard's green state evidence.

**Where identity is forced, the guard must establish that translation actually
occurred by an independent witness**, and must say in its header *why*
identity was unavoidable and *which* witness covers it.

### Why identity is fatal here

With `MMUCR.AT = 0`, a P0 access is untranslated: the bus sees the VA
(`docs/architecture/tlb.md` §1). So on an identity page, these four states are
indistinguishable from the returned data alone:

1. the translation resolved correctly;
2. the TLB entry silently failed to install;
3. the hardware TSB walker never ran;
4. `AT` was never enabled at all.

A guard whose decisive assertion is a data read-back through an identity page
is green in all four. It is not a weak guard — it is not a guard.

Two live findings motivated writing this down:

* A hard **TLB-walker livelock** survived a suite of 100+ MMU guards. Part of
  why: the cosim working sets were identity-mapped and base-sub-page-first, so
  nothing distinguished a resolved translation from an absent one.
* `mmuhuge.S` encodes a page-table shape Linux cannot build (a 256 MB huge pte
  at `pte_index(VA_touched)`, where `huge_pte_alloc()` can only produce index
  0). It survived because the walker indexed raw and the discrepancy was
  invisible — precisely because nothing forced the translation to be
  observable.

`mmuxlate.S:6-31` and `mmuirun.S:192-212` already describe this hazard in their
own headers, having been repaired for it individually. The rule generalises
what those two guards learned — while discarding the false mechanism they
attributed it to (see "Not a reason", below).

### When identity is forced

Two cases:

**(a) Large PageMask inside the backed window.** For `pm >= 6`,
`page_offset_mask()` (`core/components_pkg.vhd:628-675`) marks PA bits 12..23
as in-page offset, sourced from the VA. Only PA bits 24+ come from the PPN.
The cosim backs physical memory only in `[0, 0x0100_0000)` (`sim/cpu_ctb.c`
`mem_bus_stack_map` / `if_bus_stack_map`, `.end = 0x1000000`), so those PPN
bits must be zero — and the translation degenerates to identity. A `pm >= 6`
entry also spans the entire backed window, so it is necessarily SOLO.

**(b) A load-bearing image layout.** Identity is *forced by layout* only when
the page under test must sit at a specific **physical** address for a reason
outside the mapping — a `.org`-pinned instruction, a vector table at a fixed
`VBR` offset, the flat VA=PA image load.

> **The test: if you can move the backing frame by editing only PTE/PTEL
> constants, identity was not forced.** "It would be awkward to move" is not
> forced.

Unlike (a), which is arithmetic anyone can recheck, this one is a judgement
call — hence the fence. The test sorts the guards in §2 correctly:

* `mmuidslot.S` **passes** (forced): the branch sits at VA `0x0FFE` and the
  image loads flat, so the delay-slot instruction must be the first halfword
  of page 1 and its PA follows from the page-straddle. Same for
  `mmuimiss_illegal.S`, whose `_zero_page` is pinned by a hand-computed
  `.space` pad the VBR/handler offsets depend on (`:252-253`).
* `mmuainc.S` **fails** (not forced): the frame moves by editing two
  constants, `v_pteA` and `k_bkA`. Same for `mmuainc2.S`.

That split is exactly the call §2's repair advice already makes.

Being forced is not an exemption — it still demands a witness, like any other
forced identity. Over-citing (b) therefore costs guard strength, not
soundness: the worst case is an identity-mapped guard that carries a counter
or fault witness anyway, which is the compliant `mmuhuge` category.

### Not a reason: "the bus is not relocated"

An earlier revision of this file (and of four guard headers) claimed that the
MMU emits PA tags only, does not relocate the bus, and that `PA != VA` is
therefore observable only under `cpu_cache_tb`. **That is false**, and it is
worth stating plainly because it hands out a blanket exemption from the rule.

Relocation happens **inside the core**, upstream of any testbench:

* `core/cpu.vhd:811-866` — `g_dstore_squash`, under `if PRIV_ARCH generate`:
  `db_o.a(27 downto 12) <= (ppn_lo and not offm) or (sig_db_o.a(27 downto 12) and offm);`
* `core/cpu.vhd:872-897` — `g_inst_p1_fold`, the identical splice on
  `inst_o.a(27 downto 12)`.

Both rewrite the **external** bus. `sim/cpu_tb.vhd:212-217` passes
`PRIV_ARCH => true`, and `sim/mmu_sim.sh:54` hard-fails the build unless
`cpu_tb.vhh` contains it — so both generates are live under `cpu_tb`. The
`*_pa_tag` port exists only to hand the PIPT caches their tag;
`cache/dcache_ccl.vhm:255` says so: *"PIPT: cpu.vhd relocates the address
upstream of the cache, so a.a is already a PA."*

Two green guards settle it. `mmuwalkdside.S` runs in `mmu_sim.sh`'s default
`cpu_tb` loop (`:131`), maps VA `0x42000`→PA `0x44000` and VA `0x43000`→PA
`0x45000`, and at `:186-209` asserts the stores landed at the **PAs** while the
VA-as-physical words still read `0x11111111`.

`mmuboot.S` is the stronger of the two, because it does not depend on a list
staying current. Its only runner is `sim/linux_sim.sh`, whose build line
(`:69-74`) makes `cpu_ctb` and `cpu_tb` and **nothing else** — there is no
`cpu_cache_tb` target — so `mmuboot` can only ever have run under `cpu_tb`.
It maps VA `0x00100000` → PA `0x00071000` and asserts the readback, and its
own header says why: *"a correct readback after translation proves real
relocation happened, not an identity-map coincidence"* (`:9-11,139-141`).
A guard that could not pass under the stale model has been passing under it
all along.

**So `PA != VA` is a real, cheap witness for every guard under every top.** The
stale claim survived in `mmuxlate.S`, `mmuirun.S`, `mmubenchi.S` and
`mmuidx.S`; all four headers are corrected in the same commit as this file.
None of those guards is *broken* by it — their witnesses are sound — but the
comments caused exactly one wrong audit already.

### Witnesses that count

* An exact `P4_TSBCNT` (`0xFF000054`, `[31:16]=cnt_walks [15:0]=cnt_hits`)
  delta **taken across the access under test**. A snapshot recorded *after*
  the install, compared only for equality afterwards, is a negative check and
  witnesses nothing — see §2.
* An asserted fault count / handler-entry count, or an `EXPEVT` / `MMUFSR` /
  `TEA` / `SPC` value that only a delivered exception can produce.
* The walker's PTEL image read back out of the TSB row.
* An effect only a correct PageMask can produce.
* A `PA != VA` read-back — available under every top, and usually the cheapest
  fix.

---

## 2. Exposed — 8 guards

Identity-mapped on the asserted path, with no independent witness. Each was
read in full and confirmed by hand.

| Guard | Top | Why it is green with the MMU switched off |
|---|---|---|
| `mmuainc.S` | `cpu_tb` | `v_pteA = 0x001000F1` and `k_bkA = 0x00100000` identity-map VA `0x00100000`; the seed is written straight to that PA with AT off. The only assertions are `r0 == VA+4` and `r8 == seed` (`:158,161`). An untranslated `mov.l @Rn+` reads the same seed and increments once. The *subject* — post-increment across a D-side TLB fault — requires a fault that never has to happen. The `_h_tsbhit` / result-29 path lives in the handler, so it is dead unless a fault occurs. |
| `mmuainc2.S` | `cpu_tb` | Identical construction (`:185,187`), `@Rm+`/`@Rn+` co-located variant. Same assertions at `:168-175`. |
| `mmuidslot.S` | `cpu_tb` | `Hptel1 = 0x000010C9` maps VA `0x1000` → PA `0x1000`, and the delay-slot instruction `mov #0x55, r3` is *physically laid out* at `0x1000` (`:257`). With AT off the delay-slot fetch reads the same instruction untranslated, no IMISS fires, `bra idl_target` is taken anyway, and the sole check `r3 == 0x55` (`:228-233`) passes. Handler markers go to the PIO port and are printed, never asserted. |
| `mmuimiss_illegal.S` | `cpu_tb` | `_zero_page` is padded to land at **PA `0x1000` == VA `0x1000`** (`:252-253`, `Hzero_page_pte` `:233`). With AT off the `jmp` to VA `0x1000` fetches `0x0000` directly, raising the same GENERAL_ILLEGAL, and the sole assertion `EXPEVT == 0x180` (`:176-182`) passes. The subject — that I-side IMISS suppression is *transient* — never occurs. |
| `mmupage16k.S` | `cpu_cache_tb` | `PTEL 0x000101E9` → PPN `0x10000` == VA base, so VA `0x11000` resolves to PA `0x11000`. The walk-counter snapshot is taken **after** the step-1 install (`:165-167`) and result 3 only asserts the counter *did not move again* (`:189-194`). With AT off: the store lands at PA `0x11000` (fail 1 passes), PA `0x10000` stays 0 (fail 2 passes), the counter never moves (fail 3 passes). Fully green with the MMU inert. |
| `mmupage64k.S` | `cpu_cache_tb` | Same defect: identity `PTEL 0x000202E9` (`:130`), snapshot after install (`:148`), equality-only counter check (`:173-176`). **Not quite the same construction** — unlike `mmupage16k`, it still carries a sub-page TSB row at `:131`, so its repair patch will differ. |
| `mmupage1m.S` | `cpu_cache_tb` | Same defect: identity `PTEL 0x001004E9` (`:131`), snapshot after install (`:149`), equality-only counter check (`:174-177`). Also still carries a sub-page TSB row (`:132`). `pm=4` (1 MB) is well below the `pm >= 6` threshold, so this identity is *chosen*, not forced. |
| `mmupagewalk.S` | `cpu_cache_tb` | The handler installs `PTEL 0x000101E9`, PA `0x10000` for VA `0x10000-0x13FFF`, so the sub-page store to VA `0x11000` targets PA `0x11000`. Both assertions are P2 read-backs of identity addresses (`:146-158`) and there is no counter, no fault count, and no handler-ran flag anywhere in the file. With AT off the store goes straight to PA `0x11000` and both checks pass, so the "realistic miss handler" it exists to exercise need never run. |

### Suggested repairs

* `mmupage16k` / `mmupage64k` / `mmupage1m`: move the existing `q_walkcnt`
  snapshot to *before* step 1 and add a positive-delta assertion (a new result
  code) alongside the existing equality check. Both properties then hold — the
  base access must walk, the sub-page access must not.
  `mmup4alias.S:156-164` and `mmuwalkhit.S:155-197` are the pattern. Note this
  is **stronger** than merely asserting the counter is nonzero: both catch an
  inert MMU, but only a before/after delta localizes the walk to step 1.
  `mmupage64k` / `mmupage1m` additionally still carry the sub-page TSB row
  that `mmupage16k` deleted, so their patches are not identical.
* `mmupagewalk`: give the handler a non-identity PPN and read back through the
  P2 alias of the *relocated* PA. `mmupagereloc16k.S:122` is the pattern.
* `mmuainc` / `mmuainc2`: `PA != VA` is the cheapest fix and is available —
  point `v_pteA` at a frame other than `0x00100000` and seed `k_bkA` there.
  Both assertions then fail outright if the mapping is absent.
* `mmuidslot` / `mmuimiss_illegal`: here the identity is genuinely load-bearing
  to the *image layout* — the faulting instruction / zero-page is pinned at a
  fixed PA that the VBR and handler-offset arithmetic depend on. Moving it is
  invasive, so the right fix is a handler-entry count asserted `== 1` on the
  pass path, the pattern `mmudslot.S:161-168` and `mmupcprobe.S:234-247`
  already use. (This is a layout constraint, **not** a consequence of the top
  they run under — `PA != VA` would be observable if the layout allowed it.)

---

## 3. Forced identity — 1 guard

**Scope of this section is carve-out (a) only**, the arithmetic one. Guards
whose identity is forced by *layout* — carve-out (b) — and which carry a
witness are classified in §4 with the rest of the not-exposed set, because the
question §4 answers is "what makes this guard's green mean something", and a
layout-forced identity changes the answer not at all. `mmuwalkiside.S`,
`mmusplit.S`, `mmuishadow.S` and `mmudshadow.S` are all in that position (the
`.tlbtext` construction), and all four are in §4. What §2 shows is that
layout-forced identity is *not* a defence on its own: `mmuidslot.S` and
`mmuimiss_illegal.S` are forced by layout too and are exposed, because neither
carries a witness.

| Guard | Why forced | Witness |
|---|---|---|
| `mmuhuge.S` | Leg H3 uses `pm=8` (256 MB). Every PPN bit `page_offset_mask()` leaves live must be zero to keep the PA inside the backed window, so VA `0x300000` == PA `0x300000` is unavoidable. Explained in the header at `:46-57,456-467`. | Legs H1 (VA `0x200000` → PA `0x100000`) and H2 (VA `0x400000` → PA `0x200000`) are non-identity; H3 additionally asserts the walker's PTEL image (`v_ptel_expect_h3`, `:468-476`) and a walker-counter delta (`:396-397`). Compliant. |

`mmuhugefar.S` (arriving with the `test/hugetlb-pte-slot` work) is the worked
example of a header that states the forcing and names its witness; it is the
model to copy.

**Where it runs:** `mmuhuge.S` is absent from `sim/mmu_sim.sh`'s auto-run
lists, but it **does** run in CI. `.github/workflows/full-regression.yml:395`
invokes it by name, and `sim/linux_sim.sh:49` is `name="${1:-mmulinux}"`, so it
is invocable as `sim/linux_sim.sh mmuhuge`. The same holds for `mmulinux`
(`:374`), `mmulinuxexc` (`:381`) and `mmuboot` (`:387`); `pr-quick.yml:102-104`
states it explicitly. Searching only the two shell scripts for literal guard
names misses all four — that is how an earlier revision of this file wrongly
called them unrun. (Those other three are classified in §4, not here; only
`mmuhuge` is forced-identity *by carve-out (a)*.)

---

## 4. Not exposed — 73 guards

Grouped by what carries them. None needs work for this rule.

**No translation under test at all** (no PTE/TSB setup, or AT never enabled) —
the rule does not apply: `mmucmpcsr`, `mmudblflt`, `mmuguard`, `mmureg`,
`mmunest_slotill`, `mmunest_trapa`, `mmutsbslot`, `mmuwalkasid`.

**Non-identity on the asserted path** (the relocated PA is observable under
every top): `mmupage4k` (VA `0x11000` → PA `0x55000`),
`mmupagemix`, `mmupagemix2` (VA `0x14000` → PA `0x44000`), `mmupagereloc16k`
(VA `0x10000` → PA `0x40000`), `mmureloc`, `mmurelocbp`, `mmurelocif` (VA
`0x4000` → PA `0x6000`), `mmuwalkdside` (VA `0x42000` → PA `0x44000`; its
header at `:11-21` records that an identity version of this very guard stayed
green with the demote logic deleted). Also `mmuboot` (VA `0x00100000` → PA
`0x00071000`), `mmulinux`, `mmulinuxexc`, `mmumultihit`, `mmuremap` — these
carry counter or fault witnesses on top of the non-identity map, so they are
doubly covered.

**Walker-counter delta across the access under test** (`0xFF000054`):
`mmubenchi`, `mmuirun`, `mmup4alias`, `mmurun`, `mmusplit`, `mmustale`,
`mmutsbcoh`, `mmutsbvictim`, `mmuwalkhit`, `mmuwalkiside`, `mmuwalkmiss`,
`mmuwalkorder`, `mmuwalkorderhit`, `mmuwalkrearm`, `mmuwalkway1`, `mmuxlate`.

The two shadow-fill guards belong to this group, and both were read in full for
this re-audit rather than bucketed — a guard whose subject is "an install that
did NOT happen" is exactly the shape that goes vacuous under identity.
Both map their observed page identity (VA `0x00008000` == PA `0x00008000`,
`PTEL 0x000080C9`), forced by layout in the sense of carve-out (b): the page is
the linker's `.tlbtext` section, fixed at VA `0x00008000` by
`sim/tests/sh32_tlbtext.x`, and the cosim loads the image flat, so the
instructions physically *are* at `0x8000`. Editing `p_ptel_x` / `p_ptel_wx`
alone would point the mapping at a frame that contains no code — the same
construction `mmuwalkiside.S` and `mmusplit.S` already use.

| Guard | Verdict | Witness |
|---|---|---|
| `mmuishadow.S` | carried | Result 3 asserts the walk counter is **nonzero** before the probe (`:225-229`), so an inert `AT` — which walks nothing — fails there and never reaches the decisive check. |
| `mmudshadow.S` | carried | Result 3 is a true before/after walk-counter delta across leg 1a's D-side load (`:143-153`), and leg 2 asserts an exact `TLBINST` (`0xFF000058`) delta of +1 ITLB / +0 DTLB writes across the jump (`:266-294`). |

`mmuishadow`'s equality-only check (result 4, "the counters did not move across
the literal-pool load") is the *subject*, not the witness — read on its own it
is the same negative check §2 faults `mmupage16k` for. What separates them is
that result 3 runs first and is positive. Its nonzero-rather-than-delta form is
the fragility noted under "Closest calls" below.

**A fault must fire** — `EXPEVT` / `MMUFSR` / `TEA` / `SPC` pinned, or a
handler-entry / fault count asserted, so an inert MMU produces "no exception"
and fails: `mmuasid`, `mmuasidsh`, `mmudrain`, `mmudslot`, `mmudspcprobe`,
`mmudspcprobe_late` (and its five `#include` variants `_lateb`, `_latec`,
`_latem`, `_latemw`, `_latew`), `mmufault`, `mmufaultage`, `mmufsr`,
`mmuglobal`, `mmuidorder`, `mmuidx`, `mmuimiss`, `mmuimissrest`, `mmumhorder`,
`mmunest`, `mmupcprobe`, `mmurestartpc`, `mmurte`, `mmusmep`, `mmusr`,
`mmushadowld`, `mmushadowst`, `mmustcldslot`, `mmustore`, `mmustr2`,
`mmustres`, `mmutsb`, `mmuvecsplit`, `mmuwalkstale`, `mmuwalktorn`.

**Other structural witness**: `mmubench` (software walker-call counter must
equal 4), `mmudcbit` (leg B's expected bypass result requires `at=1`, because
`is_cacheable_mmu` falls back to region-decode when `at=0` —
`cache/cache_pkg.vhd:106-114,960-983`), `mmuicolor` (the two legs must
*diverge* on the PTE C-bit; an inert MMU makes them identical).

### Closest calls

`mmutsbvictim.S:209-214`, `mmuwalkiside.S:203-210` and `mmuishadow.S:225-229`
assert the walker counter is **nonzero** rather than taking a before/after
delta. That is sound only
because each image is the whole simulation and the counter starts at 0, so
"nonzero" is a from-zero delta. It is fragile reasoning — the moment such a
guard gains an earlier walk, the check stops witnessing the access under test.
Prefer an explicit delta.

`mmuishadow.S` is the sharpest instance: its baseline is read after BOTH the
code page's own walk and the observed page's I-side walk, so the nonzero result
does not distinguish which of the two ran. It still fails on an inert MMU, which
is what the rule asks for, but a before/after pair around the `jmp` — which its
companion `mmudshadow.S` already takes — would witness the access under test
instead of the run so far.

`mmuidorder.S:355`'s inline comment "(4) NOT ASSERTED" is stale — the check is
live in the current `.word 0x6CD2` build. It does not change the verdict
(checks 1-3 carry the guard), but the comment should be corrected.

---

## 5. Coverage of this survey

* **87** `mmu*.S` files exist. **82** are distinct guards; the other 5
  (`mmudspcprobe_late{b,c,m,mw,w}.S`) are `#define` + `#include` shims over
  `mmudspcprobe_late.S` and inherit its verdict. (85/80 at the original survey
  date; `mmuishadow.S` and `mmudshadow.S` arrived with `a68c765`.)
* All 82 were classified, and none was left `UNKNOWN`. **The evidence behind
  those verdicts is not uniform**, and the difference matters when acting on
  this file:
  * The 8 exposed guards in §2, plus the named guards cited with line numbers
    in §3 and §4 (`mmupage4k`, `mmupagemix`, `mmuwalkdside`, `mmuxlate`,
    `mmuhuge`, `mmutsbvictim`, `mmuwalkiside`, `mmuidorder`, `mmudcbit`), were
    read in full and hand-verified against their `PTEH`/`PTEL` constants and
    assertion sequences.
  * `mmuishadow` and `mmudshadow` were likewise read in full, in the
    2026-08-23 re-audit; their verdicts are in §4 with line citations.
  * The remaining ~60 appear as bare names in the §4 prose groups. They were
    bucketed by witness class in a delegated pass and spot-checked, **not**
    individually line-cited. Treat those as a well-founded classification, not
    as a per-guard proof. Anyone repairing or re-auditing a specific guard from
    §4 should re-derive it.
* **Not covered:** the `m8_*` guards, `exctest`, `banktest`, the `dualcore/`
  images, and Lane 2's kernel-object path. `dualcore/mmusmpasid.S` (new with
  `1883b2d`) does TSB/PTEL work and is in scope for this rule, but the
  `dualcore/` tree was out of the corpus at the original survey and stays out
  here rather than being half-audited — it joins the named follow-up below.
* **Named follow-up: the `m8_*` guards are a real nine-guard gap.** 9 of the 12
  do TSB/PTEL work and are in scope for this rule but were not surveyed:
  `m8_idslot_{0,1,2}`, `m8_ifetch_{0,1,2}`, `m8_dside`, `m8_dsdslot_0`,
  `m8_multihit_ifetch`. They should get the same pass, together with
  `dualcore/mmusmpasid.S`.
* Nothing was simulated. Every verdict is by construction from the source, not
  from a mutation run. Confirming an exposed guard is *actually* vacuous means
  deleting the `MMUCR.AT` enable and observing it stay green — that is the
  natural first step of each repair, per CLAUDE.md's "Mutate it and confirm
  red."
