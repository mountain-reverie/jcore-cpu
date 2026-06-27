# J4 TLB — Software & Security Architecture

The user/programmer view of the J4 MMU's translation lookaside buffer: what the TLB
guarantees, the contract a kernel must uphold to use it safely for multi-tenant
isolation, and the security properties it does and does not provide. For the
hardware block view and synthesis cost see [j4.md](j4.md); the RTL is
[`core/tlb.vhd`](../../core/tlb.vhd) (instantiated in `core/cpu.vhd` under
`g_mmu : if MMU_ARCH generate`). The behaviour described here is locked by the
`sim/tests/mmu*.S` regression guards (named per property below).

> **Audience:** OS / hypervisor / firmware authors and security reviewers. This
> document is normative for *how software must use the TLB*; the `*.toml` decode
> spec and `core/tlb.vhd` are authoritative for the encodings and hardware.

---

## 1. What the TLB is

- **32-entry, fully associative, software-loaded.** There is **no hardware
  page-table walker.** On a TLB miss the core raises an exception and a
  privileged software handler reads the page tables / TSB and installs the
  mapping with `LDTLB` (or the fused `LDTLB.RN`). This is the single most
  important design fact: *translation correctness, permission setup, and
  invalidation are entirely software's responsibility* — the hardware only
  matches, enforces the installed permissions, and relocates.
- **Fixed 4 KB pages** (the reference J32 build).
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
| `VPN` | `PTEH[31:12]` | Virtual page number tag. Captured by hardware on a miss at 4 KB granularity. |
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
hit  = VALID ∧ (STALE = 0) ∧ (VPN = VA[31:12]) ∧ (GLOBAL ∨ ASID_TAG = ASIDR)
```

Only on a **hit** is the permission predicate evaluated. A violation raises the
access-type protection exception and **suppresses the memory effect** (a faulting
store is demoted to a non-mutating read on the external bus):

| Access | Protection fault when | Exception (vector offset) |
|---|---|---|
| Instruction fetch | `X=0` **or** (`U=0` and `MD=0`) | `IPROT` (`0x0A0`) |
| Data load | `U=0` and `MD=0` | `DPROT_R` (`0x0C0`) |
| Data store | (`U=0` and `MD=0`) **or** `W=0` | `DPROT_W` (`0x0C0`) |

A **miss** (no matching entry) raises `IMISS` (`0x040`), `DMISS_R` (`0x060`), or
`DMISS_W` (`0x080`) by access type — the distinct vectors let the miss handler
know the access kind without reading `EXPEVT`. `EXPEVT` holds the cause and `TEA`
the faulting virtual address (both privileged-read only).

**Privileged-mode (`MD=1`) rules.** The kernel honours `X` and `W` (it cannot
execute an `X=0` page nor write a `W=0` page — the `MD` term gates only the `U`
check). The kernel does **not** enforce `U` against itself: it may read, write,
and execute user (`U=1`) pages. There is **no SMEP/SMAP-equivalent**; a kernel
that must not trust tenant-controlled user pages has to arrange that in software.

On a hit the physical address is formed as `PA = {0000, PPN[27:13], PPN[12],
VA[11:0]}` (28-bit physical region) and used to index the PIPT L1 caches; `C`
selects cache vs. uncached bypass.

*Guards: `mmuxlate` (basic translate), `mmufault` (all six miss/prot classes
incl. user-mode `IPROT`/`DPROT_R` and `DPROT_W`), `mmureloc`/`mmurelocif`/
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
   - `LDTLB.RN` (`0x0068`) — the fused *install-and-return*. **It has NO delay
     slot.** A trailing `nop` in handler examples is padding, not an architectural
     delay slot, and must not carry a meaningful instruction.
5. **Replacement** is NRU (not-recently-used) across the 32 entries; software does
   not choose the slot. **Do not install duplicate `VPN+ASID` entries** — a
   multi-hit is resolved to the highest-index match with no hardware multi-hit
   exception.

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
- **Rowhammer** and other DRAM-level effects — a function of the SDRAM part and
  the physical allocator, not the core; the good CPU properties do not help here.
- **Software correctness** in ASID recycle, global-bit hygiene, revocation, and
  the nested-fault/exception path — by far the dominant risk, and entirely in the
  kernel's hands.

The full attack-landscape analysis, spec review, and implementation review are in
the design repository's `docs/mmu/security-review.md`.

---

## 8. Property → guard map

| Security / correctness property | Guard(s) |
|---|---|
| Basic VA→PA translation | `mmuxlate` |
| Permission enforcement (U/W/X, user + kernel, all 6 classes) | `mmufault` |
| ASID cross-tenant isolation + global-bit | `mmuasid` |
| STALE single-entry revocation | `mmustale` |
| TLB flush → software re-walk | `mmurun` |
| VA→PA relocation (D / I / C=0 bypass) | `mmureloc`, `mmurelocif`, `mmurelocbp` |
| Faulting store does not mutate memory | `mmustore` |
| Per-access fault vectors + EXPEVT/TEA | `mmufault`, `mmuimiss` |
| Privileged-register / instruction trap | `mmureg`, `mmuguard`, `privmode` |
| SR / bank state on exception entry | `mmusr` |
| Precise-exception fault transparency (MAC, auto-inc, …) | `m8_*` family |

---

## 9. References

- [j4.md](j4.md) — J4 hardware block diagram, configuration matrix, synthesis cost.
- [`core/tlb.vhd`](../../core/tlb.vhd) — the TLB RTL (match, permission, NRU, flush).
- `core/cpu.vhd` `g_mmu` / `g_dstore_squash` / `g_inst_p1_fold` — translation
  enable, PIPT relocation, faulting-store demote.
- `decode/gen-go/spec/sh4/{mmu,exceptions}.toml` — privileged MMU instruction and
  exception-vector encodings.
- `docs/mmu/{design,hardware,linux}-spec.md` and `docs/mmu/security-review.md`
  (design repository) — the full architectural specification and security review.
