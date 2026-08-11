# J4 TLB — Software & Security Architecture

The user/programmer view of the J4 MMU's translation lookaside buffer: what the TLB
guarantees, the contract a kernel must uphold to use it safely for multi-tenant
isolation, and the security properties it does and does not provide. For the
hardware block view and synthesis cost see [j4.md](j4.md); the RTL is
[`core/tlb.vhd`](../../core/tlb.vhd) (instantiated in `core/cpu.vhd` under
`g_mmu : if PRIV_ARCH generate`). The behaviour described here is locked by the
`sim/tests/mmu*.S` regression guards (named per property below).

> **Audience:** OS / hypervisor / firmware authors and security reviewers. This
> document is normative for *how software must use the TLB*; the `*.toml` decode
> spec and `core/tlb.vhd` are authoritative for the encodings and hardware.

---

## 1. What the TLB is

> **IN-PROGRESS WORK — read before editing MMU RTL.** A hardware **TSB**
> walker is being added on branch `mmu/tsb-hw-walker`. It changes a TLB miss
> from an exception into a pipeline **stall**: on a TSB hit the entry installs
> and the access replays with **no exception taken at all** (`SPC`, `SSR`,
> `EXPEVT`, `PTEH`, `TEA`, `MMUFSR` untouched). On a walk failure the
> exception fires exactly as described in this document.
>
> There is still **no hardware page-table walker** — the walker probes the
> flat TSB hash array only; `pgd`/`pmd`/`pte` stay private to software. That
> distinction is the point, not a technicality.
>
> **Phase 2 is now IN THIS BRANCH (not merged).** The TSB is **2-way**: a set
> is one 32-byte cache line holding two contiguous 16-byte entries, way 0 at
> `+0` and way 1 at `+16`, and the walker probes both. `TSBBR.TSB_SIZE_LOG`
> counts **sets**, `tsb_ptr()` scales by `<< 5`, and **`ASID` is folded into
> the index** rather than only compared as a tag. `TSBPTR` presents the
> **set** address; software reads the line, compares both tags, and writes the
> matching way, or the way hardware nominates. Three new P4 registers:
> `TSBSLOT` (`0xFF000048`, write a VA / read its set address), `TSBVSEED`
> (`0xFF00004C`, **write-only** victim-LFSR seed) and `TSBVICT`
> (`0xFF000050`, **read-only** 1-bit way nomination; the read advances the
> LFSR).
>
> **The `ASID` fold is hardening, not isolation, and must not be described as
> isolation anywhere.** It is XOR-separable — `hash = f(vpn) ⊕ g(asid)` — and
> this is an open-source core, so `g` is public and the remaining unknown fits
> in `2^TSB_SIZE_LOG` (64–1024) offsets, brute-forceable by timing probes. It
> removes the zero-effort same-VA eviction primitive and improves
> distribution; that is all it does. The isolation mechanism is per-domain TSB
> partitioning via `TSBBR` (`docs/mmu/hardware-spec.md` §2.13a).
>
> **Phase 3 IS NOW IN THIS BRANCH.** The seven MMU encodings are **retired**:
> `STC {TSBPTR,PTEH,PTEL,ASIDR},Rn`, `CMP/EQ {PTEH,ASIDR},Rn` and
> `LDTLB.RN Rm` all decode to **General Illegal**. `LDTLB` (`0x0038`) and the
> parameterless `LDTLB.RN` (`0x0078`) survive, as do the three
> `LDC Rm,{PTEH,PTEL,ASIDR}` writes (design D7 — the write side has no MMIO
> equivalent). The CSRs are now **read** through read-only P4 aliases: `PTEH`
> `0xFF000000`, `PTEL` `0xFF000004`, `ASIDR` `0xFF000038`, `TSBPTR`
> `0xFF00001C`. The walker's `cnt_walks`/`cnt_hits` counters moved to P4
> `0xFF000054` (and are guest-observable — see
> `../../../docs/hypervisor/design-spec.md` §6). The encoding family
> `0000 nnnn xxxx 1011` is empty: **8 free slots, all virgin.** Anything below
> that still shows a retired mnemonic is describing history, not the ISA.
>
> **Fmax:** Phase 3 repaid +10.3 % (25.82 → 28.49 MHz), leaving −6.1 % against
> the pre-walker 30.34 MHz — see [j4.md](j4.md), "Fmax: the hardware TSB
> walker, measured". The gain was **congestion relief, not logic depth**.
>
> Design: `../../../docs/superpowers/specs/2026-08-09-hardware-tsb-walker-design.md`.
> Spec: `../../../docs/mmu/hardware-spec.md` §5.0, §2.8, §2.8a, §2.12, §2.13.
> Guards (`sim/tests/`): `mmuwalkway1` (the real 2-way conflict case),
> `mmuwalkasid` (the `ASID` fold moves the index), `mmuwalktorn`,
> `mmuwalkorder` (fault-dispatch ordering), `mmuwalkhit`, `mmuwalkmiss`,
> `mmuwalkstale`,
> `mmuwalkdside`, `mmuwalkiside`.

- **32-entry, fully associative, software-loaded.** There is **no hardware
  page-table walker.** On a TLB miss the core raises an exception and a
  privileged software handler reads the page tables / TSB and installs the
  mapping with `LDTLB` (or the fused `LDTLB.RN`). This is the single most
  important design fact: *translation correctness, permission setup, and
  invalidation are entirely software's responsibility* — the hardware only
  matches, enforces the installed permissions, and relocates.
- **4 KB base; variable up to 1 GB via the per-entry PageMask field at `PTEL[11:8]`.**
  pm=0 gives 4 KB (the common case), pm=1 gives 16 KB, pm=2 gives 64 KB, pm=3
  gives 1 MB, and so on in powers of four up to 1 GB.  The comparison is a masked
  VPN check; the relocation offset width scales with pm.
- **Parallel I-side and D-side lookup**, combinational, every cycle an access is
  presented. A hit costs no extra cycles; a miss faults.
- **Physically-indexed caches (PIPT).** On a hit the virtual address is relocated
  to the physical address *before* it reaches the L1 caches, so the caches index
  and tag on physical addresses. Software does **not** need page-colouring.

Translation is active only when `MMUCR.AT = 1` and only for the translated
segments **P0** (`0x0000_0000–0x7FFF_FFFF`, user + kernel) and **P3**
(`0xC000_0000–0xDFFF_FFFF`, kernel). The untranslated segments are unaffected:
**P1** (`0x8…`) is the cached physical window (`PA = VA & 0x1FFF_FFFF`), **P2**
(`0xA…`) the uncached physical window, **P4** (`0xE…`/`0xF…`) the privileged
control/MMIO region. Kernels run their miss handler and page tables from P1/P2 so
the handler itself never faults.

---

## 2. The TLB entry (per-bit semantics)

Each entry is installed from the `PTEH`, `PTEL`, and `ASIDR` registers by `LDTLB`.
The fields, and what each means to software:

