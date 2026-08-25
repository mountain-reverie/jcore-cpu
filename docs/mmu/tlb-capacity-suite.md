# The TLB capacity / eviction suite (task D0b)

Companion to `sim/tests/mmucapd.S`, `sim/tests/mmucapsub.S` and
`sim/tests/mmucapi.S`. The guards carry their own headers; this file records
the things that are true of all three — the harness contract, the mutation
table, and how to add a parameterisation without rewriting any of it.

---

## 1. What it replaces

Before this suite, the cosim's MMU working sets were small and base-first, and
a good many of them were identity-mapped (`sim/tests/README-identity-mapping.md`
surveys which). Three consequences, all of them the kind of gap that makes a
green suite mean less than it looks:

* **Nothing exceeded the DTLB.** The shipped DTLB is 16 entries
  (`core/cpu.vhd`, `u_dtlb`). `mmudrain.S`'s ten D-side pages are the largest
  live set this work is aware of — its own header claims it is the largest in
  `mmu_sim.sh`/`linux_sim.sh`, and that claim was NOT re-verified here across
  all 100 `mmu*.S` files. What *was* checked is the part that matters: ten is
  under sixteen, so that guard does not force a capacity eviction at the
  shipped size. It reacts to an 8-entry DTLB, via leg A's fault count
  (`Result=0x10`), and its header says so.
* **Nothing asserted anything about the ITLB.** `mmudrain`'s leg D does have an
  11-page I-side live set against an 8-entry ITLB, and its header records that
  the resulting capacity misses are absorbed as stalls — but no assertion in
  the file is about the ITLB at all. Its checks are D-side base-register
  arithmetic and fault counts.
* **First touches were base-first.** `mmupmrawvpn.S` is the exception, and it
  is one mapping and one unaligned touch with nothing resident competing for
  the entry. Otherwise a mapping was entered through its own first `PAGE_SIZE`,
  which is exactly the case where the TSB's 4 KB tag granularity and the
  entry's `page_mask` cannot disagree.

An infinite-capacity TLB model, or a replacement policy that never evicted,
would have passed the entire suite.

---

## 2. The harness contract

Everything below is shared by all three guards, and is the part worth reusing.

### 2.1 The alias scheme: `VA = PA + ALIAS_DELTA`

There is exactly one relocation constant, `ALIAS_DELTA = 0x0040_0000`. Every
page under test — data frames, and in `mmucapi` the executable stub pages too —
lives physically in the image and is reached only at `PA + ALIAS_DELTA`.

This buys three things at once:

* **No identity mapping anywhere on an asserted path.** The frames move by
  editing `ALIAS_DELTA` alone, so neither carve-out of
  `sim/tests/README-identity-mapping.md` is claimed or needed.
* **A free inert-MMU tripwire.** The alias window sits above the image, and
  `sim/cpu_ctb.c` backs `[image_size, 0x0100_0000)` with an anonymous
  zero-filled mapping. An untranslated *read* therefore returns 0, and an
  untranslated *instruction fetch* returns `0x0000` — a general illegal
  instruction, not a stub. `mmucapi` cannot enter its first leg at all without
  real I-side relocation.
* **PC-relative code works unchanged at the alias.** A uniform delta means
  `MOV.L @(disp,PC),Rn` inside an aliased page reads the aliased address of its
  own literal, which translates back to the right frame. That is why the stub
  pages need no linker-script special-casing (contrast `sh32_tlbtext.x`).

### 2.2 Self-describing sentinels

Every backing word holds **its own physical address**:

```
_frames:
        .rept   N_LARGE * CAP_NSUB
        .long   .
        .space  PAGE_SZ - 4, 0
        .endr
```

So the expected value of any touch is `VA - ALIAS_DELTA`, computed in two
instructions from the address already in hand. There is no sentinel table to
keep in step with a layout, and a translation that lands on the *wrong frame*
is as visible as one that never happened. (Verified against the linked image:
the word at `0x3000` in `mmucapd.elf` reads `0x0000_3000`.)