| Field | Source | Meaning (software view) |
|---|---|---|
| `VPN` | `PTEH[31:12]` | Virtual page number tag. Captured by hardware on a miss at 4 KB granularity. The match compares only the bits unmasked by `PageMask`; the masked (sub-page) bits are preserved for PA relocation. |
| `PageMask` | `PTEL[11:8]` | Per-entry page size selector. `0`=4 KB, `1`=16 KB, `2`=64 KB, `3`=1 MB, … up to 1 GB. Controls how many low VPN bits are masked out of the compare and passed through as the PA offset. |
| `ASID_TAG` | `ASIDR[15:0]` | The owning context tag (12-bit ASID + 4-bit generation, kernel-encoded). An entry is private to this tag unless `GLOBAL`. |
| `PPN` | `PTEL[31:10]` | Physical page number. `PA = PPN << 10` (low bits from the virtual offset). |
| `V` (valid) | `PTEL[0]` | Entry occupied. Cleared by reset and by the `MMUCR.TI` flush. |
| `STALE` | `PTEL[1]` | **Soft-invalidate / revocation marker — enforced in hardware.** A `STALE=1` entry never hits (the access faults as a miss). See §6. |
| `G` (global) | `PTEL[2]` | Match regardless of `ASID_TAG`. **Kernel pages only** (see §5 invariant). |
| `C` (cacheable) | `PTEL[3]` | `1` → access goes through the L1 cache; `0` → uncached bypass straight to memory. |
| `D` (dirty) | `PTEL[4]` | Loaded but not enforced by hardware in the reference build (no initial-write fault). Software may use it for dirty tracking. |
| `U` (user) | `PTEL[5]` | Page is accessible from user mode (`SR.MD=0`). If `0`, only the kernel may touch it. |
| `X` (execute) | `PTEL[6]` | Page may be fetched as instructions. |
| `W` (write) | `PTEL[7]` | Page may be stored to (enforced for kernel and user alike). |

> **PTEL flag layout (implementation):** `W7 X6 U5 D4 C3 G2 STALE1 V0`. So a
> cacheable user RWX page = `0xE8` (`W|X|U|C`), the same page uncacheable = `0xE0`,
> add `STALE` = `0xEA`. `PPN = PTEL[31:10]`, so for physical address `PA`
> (4 KB-aligned), `PTEL = (PA & 0xFFFF_FC00) | flags`. *(The architectural
> hardware-spec uses a different nominal bit numbering; this repo's decode spec
> and RTL use the layout above — that is what software targets here.)*

There is **no separate read-permission bit**: readability is governed by `U` (for
user) or by being the kernel. `W` and `X` are independent, so the kernel
implements W^X by never setting both on the same page.

---

## 3. The lookup and permission model

On every access (with `AT=1` and a translated segment) the TLB evaluates, per side:

```
hit  = VALID ∧ (STALE = 0) ∧ ((VPN & ~PageMask) = (VA[31:12] & ~PageMask)) ∧ (GLOBAL ∨ ASID_TAG = ASIDR)
```

The VPN compare is **masked by the entry's `PageMask`**: bits within the page are
zeroed before comparison, so a single entry covers the entire large page.  On a
hit, the relocation offset is `VA[11+2*pm:0]` (the unmasked sub-page bits), so the
correct physical byte within the large page is addressed.

Only on a **hit** is the permission predicate evaluated. A violation raises the
access-type protection exception and **suppresses the memory effect** (a faulting
store is demoted to a non-mutating read on the external bus):

| Access | Protection fault when | Exception (vector offset) |
|---|---|---|
| Instruction fetch | `X=0` **or** (`U=0` and `MD=0`) | `IPROT` (`0x0A0`) |
| Data load | `U=0` and `MD=0` | `DPROT_R` (`0x0C0`) |
| Data store | (`U=0` and `MD=0`) **or** `W=0` | `DPROT_W` (`0x0C0`) |

A **miss** (no matching entry) raises `IMISS` (`0x040`), `DMISS_R` (`0x060`), or
`DMISS_W` (`0x080`) by access type. `EXPEVT` holds the cause and `TEA`
the faulting virtual address (both privileged-read only).

**Misses and protection faults take different vectors**, as on SH-4: the three
miss causes vector to `VBR+0x400`, the three protection causes to `VBR+0x100`
(the general exception vector, shared with Error / Slot Illegal / General
Illegal / TRAPA). The miss handler therefore never has to ask which kind of
fault it is. That matters for more than speed: a protection fault against a
VPN/ASID that still has a valid TSB slot would TSB-hit on the miss path, and
reinstalling the same entry livelocks — the split excludes that by
construction rather than by a software check. *Guard: `mmuvecsplit`.*

A supplementary read-only register, `MMUFSR` (MMU Fault Status Register, P4 MMIO `0xFF00002C`), latches the fault-cause `KIND` and access-type flags alongside `TEA` and `PTEH`. Its low byte is deliberately formatted as a Linux `FAULT_CODE_*` image: `[0] WRITE`, `[2] ITLB`, `[3] PROT`, `[4] USER`; the high nibble encodes `KIND` (1–7: miss/prot variants, 0 if no fault latched). **Critically, `MMUFSR` distinguishes `DPROT_R` from `DPROT_W`**, which both report `EXPEVT=0x0C0` and vector to `VBR+0x100`. The entire low byte for a `MULTI_HIT` fault is zero (since it is not a page fault). Software must read `MMUFSR` in the exception prologue; it is overwritten by the next fault.

**Privileged-mode (`MD=1`) rules.** The kernel honours `X` and `W` (it cannot
execute an `X=0` page nor write a `W=0` page — the `MD` term gates only the `U`
check). The kernel does **not** enforce `U` against itself: it may read, write,
and execute user (`U=1`) pages. There is **no SMEP/SMAP-equivalent**; a kernel
that must not trust tenant-controlled user pages has to arrange that in software.

On a hit the physical address is formed as `PA = {0000, PPN[27:13], PPN[12],
VA[11:0]}` (28-bit physical region) and used to index the PIPT L1 caches; `C`
selects cache vs. uncached bypass.

*Guards: `mmuxlate` (basic translate), `mmufault` (all six miss/prot classes
incl. user-mode `IPROT`/`DPROT_R` and `DPROT_W`), `mmufsr` (fault status register
and `DPROT_R`/`DPROT_W` discrimination), `mmureloc`/`mmurelocif`/
`mmurelocbp` (VA→PA relocation for D, I, and the C=0 bypass).*

---

## 4. The kernel's contract — installing and using mappings

1. **Set up untranslated handler memory.** Place the miss handler, page tables,
   and TSB in P1/P2 so they are reachable with `AT=1` without faulting.
2. **Per context switch:** write the new context tag to `ASIDR`
   (`LDC Rn, ASIDR`). This single register is *both* the lookup context and the
   tag stamped onto subsequently-installed entries.