### 2.3 The TSB is pre-seeded, and it is 4 KB-granular

The preamble writes one TSB row per **4 KB page** of the alias window before
`MMUCR.AT` goes on, so no leg ever takes an exception: every miss is resolved
by the hardware walker as a stall. A fault is therefore a defect, and both
vector handlers say so with a named code (`0x41` at VBR+0x400, `0x42` at
VBR+0x100) rather than hanging.

Per-4 KB-page rows are not a convenience, they are the contract.
`core/tlb_walk.vhd` compares `bus_d(31 downto 12) = va_reg(31 downto 12)` and
`core/datapath_pkg.vhd`'s `tsb_ptr()` hashes `VA[31:12]`, so a superpage needs
one row per sub-page, each tagged with that sub-page's own VPN and all carrying
the same PTEL. The seed loop derives it uniformly:

```
PPN = (VA - ALIAS_DELTA) & ~(MAP_SPAN - 1)
PTEL = PPN | (CAP_PM << 8) | flags
```

Row insertion is two-way (way 0 unless it holds a valid entry). A third
colliding VPN reports `0x2F` — a harness collision, explicitly *not* a CPU
defect — instead of silently evicting a row the run depends on.

### 2.4 The probe window

The decisive measurement in `mmucapd` is three instructions with **no memory
access other than the one under test**:

```
        mov.l   @r10, r4        ! P4_TSBCNT before   (r10 staged)
        mov.l   @r11, r5        ! the access under test (r11 staged)
        mov.l   @r10, r6        ! P4_TSBCNT after
```

A PC-relative literal load inside that window would be a second D-side access
through a code page and would make the delta mean something else. Where two
probes run back to back, the second probe's VA is staged into `r15` up front
and the `0x0001_0001` comparand is *built* (`mov`/`shll16`/`add`) rather than
loaded, so nothing touches memory between them.

`P4_TSBCNT` (`0xFF000054`) packs `[31:16] = cnt_walks`, `[15:0] = cnt_hits`, so
"exactly one walk that hit the TSB" is a single 32-bit compare against
`0x0001_0001`.

`mmucapi` uses `P4_TLBINST` (`0xFF000058`, `[31:16] = ITLB slot writes,
[15:0] = DTLB`) instead, because the I side needs the *side* of the install,
not just that a walk happened. Its windows cannot be three instructions — a
chain traversal is code — so it traverses each chain **three times from one
fixed return address** and measures only the third. By then every page of the
driver loop itself has been fetched, which is what makes `delta == 0` a legal
answer for a chain that fits.

### 2.5 The differential, and why it is the whole design

Each guard pairs a working set that **fits** with one that **does not**, run
through the identical probe:

| | fits | does not fit |
|---|---|---|
| `mmucapd` / `mmucapsub` | 6 mappings, re-touch must not walk (`0x13`) | 24 mappings, re-touch must walk exactly once (`0x23`) |
| `mmucapi` | 3-stub chain, third traversal installs 0 ITLB entries (`0x52`) | 12-stub chain, third traversal installs ≥ 12 (`0x54`) |

The "fits" assertion is a **non-increment**, which a dead counter satisfies
perfectly. It is paired, in the same run and off the same counter, with an
exact positive delta. That is the counter-trustworthiness pattern the Group-C
locks use, and it is why neither leg needs to lean on the other guard.

---

## 3. The guards

### `mmucapd.S` — DTLB capacity, 4 KB pages

Also the harness. 24 mappings of 4 KB against a 16-entry DTLB.

* **leg S** — sweep 6 mappings, re-probe mapping 0: no walk.
* **leg L** — flush, sweep 24, then: the sweep itself walked ≥ 24 times
  (`0x26`); re-probing mapping 0 walks exactly once and that walk hits
  (`0x23`); the entry it rebuilds covers the mapping base with no further walk
  (`0x25`).