3. **Enable translation:** `MMUCR.AT = 1` (P4 MMIO at `0xFF00_0010`).
4. **On a miss exception:** hardware has latched `TEA` (faulting VA), `PTEH`
   (faulting VPN at 4 KB granularity), and `TSBPTR` (the TSB hash slot). The
   handler stages `PTEH`/`PTEL` (and re-asserts `ASIDR` if needed) for the target
   mapping and issues:
   - `LDTLB` (`0x0038`) — install `{ASIDR, PTEH.VPN, PTEL}` into an NRU-chosen
     slot, then return via `RTE`; **or**
   - `LDTLB.RN` (`0x0078`) — the fused *install-and-return*. **It has NO delay
     slot.** A trailing `nop` in handler examples is padding, not an architectural
     delay slot, and must not carry a meaningful instruction.
5. **Replacement** is NRU (not-recently-used) across the 32 entries; software does
   not choose the slot, EXCEPT that dedup takes priority over NRU: an `LDTLB`
   whose install overlaps an already-resident, valid entry (same masked VA
   range under the ASID/global rule — this subsumes plain `VPN+ASID` equality)
   overwrites that resident entry in place instead of adding a second one.
   This is what makes routine re-installs (e.g. upgrading a still-resident
   page's permission/dirty bits) and page-size transitions (e.g. installing a
   4 KB page inside a resident 1 MB hugepage, or vice versa) safe: the
   overlapping resident mapping is evicted at install time, so the two
   mappings never coexist and a subsequent lookup is a clean single hit. See
   §8.1 for the full multi-hit story, including the one case this dedup
   cannot reach and why the hardware still detects it.

All MMU registers and instructions (`PTEH`, `PTEL`, `ASIDR`, `MMUCR`, `TSB*`,
`LDTLB`, `LDTLB.RN`) are **privileged**: a user-mode access traps illegal-instruction.
*Guards: `mmureg` (register round-trip + no cross-clobber), `mmuguard`/`privmode`
(user access traps), `mmuldtlbr` (fused install+return), `mmusr` (SR/bank state on
exception entry).*

---

## 5. Isolation & security model (multi-tenant)

The TLB is the isolation boundary between mutually-distrusting user tenants under a
trusted kernel. The guarantees, and the software invariants they depend on:

- **Per-tenant separation via ASID.** Each live address space has a unique
  `ASID_TAG`. A non-global entry installed under tenant A's ASID **cannot** be
  used while `ASIDR` holds tenant B's ASID — the match requires
  `ASID_TAG = ASIDR`. *Software invariant:* never assign the same live ASID to
  two address spaces; on ASID **recycle** (and on generation-counter wrap) flush
  the affected entries / rebuild the TSB, because only 4 bits of the tag are the
  generation discriminator. *Guard: `mmuasid` (an A-tagged entry faults under B;
  a global page keeps working across the switch).*
- **Global pages are kernel-only.** A `GLOBAL` entry matches under every ASID —
  that is how shared kernel mappings work. **Invariant (no hardware guard):** set
  `G=1` *only* on kernel-owned pages. `G=1` on a tenant page exposes it to every
  tenant.
- **Permission enforcement.** `U/W/X` are enforced in hardware per §3 for every
  access type and for user vs. kernel mode. *Guard: `mmufault`.*
- **Confidentiality of privileged state.** `TEA`, `EXPEVT`, `PTEH`, `PTEL`,
  `ASIDR`, `TSBPTR` are privileged-read only; no user-visible register exposes
  another context's VPN/PPN/ASID/fault address.
- **Faulting accesses do not leak or mutate.** A protection-violating store is
  demoted to a non-mutating read; the result of any faulting access is squashed
  before it reaches an architectural register. *Guard: `mmustore`.*

### Threat model in one paragraph

The **kernel (`SR.MD=1`) is the TCB.** The **adversary** is an unprivileged tenant
(`SR.MD=0`) running arbitrary user code, able to issue any user instruction and to
fault deliberately. The TLB **guarantees**: no user access to memory outside its
own live ASID with the required permission; `U/W/X` enforcement; confidentiality of
privileged MMU/exception state; and that a revoked mapping (flushed or `STALE`)
cannot be used. It does **not** guarantee resistance to timing/cache side channels
or to DRAM-level (Rowhammer) effects — see §7.

---

## 6. Revocation — STALE bit and TI flush

There is no single-entry-invalidate instruction. Software revokes a mapping two
ways:

- **`MMUCR.TI` flush** clears `VALID` (and the NRU state) on all entries. Use on
  address-space teardown / ASID recycle. *Guard: `mmurun` exercises flush →
  software re-walk.*
- **`STALE` bit** (`PTEL[1]`): re-install the entry with `STALE=1` to soft-invalidate
  a single mapping. **Hardware enforces it** — a `STALE=1` entry never hits, so the
  next access faults back into the trusted miss handler. *Guard: `mmustale`.*

**Critical invariant:** before a physical page is reassigned to a different tenant,
every TLB entry that maps it **must** be flushed or marked `STALE`. The hardware
does *not* auto-invalidate on page-table edits; a forgotten invalidation is a
cross-tenant read/write (a "TLB-desync"). This is the highest-frequency real risk
of a software-loaded TLB.

---

## 7. Security properties and non-guarantees

**Immune by construction (do not spend defensive effort here).** J4 is in-order,
single-issue, strictly **non-speculative** (no out-of-order execution, no data/target
speculation, no prefetcher). This neutralises the entire transient-execution attack
class — Meltdown, all Spectre variants, L1TF/Foreshadow, MDS/RIDL/ZombieLoad,
Retbleed, Downfall, Inception — because an architecturally-forbidden access is never
performed; there is no transient window. The **software** TLB walk likewise removes
the hardware-page-table-walker cache-timing class (AnC). *The one caveat:* a future
microarchitectural optimisation that adds speculation, a forwarding load buffer, or
a prefetcher would reintroduce this surface and must be re-reviewed.

**Residual surface (real, but bounded).**
- **Timing / covert channels** on the shared L1 caches and 32-entry TLB
  (Prime+Probe, Evict+Time, TLB occupancy, deterministic-NRU eviction sets,
  data-dependent software-miss-handler timing). Bounded by the single-hart,
  non-SMT design (no concurrent observation) and the low clock. Optional
  mitigations: flush L1+TLB on context switch, a constant-time/constant-memory
  miss handler, and mapping secret pages uncacheable (`C=0`).
- **TSB contention** (Phase 2, in this branch, not merged). The TSB is per-CPU
  and shared across address spaces, and a hit is ~11× cheaper than a miss, so
  conflict-based prime+probe against it is real. Phase 2 folds `ASID` into the
  TSB index and adds an OS-seeded victim LFSR. **Both are hardening and neither
  is a boundary** — the fold is XOR-separable and public in an open-source
  core, and the residual unknown is a 64–1024-entry offset space that timing
  probes can search. What they buy is the removal of the *zero-effort*
  same-VA eviction primitive and an unpredictable eviction choice. The actual
  boundary, for a deployment that needs one, is **per-domain TSB partitioning**
  — disjoint index ranges per trust domain, switched by writing `TSBBR`, which
  needs no RTL change (`docs/mmu/hardware-spec.md` §2.13a).