* **leg F** — re-sweep all 24 at their bases with the DTLB thrashing
  throughout; every one must still relocate correctly (`0x31`).

### `mmucapsub.S` — the same, but never base-first

`#define CAP_PM 1` + `#define CAP_FIRSTSUB 3` + `#include "mmucapd.S"`.
Mappings become 16 KB superpages and the **first touch of every one of them is
its last 4 KB sub-page**. Leg L's probe pair then becomes the property the file
exists for: an entry installed from a non-base VA must cover its own mapping
base, which is only true if the walker installs the raw faulting VPN and the
match path masks it by the entry's own `page_mask`.

`mmupmrawvpn.S` locks that for one mapping and one unaligned touch;
`mmucapsub` puts it under 24 mappings and forced eviction.

### `mmucapi.S` — ITLB capacity and interleaved I/D walks

Self-driving chains of aliased stub pages (`jmp @r12` / `add r11,r12`, the
mmudrain leg-D construction). Three legs: a 3-stub chain that fits, a 12-stub
chain that does not, and a 20-stub **mixed** chain in which every page
transition is an I-side walk immediately followed by a D-side walk of a
different page, with both arrays over-subscribed. The mixed leg asserts the
ITLB and DTLB install counts, both chain pointers, and the **exact sum** of the
twenty relocated loads.

---

## 4. Mutation table (all measured, not predicted)

Every row was produced by editing the named file, rebuilding without `-n`, and
running the guard. Reverted afterwards; `git status` clean.

| # | Mutation | Guard | Result |
|---|---|---|---|
| M0 | guard preamble: `Enable AT` store `mov #1,r1` → `mov #0,r1` | `mmucapd` | FAIL `Result=17` (`0x11`) |
| M0 | ditto | `mmucapsub` | FAIL `Result=17` (`0x11`) |
| M0 | ditto | `mmucapi` | FAIL `Result=66` (`0x42`) |
| M1 | `core/cpu.vhd` `u_dtlb entries => 16` → `32` | `mmucapd` | FAIL `Result=35` (`0x23`) |
| M2 | `core/cpu.vhd` `u_dtlb entries => 16` → `4` | `mmucapd` | FAIL `Result=19` (`0x13`) |
| M3 | `core/tlb.vhd` `ram(idx).page_mask <= ptel(11 downto 8)` → `<= "0000"` | `mmucapsub` | FAIL `Result=17` (`0x11`) |
| M3 | ditto | `mmucapd` | **PASS** |
| M4 | `core/tlb.vhd` `tlb_match`: `vpn_compare_mask(entry.page_mask)` → `vpn_compare_mask("0000")` | `mmucapsub` | FAIL `Result=37` (`0x25`) |
| M4 | ditto | `mmucapd` | **PASS** |
| M5 | `core/cpu.vhd` `u_itlb entries => 8` → `32` | `mmucapi` | FAIL `Result=84` (`0x54`) |
| M6 | `core/cpu.vhd` `u_itlb entries => 8` → `2` | `mmucapi` | FAIL `Result=82` (`0x52`) |

Three things this table says that are worth reading twice.

**The `entries` generics are now bracketed from both sides.** M1/M2 and M5/M6
make each array's size a *measured* property: the suite is red if the array is
larger than the RTL says and red if it is smaller. "TLB pressure greater than
the entry count" stopped being a description of the working set and became an
assertion about the hardware.

**M3 and M4 split `mmucapd` from `mmucapsub`, and that is the point.** Both are
"assume one page size" shortcuts — one on the install path, one on the match
path — and both leave every base-page guard in the suite green. Only a
non-base-first superpage touch sees them.