- **Rowhammer** and other DRAM-level effects — a function of the SDRAM part and
  the physical allocator, not the core; the good CPU properties do not help here.
- **Software correctness** in ASID recycle, global-bit hygiene, revocation, and
  the nested-fault/exception path — by far the dominant risk, and entirely in the
  kernel's hands.

### 7.1 Handler residency — a hard requirement on the kernel

**TLB faults are not detected while `SR.RB=1`.** Both detection paths in
`core/cpu.vhd` are gated on `dp_sr.rb = '0'` — the I-side at the
`i_at_translated` branch and the D-side at the `exc_en = '0' and
d_at_translated = '1' ...` branch. Exception entry sets `RB=1`, so a handler
cannot itself take a TLB fault.

This is deliberate and it is what makes nested TLB faults structurally
impossible: `core/cpu.vhd`'s `g_dblflt` gate converts an INTERRUPT/ERROR at
`RB=1` and a nested `illegal_instr` into a defined `RESET_CPU`, but it does
**not** cover a nested TLB exception. Nothing needs it to, because no such
exception can be raised.

**The cost, and the requirement it imposes.** Suppressing the fault does *not*
suppress translation. `i_at_translated` / `d_at_translated` are functions of
`MMUCR.AT` and the segment alone (`SEG_P0` / `SEG_P3`), not of `RB`. So a
handler running in P0/P3 with `AT=1` is still translated, and on a TLB miss
neither arm of the address-fold applies, so **the virtual address is passed to
the bus as the physical address**. The access silently goes to the wrong place;
no exception reports it.

Therefore:

> **Invariant.** Handler code, its literal pools, its stack, and every datum it
> touches before it can re-establish a mapping MUST be either in **P1/P2**
> (fixed-translate, never TLB-dependent) or in **P0/P3 pages guaranteed
> resident** for the lifetime of the handler. A TLB-fault handler that can miss
> on its own working set does not fault — it silently reads and executes the
> wrong physical addresses.

Linux takes the P1 route: `sim/tests/Makefile` links `mmulinux`, `mmuboot` and
`mmuhuge` with `sh32_p1.x`, so `jcore_vbr_base` and the whole miss path live at
P1. `sim/tests/m8_runtime.inc` does the same by calling every runtime helper
through its `0x80000000 +` alias. The bare-metal guards that *do* put handlers
in P0 (`mmufaultage.S`, `mmuidorder.S`) satisfy the invariant the other way, by
identity-mapping page 0 before enabling `AT` and never evicting it.

This invariant is currently unenforced and unguarded — nothing fails if a
kernel violates it. See the note in §9.5.

The full attack-landscape analysis, spec review, and implementation review are in
the design repository's `docs/mmu/security-review.md`.

---

## 8. Property → guard map

| Security / correctness property | Guard(s) |
|---|---|
| Basic VA→PA translation | `mmuxlate` |
| Ordered delivery: older held D-side fault vs younger deferred I-fetch fault | `mmuidorder` |
| I-side MULTI_HIT does not pre-empt an older in-flight D-side access | `mmumhorder` |
| Handler residency invariant (§7.1) | **none — unguarded** |
| Permission enforcement (U/W/X, user + kernel, all 6 classes) | `mmufault` |
| ASID cross-tenant isolation + global-bit | `mmuasid` |
| STALE single-entry revocation | `mmustale` |
| TLB flush → software re-walk | `mmurun` |
| VA→PA relocation (D / I / C=0 bypass) | `mmureloc`, `mmurelocif`, `mmurelocbp` |
| Faulting store does not mutate memory | `mmustore` |
| Per-access fault vectors + EXPEVT/TEA | `mmufault`, `mmuimiss` |
| Fault status register (DPROT_R vs DPROT_W discrimination) / fault status latching | `mmufsr` |
| Privileged-register / instruction trap | `mmureg`, `mmuguard`, `privmode` |
| SR / bank state on exception entry | `mmusr` |
| Precise-exception fault transparency (MAC, auto-inc, …) | `m8_*` family |
| Variable page size (PageMask) | `mmupage4k`, `mmupage16k`, `mmupage64k`, `mmupage1m`, `mmupagemix`, `mmupagemix2`, `mmupagewalk` |
| Hardware TSB walk installs without an exception (SPC/SSR/EXPEVT untouched) | `mmuwalkhit` |
| Walk failure still vectors exactly as before | `mmuwalkmiss` |
| `V=0` / `STALE=1` entries do not install | `mmuwalkstale` |
| Torn TSB entry never installs a mismatched translation (store order) | `mmuwalktorn` |
| A live walker does not disturb older-instruction-first fault dispatch | `mmuwalkorder` |
| D-side ack-withholding; I-fetch walk while the data bus is borrowed | `mmuwalkdside`, `mmuwalkiside` |
| **2-way TSB: way-1 hit on a real conflict** (Phase 2) | `mmuwalkway1` |
| **`ASID` participates in the index, not only the tag** (Phase 2) | `mmuwalkasid` |
| TSB contention as an isolation boundary (per-domain partitioning, §7) | **none — it is a software/hypervisor policy, not an RTL property** |

> ### 8.1 S-I5 — multi-hit: install-time overlap eviction, with hardware
> detection retained as defence-in-depth
>
> A **multi-hit** is >1 usable (`VALID`, not `STALE`, VPN-in-range,
> ASID-or-`GLOBAL`) entry matching one lookup. It is a **defined,
> non-recoverable fault** (`i_multihit`/`d_multihit`, routed to the existing
> General Illegal exception, `EXPEVT=0x180`) rather than a silent
> last-match-wins pick of one candidate PA — an unspecified choice among N
> live PAs is exactly the address-confusion primitive S-I5 exists to deny.
>
> **The common cause used to be install-time page-size aliasing**, and it is
> now resolved before it can reach the lookup path: `LDTLB`'s install dedup
> (item 5 above, §5.1) compares the new mapping against every resident entry
> under the **intersection of the two entries' page masks** (the coarser/wider
> of the two) rather than exact `VPN` equality. A 4 KB page installed inside a
> resident 1 MB hugepage — or a hugepage installed over a resident 4 KB page —
> has a *different* raw `VPN` from the entry it overlaps, but the masked
> compare still recognises the range overlap and evicts the resident entry in
> place. Exact-`VPN`-equality re-installs (e.g. a permission/dirty-bit update)
> are the special case where both page masks are 4 KB, so this dedup subsumes
> the old exact-match dedup entirely. **Practically: normal `LDTLB` sequences,
> including page-size transitions, no longer produce a multi-hit fault** —
> splitting or growing a mapping no longer requires a manual `STALE`/`TI`
> flush of the overlapped entry first (though doing so is still harmless).
>
> **The install dedup deliberately does NOT gate on `STALE`**, unlike the
> lookup path (§6): a `STALE=1` resident entry is a soft-invalidated-but-still
> -occupying-a-slot mapping, not an absent one, and an install that ignored it
> could overlap a range it can no longer see, defeating the whole point of the
> check. The lookup path, symmetrically, *does* gate on `STALE` — a stale
> entry must never hit. This asymmetry (install considers stale entries;
> lookup suppresses them) is intentional and load-bearing, not an oversight.
>
> **Multi-hit detection in the RTL is unchanged and still present as
> defence-in-depth.** `LDTLB`'s dedup only evicts the *first* resident entry
> it finds overlapping the new install (single-slot replacement, matching
> SH-4 `LDTLB` semantics) — it does not sweep and evict every overlapping
> entry. A pathological sequence where **two or more pre-existing, mutually
> non-overlapping entries independently overlap one new install** can still
> leave a genuine multi-hit: dedup evicts only the first match it scans, the
> remaining overlapping entry survives untouched, and a lookup landing in the
> shared range will hit both. This is a narrow, avoidable case (well-behaved
> software installs mappings in an order that does not construct it), and any
> other genuinely inconsistent SW/HW state that manufactures duplicate
> matching entries is caught the same way. The hardware fault is retained
> specifically to catch these, not because normal install sequences are
> expected to trigger it anymore.
>
> *Guards: `mmumultihit` (dedup — exact-VPN re-install and page-size-aliasing
> overlap, both resolved at install with no fault; kept as regression coverage
> for the eviction path), `mmupagemix`/`mmupagemix2` (mixed page-size
> transitions).*