**M3's code was NOT what the guard's author predicted.** `mmucapsub.S`'s header
originally said M3 would fail probe 2 (`0x25`). It fails leg S's very first
data check (`0x11`) instead: with `pm` forced to 0 the entry's
`page_offset_mask` is empty, so PA bits 13:12 come from the (zero) PPN rather
than the VA and the first sub-page-3 touch reads the mapping *base's* frame.
Relocation breaks before the coverage property is reached. The header records
the measured value and says so. That is the reason to run mutations rather than
argue them: the argument was directionally right and specifically wrong, which
is the failure mode that survives review.

Leg M of `mmucapi` (codes `0x55`–`0x59`) has **no dedicated RTL mutation**. It
is carried by M0 and by the exactness of its sum, and its header says so
plainly rather than implying coverage it does not have.

---

## 5. Adding a parameterisation

`mmucapd.S` is written to be extended by wrapper, in the shape
`mmuwalktagmbz.S` / `mmudspcprobe_late*.S` already use:

```
#define CAP_PM       <0..>      /* mapping size: PAGE_SZ << (2*CAP_PM) */
#define CAP_FIRSTSUB <0..>      /* which 4 KB sub-page is touched FIRST */
#include "mmucapd.S"
```

Everything else — the seed loop, the alias arithmetic, the probe windows, the
result codes — follows from those two. Three constraints on the values:

* **Every mapping must still cost exactly one TLB entry**, or `N_SMALL` and
  `N_LARGE` stop bracketing the array size. That holds for any `CAP_PM`.
* **P5.** Every VA touched under `AT=1` must lie in `[0, 0x0100_0000)`, because
  the raw VA reaches the bus while a miss is walked and the cosim backs only
  16 MB. The window is `_frames + ALIAS_DELTA` for `N_LARGE * MAP_SPAN` bytes,
  so at `N_LARGE = 24`: `CAP_PM = 2` (64 KB) needs 1.5 MB and is comfortable,
  `CAP_PM = 3` (256 KB) needs 6 MB and fits but is unwieldy, and `CAP_PM = 4`
  (1 MB) needs 24 MB and does not fit at all. Lower `N_LARGE` and the bracket
  loosens, so that is a trade, not a free knob.
* **Image size.** The frames are `.space`-filled in the image, so the `.img`
  grows as `N_LARGE * MAP_SPAN`. Measured: 108 KB at `CAP_PM=0`, 416 KB at
  `CAP_PM=1`; a `CAP_PM=3` build would be ~6 MB.

A new wrapper needs registering in **three** places — `sim/mmu_sim.sh` (both
the suite loop and the single-guard `case` arm), `sim/tests/Makefile` (an
`.elf: .o` rule *and* a `.o: mmucapd.S` dependency so the wrapper rebuilds when
the harness changes), and `.github/workflows/full-regression.yml`. Run
`scripts/guard_list_drift.sh` afterwards; it is cheap and it catches the one
mistake that is easy to make here.

---

## 6. Reproducing

```
docker run --rm \
  -v $PWD:/w -v <jcore-soc>:/jcore-soc -v <jcore-soc>/tools:/tools \
  -e JCORE_SOC=/jcore-soc -w /w \
  ghcr.io/mountain-reverie/jcore-cpu-ci:latest \
  bash -lc 'sim/mmu_sim.sh mmucapd'
```

The `/tools` mount is load-bearing: `sim/Makefile` resolves `TOOLS_DIR` to
`../../../tools` and the build dies with `/ghdl.mk: No such file or directory`
without it.

Drop `-n` for anything that touches RTL — see `CLAUDE.md`'s note on `-n`
measuring stale hardware. Every row of the table in §4 was rebuilt.

Measured completions, taken as the final timestamp of an `MMU_VCD` dump (which
ends at the "Test Passed" exit): `mmucapd` 21.37 µs, `mmucapsub` 37.86 µs,
`mmucapi` 40.47 µs. The stop times in both guard lists are 120 µs / 200 µs /
200 µs, i.e. margins of ~5.6× / ~5.3× / ~4.9×.