---

## 9. Instruction-restart contract — base-register writeback

### 9.1 The rule

> **On a precise TLB fault, the base register of an access that specifies base
> writeback is left at its pre-instruction value — for every such instruction,
> uniformly, including multi-operand forms.**

This is ARM's **Base Restored Abort Model**, adopted verbatim in intent. ARM DDI
0100I (§A2.6.6) defines it as *"If a precise Data Abort occurs in an instruction
that specifies base register write-back, the value in the base register is
unchanged"*, and makes it mandatory from ARMv6. The sentence that matters most
here is the one that follows:

> *"In either case, the abort model applies uniformly across all instructions. An
> implementation does not use the Base Restored Abort Model for some instructions
> and the Base Updated Abort Model for others."*

**Why this has to be written down here.** The SH ISA does not specify it. The
instruction reference lists `Data TLB miss exception` for `@Rm+`/`@-Rn` forms but
never states the base register's post-exception value, and its pseudocode models
no fault path. SH *does* specify restart semantics elsewhere — `DIVS`/`DIVU`
("*the return address will be the start address of this instruction, and this
instruction will be re-executed*"), `MOVLI.L` (LDST cleared on exception) — so the
omission is specific, not a general silence. Nothing upstream will define this for
J4; the choice is ours, and the cost of leaving it undefined is one defect per
addressing mode.

### 9.2 Why a 5-stage in-order pipeline needs the rule at all

The classic discipline is to commit architectural state in program order at a
single point — writeback — so that a fault flushes everything younger by
construction and nothing older is ever lost. An ISA with no base writeback
(MIPS I: *"Only one addressing mode is supported: base + displacement"*) gets this
almost for free.

SH has `@Rm+`, `@-Rn`, and MAC forms with *two* base updates, so J4 cannot. Where
an instruction mutates a base **before** the access that may fault, the machine
must either suppress that write or undo it. Both mechanisms exist in
`core/datapath.vhm`; §9.4 says which applies where.

### 9.3 The three models currently in the machine

Enumerated mechanically from `decode/gen-go/spec/` — every instruction whose
operand syntax carries a base writeback (`@Rx+` or `@-Rx`), classified by *when*
the base write commits relative to the faulting access:

| Model | Count | Shape | Restart cost |
| --- | --- | --- | --- |
| **A — deferred** | 7 | base write is in a slot **after** every access | Restart-safe *by construction*; no restore needed |
| **B — bump-first** | 9 | base write commits in a slot **before** the access | Needs suppression or undo |
| **C — concurrent** | 14 | base write and access are in the **same** slot | Suppression is too late; needs undo |

**Model A (restart-safe by construction) — 7:** `LDC.L @Rm+,{SR,GBR,VBR}`,
`LDS.L @Rm+,PR`, `MOVML.L @R15+,Rn`, `MOVML.L Rm,@-R15`, `MOVMU.L @R15+,Rn`.
These keep the base pristine until a terminal slot. The SH-2A pop states the
principle in its own comment: *"R15 pristine until the terminal; loads
idempotent."* **This is the preferred shape for any new instruction.**

**Model B (bump-first) — 9:** `MOV.{B,W,L} @Rm+,Rn` and the SH-2A
`MOV.{B,W,L} R0,@Rn+` / `@-Rm,R0` forms. `MOV.L @Rm+,Rn` is the archetype: slot 0
commits `Rm := Rm+4` with no access, slot 1 then reads at `Rm-4`, recovering the
original address by subtracting the 4 it just added.

**Model C (concurrent) — 14:** every `@-Rn` store (`MOV.{B,W,L} Rm,@-Rn`,
`STS.L {PR,MACH,MACL},@-Rn`, `STC.L {SR,GBR,VBR},@-Rn`), `LDS.L @Rm+,{MACH,MACL}`,
`MAC.{L,W} @Rm+,@Rn+`, `RTE` (two consecutive `@R15+` pops, base bump committing
in the access slot — structurally identical to the MAC dual-base case; see
`core/datapath.vhm:833-840`, which names it explicitly alongside MAC as the
other dual-`mem_autoinc1` form), and `MOVMU.L Rm,@-R15`. The z-port write lands
in the same slot as the access, one cycle before `tlb_squash` can arm — so
`reg_wr_z_g` suppression cannot reach it and the undo path is mandatory.
`RTE`'s restart safety is unexercised: `squash_arm` requires `sr.rb = '0'`
(user mode), and RTE runs in the handler (`sr.rb = '1'`), so the squash window
this whole section describes never arms for it in practice.

**Multi-access forms (more than one base to restore): 2** — `MAC.L @Rm+,@Rn+`,
`MAC.W @Rm+,@Rn+` (plus `RTE`, see above — 3 including it). `MOVMU.L @R15+,Rn`
is **not** a multi-access form: it is Model A (§9.3 above) — R15 is written
once, in the terminal slot, not per-operand — and was previously listed here
in error, contradicting its own Model-A classification two paragraphs up.
`MOVMU.L Rm,@-R15` is also not a multi-*base* form: it is **one** base (R15)
decremented N times, which two restore entries cannot structurally undo (see
§9.4/§9.5 — this is a limitation, not a coverage gap to close by adding more
entries).

### 9.4 How the contract is met today

- **Model A** — nothing to do; the base never moves before the fault.
- **Model B** — `reg_wr_z_g` suppression under `tlb_squash`, plus the
  `mem_autoupd` restore, **for the 3 base-ISA forms only**
  (`MOV.{B,W,L} @Rm+,Rn`). The SH-2A forms nominally counted in the same
  Model-B bucket are **not** covered by this mechanism:
  - `MOV.{B,W,L} R0,@Rn+` (store direction) does not match `mem_autoupd` at
    all (`mem_autoupd` requires `mem.wr = '0'`, a read). Its slot1 is
    `ma_op=WRITE, ma_addy=ZBUS, arith=SUB` (`decode/gen-go/spec/sh2a/mov.toml:556-580`),
    which instead matches `mem_predec` (`core/datapath.vhm:480-482`). But
    `mem_predec`'s restore value is `ma_base := xbus` captured *at the fault
    slot*, and on this instruction's shape `xbus` (= Rn) has **already been
    bumped by slot0** by the time the fault slot runs — so the "restore"
    writes back the already-bumped value and is a no-op.
  - `MOV.{B,W,L} @-Rm,R0` (load direction) matches **no** restore signature at
    all (neither `mem_autoupd` nor `mem_predec` nor `mem_autoinc1`).
  - That is 6 of the 9 nominal Model-B forms (the 3 store + 3 load SH-2A
    variants) silently uncovered. This is **latent, not live**: `SH2A_ARCH`
    and `PRIV_ARCH` are never both set in a shipping configuration today, so
    no current build can exercise it — but the code as written does not
    protect these 6 forms, and the SH-2A + MMU restart-safety gap is already
    tracked in §9.5 item 1 for the multi-access forms; this extends the same
    gap to these 6 single-access ones.
- **Model C** — the restore path only: `mem_autoinc1` (single-slot `@Rm+`,
  also covering `RTE`'s first pop via the second-entry mechanism below),
  `mem_predec` (`@-Rn` stores, restoring the captured pre-decrement base), and a
  **second restore entry** for dual-base forms (MAC, and structurally RTE),
  which restores operand 1's base as well as operand 2's.
- The restore arms for **D-side faults only**, gated on `tlb_exc_ifetch = '0'`
  (not `tlb_exc_is_i`, which is deliberately narrower — reserved for the
  restart-PC derivation, see `core/cpu.vhd`'s declaration comment for both
  signals); an instruction-fetch fault of ANY kind (IMISS/IPROT/MULTI_HIT)
  must never inherit a stale data-side shadow.
- **Age exemptions on the squash.** The squash window is a pure *time* window,
  so on its own it also discards the writeback of an instruction that is
  architecturally **older** than the faulting access and will therefore never
  be re-executed. This age-blindness has bitten twice — once per write port —
  and both instances are fixed by the same shape, a one-shot bit that lets
  exactly the writeback pending at arming time commit:
  - **w-port, `wb_grace`** (`g_wb_grace`): the w-port retires a slot late by
    construction, so a writeback already presenting when the squash arms is
    necessarily older. Armed from the shared `squash_arm` predicate.
  - **z-port, `z_grace`** (in `g_restore2`): armed only for an
    **instruction-side** fault whose restart PC is *not* backed up
    (`tlb_exc_is_i and not delay_slot` — the same predicate the `tlb_exc_pc`
    arm uses). On such a fault nothing younger than the faulting *fetch* can be
    in EX, so the pending write is older and must commit; the case that broke
    was an IMISS on a **branch target**, which was silently dropping the
    branch's delay-slot write while restarting at the target. A D-side fault,
    and an I-side fault on a delay-slot fetch, both restart somewhere that
    re-executes the pending write, and so still squash it — though only the
    D-side half of that is guarded: the `not delay_slot` arm is **reasoning
    only, unguarded by the current suite** (dropping it leaves all 68 guards
    passing), and the sweep that would settle it is the rotted `m8_idslot_0-2`
    of 9.5 item 3. The RTL comment says the same; keep the two in step.

  If a third instance appears, reach for this pattern rather than widening or
  narrowing the time window.

### 9.5 Coverage and open items

*Guards: `mmuainc`, `mmuainc2` (single `@Rm+` across a D-fault), `mmustr2`,
`mmushadowst` (store side), `mmudrain` (leg A: a train of faulting `@Rm+` loads
drained by an I-side miss; leg C: a train of faulting `@-Rn` **stores** drained
by an I-side miss; leg D: **alternating** faulting store -> IMISS, chained
through stub pages), `m8_dside` cases 8 and 9 (MAC dual-base at all three fault
positions), `mmurestartpc`, `mmupcprobe`, `mmudspcprobe` (restart-PC exactness).*

Known gaps, in priority order:

0. **The §7.1 handler-residency invariant is unenforced and unguarded.** Nothing
   in the RTL or the test suite fails if a handler can take a TLB miss on its own
   working set; the fault is simply suppressed and the access goes to the VA as a
   PA. A guard would install a handler in a P0 page, evict that page, and assert
   the resulting behaviour is a defined reset rather than a silent wrong access —
   at which point the desired behaviour has to be decided first, since today
   there is none. Related: a review of 2026-08-08 flagged the `RB=1` suppression
   at `core/cpu.vhd:653` as a defect; it is better understood as this invariant's
   enabling mechanism, and the defect is the missing enforcement, not the gate.

1. **`MOVMU.L Rm,@-R15` is a Model-C form that is STRUCTURALLY unrestartable,
   not merely uncovered.** It is not the MAC dual-base *shape*: MAC touches
   two independent bases (Rm, Rn), one restore entry each. `MOVMU.L Rm,@-R15`
   is **one** base (R15) decremented once per register in the mask, N times
   in a single instruction. A fault partway through has already committed
   N' < N of those decrements, and the two-entry restore mechanism (built for
   *two bases*, not *N decrements of one base*) cannot reconstruct which N'
   it was — the spec row says so explicitly ("NOT restart-safe, by design",
   `decode/gen-go/spec/sh2a/mov.toml:406`). This is a structural limitation
   of the instruction's restart contract, not a gap this machinery is meant
   to close by adding more entries; SH-2A + MMU restart safety is separately
   untested regardless — the J2A decoder lacks the privileged MMU
   instructions the guards need, so those tests have never genuinely run.
2. **Faulting-*load* trains alternating with an I-side miss are uncovered.**
   `mmudrain` legs C and D closed the store side (burst and alternating); the
   remaining hole is leg B, the alternating shape on the **load** side. Leg D
   is what exposed the z-port age-blindness described in 9.4, so the
   alternating shape is worth completing.
3. The exhaustive I-side delay-slot sweep (`m8_idslot_0-2`) does not run; it is a
   pre-existing rotted orphan, so delay-slot restart rests on single-case guards.
   Named consequence: this is exactly the sweep that would exercise the
   `not delay_slot` arm of `z_grace` (9.4). Until it is revived, that arm is
   carried on reasoning alone — dropping it changes no guard's verdict — so a
   green suite is not evidence that the delay-slot half of the I-side age
   exemption is right.

### 9.6 Rule for new instructions

Prefer **Model A**: place the base write in a terminal slot after every access.
It costs no restore state, cannot desynchronise from the squash, and is the shape
the SH-2A `MOVML`/`MOVMU` pops already use. If Model B or C is unavoidable, the
instruction must be added to the §9.3 enumeration *and* given a guard that faults
at every access position — for a multi-access form, that means each operand
separately and all operands cold.

---

## 10. References

- [j4.md](j4.md) — J4 hardware block diagram, configuration matrix, synthesis cost.
- [`core/tlb.vhd`](../../core/tlb.vhd) — the TLB RTL (match, permission, NRU, flush).
- `core/cpu.vhd` `g_mmu` / `g_dstore_squash` / `g_inst_p1_fold` — translation
  enable, PIPT relocation, faulting-store demote.
- `decode/gen-go/spec/sh4/{mmu,exceptions}.toml` — privileged MMU instruction and
  exception-vector encodings.
- `docs/mmu/{design,hardware,linux}-spec.md` and `docs/mmu/security-review.md`
  (design repository) — the full architectural specification and security review.

---

## 11. Historical references & prior art

The J4 TLB is a deliberately conservative design that re-uses decades-old,
well-understood mechanisms. The lineage of each major choice:

**Software-loaded / software-managed TLBs.** J4 has no hardware page-table
walker: a miss traps to software that installs the entry. This is the
software-refilled TLB tradition pioneered by RISC architectures.
- **MIPS** R2000/R3000/R4000 — the canonical software-refilled TLB (hardware
  raises a refill exception; software walks the tables and issues `TLBWR`).
  [MIPS architecture (Wikipedia)](https://en.wikipedia.org/wiki/MIPS_architecture)
- **DEC Alpha** — TLB fill in PALcode (privileged firmware), another fully
  software-managed model. [DEC Alpha (Wikipedia)](https://en.wikipedia.org/wiki/DEC_Alpha)
- Nagle, Uhlig, Stanley, Sechrest, Mudge & Brown, *"Design Tradeoffs for
  Software-Managed TLBs,"* ISCA 1993 — the classic performance analysis of the
  approach J4 follows.
  [ACM DL](https://dl.acm.org/doi/10.1145/165123.165128)
- General background:
  [Translation lookaside buffer (Wikipedia)](https://en.wikipedia.org/wiki/Translation_lookaside_buffer)

**Context registers / ASID tagging.** `ASIDR` is a per-context register that
hardware reads on every translation, independent of how TLB entries are
programmed — so a context switch is a single register write, not a TLB flush.
- **SPARC v9 / UltraSPARC** `PRIMARY_CONTEXT` & `SECONDARY_CONTEXT` (sun4u,
  ASI `0x21`, 1995) — the direct model for `ASIDR`.
  [SPARC (Wikipedia)](https://en.wikipedia.org/wiki/SPARC)

**`ASID` folded into the TSB index (Phase 2).** Deriving a translation
structure's *index*, not just its tag, from the address-space identifier.
- **US 5,493,660**, Hewlett-Packard, *"Software assisted hardware TLB miss
  handler"*, filed **1992-10-06**, granted 1996-02-20, **expired**. A hardware
  TLB miss handler forming its pointer by XORing high-order virtual-address
  bits — the OS-assigned space identifier — with low-order bits, "to provide a
  more uniform distribution of pointer references over periods when multiple
  processes execute". Same mechanism, same motivation, same context.
- **US 5,899,994**, Sun Microsystems, filed **1997-06-26**, **expired** — TSB
  index from PID + VA. It also warns that XORing a *narrow* process identifier
  straight in distributes badly, which is why J4's fold is a mixed function
  (`asid ^ (asid<<5)`, refolded `>> 9`) rather than a bare XOR.
- **US 7,430,643**, Sun, priority **2004-12-30** — context as a **tag only**,
  which is prior art for the arrangement J4 had *before* Phase 2.

**Random replacement between the ways of a set (Phase 2 victim LFSR).**
Ubiquitous well before the cutoff — A. J. Smith, *"Cache Memories"*, ACM
Computing Surveys 14(3), 1982; Hennessy & Patterson (any edition ≤4th); the
replacement policy of essentially every ARM core of the era.

**Set-associative placement with a set in one aligned block.** PowerPC HTAB
`PTEG` (601/603/604, 1993–94): eight candidate entries in one aligned group,
read as a unit, with a software fallback — the same "all candidates in one
read" property that lets J4's software filler see both tags before it writes.

**Partitioning a shared indexed structure per trust domain** — the actual
isolation mechanism, as distinct from the hardening above. J. Liedtke,
H. Härtig & M. Hohmuth, *"OS-Controlled Cache Predictability for Real-Time
Systems"*, **RTAS 1997, pp. 213–224**. The rejected-as-costly alternative,
flush-on-switch, is C. Percival, *"Cache Missing for Fun and Profit"*,
**BSDCan 2005**.

**Not available to this project, recorded so it is not re-proposed.** A keyed
or per-context index mapping originates with **RPcache — Z. Wang & R. B. Lee,
ISCA 2007, pp. 494–505**, past the 2006 cutoff; there is **no pre-2006 TLB
index randomization at all**. Periodic re-keying is CEASER (MICRO 2018) and
its successors. And a boot-time secret *constant* XOR'd into the index is
useless rather than merely weak: it cancels in the collision condition, because
conflict attacks turn on relative placement, never absolute. See
`docs/mmu/hardware-spec.md` §2.8b.

*Publication or grant before 2006 is evidence of prior art. It is not a
patent-clearance opinion.*

**SuperH / SH-4 lineage.** The privileged architecture J4 implements (MD mode,
banked registers, the SPC/SSR exception model, `MMUCR`/`PTEH`/`PTEL`, a
software-assisted TLB) is the SH-4 compatibility target, built on the open
J-core SH-2 clean-room core.
- [SuperH (Wikipedia)](https://en.wikipedia.org/wiki/SuperH)
- [J-core open processor project](https://j-core.org/)

**Cache indexing (VIPT → PIPT).** J4's L1 caches are now physically indexed and
tagged, removing the virtual-synonym hazards (and page-colouring requirement) of
a virtually-indexed cache.
- [CPU cache — indexing/tagging (Wikipedia)](https://en.wikipedia.org/wiki/CPU_cache#Address_translation)

**Base-register writeback on a faulting access (§9).** The rule that a faulting
access leaves its base register at the pre-instruction value, uniformly across all
writeback forms, is **ARM's Base Restored Abort Model** — optional before ARMv6,
mandatory from ARMv6, and explicitly required to apply "uniformly across all
instructions" rather than per-instruction. ARM adopted it after shipping both
models for LDM/STM, which is the same multi-access base-writeback problem J4 has
in `MAC.{L,W} @Rm+,@Rn+` and `MOVMU.L`.
- ARM DDI 0100I, *ARM Architecture Reference Manual*, §A2.6.6 "Abort models".

**Commit-in-program-order for precise exceptions (§9.2).** The discipline of
committing architectural state only at writeback, so a fault flushes everything
younger by construction, is the classic five-stage RISC model — and its known
failure mode for delay-slot faults ("exceptions then have essentially two
addresses, the exception address and the restart address") is documented as a
recurring source of design bugs, which J4 encountered and fixed.
- [Classic RISC pipeline (Wikipedia)](https://en.wikipedia.org/wiki/Classic_RISC_pipeline)
- Smith & Pleszkun, *"Implementing Precise Interrupts in Pipelined Processors,"*
  IEEE Trans. Computers, 1988 — the taxonomy (in-order completion, reorder
  buffer, history buffer, future file). J4 is in-order completion with a
  history-buffer-style undo for the writeback forms §9 enumerates.

**Page-split / multi-word instruction faults.** The rule that an instruction
fetch fault must report the instruction's *first-word* PC (so a multi-word unit
restarts cleanly) follows the **Intel 386** (1985), which validated page-split
instructions against the instruction's start address.
- [Intel 80386 (Wikipedia)](https://en.wikipedia.org/wiki/I386)

**Isolation-attack history** (full analysis and applicability in
`docs/mmu/security-review.md`):
- Transient-execution class — neutralized by J4's in-order, non-speculative
  design. [Transient execution CPU vulnerability (Wikipedia)](https://en.wikipedia.org/wiki/Transient_execution_CPU_vulnerability)
- **TLBleed** — Gras et al., USENIX Security 2018 (TLB side channel).
  [paper](https://www.usenix.org/conference/usenixsecurity18/presentation/gras) ·
  [project](https://www.vusec.net/projects/tlbleed/)
- **AnC ("ASLR⊕Cache")** — Gras et al., NDSS 2017 (hardware-page-walker cache
  attack; does not apply to a software walker).
  [project](https://www.vusec.net/projects/anc/)
- **Controlled-channel attacks** — Xu, Cui & Peinado, IEEE S&P 2015
  (page-fault-sequence oracle).
- **Rowhammer** — Kim et al., ISCA 2014 (DRAM disturbance; the one physical
  threat the core's properties do not mitigate).
  [Row hammer (Wikipedia)](https://en.wikipedia.org/wiki/Row_hammer)

---

## 12. Glossary

| Term | Meaning |
|---|---|
| **AT** | Address-translation enable, `MMUCR` bit 0. When `0`, all accesses are physical (no TLB); when `1`, P0/P3 accesses are translated. |
| **ASID** | Address Space Identifier — the 12-bit per-context tag that distinguishes one tenant's address space from another. |
| **ASID_TAG** | The 16-bit value actually stored in a TLB entry and compared on lookup: the 12-bit ASID plus a 4-bit generation discriminator, kernel-encoded. |
| **ASIDR** | The privileged register holding the **current** context's `ASID_TAG`. Written on every context switch; it is both the lookup tag and the tag stamped onto installed entries. |
| **C (cacheable)** | PTE bit selecting whether a page is accessed through the L1 cache (`C=1`) or via uncached bypass to memory (`C=0`). |
| **CAM** | Content-Addressable Memory — the parallel-match structure the 32-entry TLB is built from. |
| **D (dirty)** | PTE bit marking a page as written. Loaded into the entry but not enforced by hardware in the reference build. |
| **DMISS_R / DMISS_W** | Data TLB miss on a load / store (vectors `0x060` / `0x080`). |
| **DPROT_R / DPROT_W** | Data protection violation on a load / store of a mapped page (vector `0x0C0`). |
| **EXPEVT** | Exception-event (cause) register; privileged-read. Holds the code identifying which exception was taken. |
| **G (global)** | PTE bit making an entry match regardless of `ASID_TAG`. For kernel-shared pages only. |
| **IMISS / IPROT** | Instruction-fetch TLB miss (`0x040`) / protection violation (`0x0A0`). |
| **LDTLB** | The TLB-install instruction (`0x0038`): latches `{ASIDR, PTEH.VPN, PTEL}` into an NRU-chosen entry. |
| **LDTLB.RN** | Fused *load-TLB-and-return* (`0x0078`): an atomic `LDTLB`+`RTE` with **no** delay slot, used by the miss handler to install and resume in one step. (A hot-path variant `LDTLB.RN Rm` at `0x?FB`, sourcing `PTEL` from a GPR, existed until the hardware TSB walker made the software fast path it served obsolete; it has been retired.) |
| **MD** | `SR.MD`, the mode bit: `1` = privileged (kernel), `0` = user. Gates the `U` permission check and access to privileged registers/instructions. |
| **MMUCR** | MMU Control Register (P4 MMIO `0xFF00_0010`): `AT` (bit 0) enables translation, `TI` (bit 2) flushes the TLB. |
| **MMUFSR** | MMU Fault Status Register (P4 MMIO `0xFF00002C`): read-only latch of the last fault. `[12] VALID`, `[11:8] KIND`, `[7:5] reserved`, `[4] USER`, `[3] PROT`, `[2] ITLB`, `[1] INITIAL` (always 0), `[0] WRITE`. KIND values: 1=IMISS, 2=DMISS_R, 3=DMISS_W, 4=IPROT, 5=DPROT_R, 6=DPROT_W, 7=MULTI_HIT, 0=none. Low byte is a Linux `FAULT_CODE_*` image. Latched on first fault cycle alongside TEA/PTEH; overwritten by next fault. |
| **NRU** | Not-Recently-Used — the TLB's replacement policy for choosing which entry `LDTLB` overwrites. |
| **P0–P4** | The SH-4 virtual segments: P0 (`0x0…`) user+kernel translated; P1 (`0x8…`) kernel cached physical window; P2 (`0xA…`) kernel uncached physical window; P3 (`0xC…`) kernel translated; P4 (`0xE…/0xF…`) privileged control/MMIO. |
| **PA / VA** | Physical address / Virtual address. |
| **PIPT** | Physically-Indexed, Physically-Tagged cache: the cache is indexed and tagged with the physical address (after TLB relocation), so no page-colouring is needed. |
| **PPN / VPN** | Physical / Virtual Page Number — the page-aligned high bits of a PA / VA. |
| **PTE** | Page Table Entry — the software description of a mapping; its fields are loaded into a TLB entry via `PTEH`/`PTEL`. |
| **PTEH / PTEL** | Privileged registers staging a TLB install: PTEH carries the VPN, PTEL the PPN plus permission/attribute flags. |
| **STALE** | PTE bit (`PTEL[1]`) marking an entry soft-invalidated/revoked. **Hardware-enforced:** a `STALE=1` entry never hits. |
| **SR** | Status Register; holds `MD` (mode), `RB` (register-bank select), `BL` (exception block), and the interrupt mask. |
| **TCB** | Trusted Computing Base — here, the privileged kernel that owns the page tables, ASID allocation, and the miss handler. |
| **TEA** | TLB Exception Address register; privileged-read. Holds the faulting virtual address. |
| **TI** | TLB Invalidate — `MMUCR` bit 2; writing it clears `VALID` on every entry (full flush). |
| **TLB-desync** | A stale TLB entry that outlives the mapping it describes (page freed/reassigned/permission-downgraded without invalidation) — the dominant cross-tenant risk of a software-loaded TLB. |
| **TSB** | Translation Storage Buffer — an in-memory hash table of recent translations the software miss handler consults before a full page-table walk. |
| **U / W / X** | Per-page permission bits: User-accessible / Writable / eXecutable. |
| **V (valid)** | PTE bit marking a TLB entry as occupied/usable. |
