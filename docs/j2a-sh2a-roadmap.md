# J2A — SH-2A Integer Instruction Roadmap (Handover)

**Purpose:** Complete the SH-2A *integer* instruction set on the **J2A** CPU variant.
This document is a handover: it records what is already built and proven, the two
reusable hardware mechanisms, and a grouped, ordered plan for every remaining
instruction, with the gotchas learned during bring-up.

**Scope:** SH-2A **integer** only. Out of scope (deliberate): the SH-2A FPU
(~40 FP ops + FPU regfile), register banking (`resbank`, `ldbank`, `stbank`,
`ldc/stc TBR`), `pref @Rn`, and `jsr/n @@(disp8,TBR)` (needs TBR). J4 = SH-4
user-space is a separate track.

**Hard invariant (every change):** J1/J2/J4 generated decoders stay
**byte-identical** (`make -C decode diff` clean; `make -C decode generate-j4`
unchanged) and area/timing-neutral. Everything SH-2A is gated behind the
`SH2A_ARCH` generic, the `spec/sh2a` overlay, or variant-additive generator
mechanisms. J2A is a build-time variant: `make -C decode generate-j2a`,
`CONFIG_SH2A_ARCH=1` in sim.

---

## 1. Status

### Done & merged
- **Phase 0 — generator two-word substrate + J2A variant** (PR #105, merged):
  `Parse32`, two-word `KeyOf2`/`Key`, spec `Opcode2` field, disp12/imm20
  ext-word immediates (`IMM_U_12_2`, `IMM_S_20_0`), the `spec/sh2a` overlay +
  `timing/j2a.toml` + `generate-j2a` target + `docs/insns.json` J2A column, and
  a data-driven record-reset refactor enabling variant-additive control signals.
- **Mechanism A — 32-bit two-word** proven in-pipeline (PR #105, merged):
  `MOV.L @(disp12,Rm),Rn` runs correctly (disp=0 and disp≠0).
- **insns.json two-word sync fix** (PR #105): the `insns` tool now matches
  two-word rows by both words (`keyOfCode`/`keyOfInstr`), no duplicate rows.

- **Mechanism B — multi-register counted loop** proven (PR #106, merged):
  `movml.l Rm,@-R15` (push R0..Rm) + a back-to-back regression. Includes the
  fetch-skip fix (see gotchas).
- **Group 5 — single-word mov extras** (PR #118, merged):
  `mov.{b,w,l} R0,@Rn+` (post-increment store) and `mov.{b,w,l} @-Rm,R0`
  (pre-decrement load).
- **Group 6 — bit-manip register forms** (PR #118, merged):
  `bclr #imm3,Rn`, `bset #imm3,Rn`, `bld #imm3,Rn`, `bst #imm3,Rn`
  (new `ni3` format; BST via `BITSET` alumanip + `sr.t` into `manip()`).
- **Group 7 — single-word misc** (PR #118, merged):
  `movrt Rn` (¬T → Rn) and `nott` (invert T).

- **Group 8 PR-A — arithmetic clips/clipu** (PR merged):
  `clips.b/w Rn`, `clipu.b/w Rn` (saturate Rn to signed/unsigned byte/word
  range).
- **Group 8 PR-B — arithmetic mulr** (PR merged):
  `mulr R0,Rn` (Rn ← R0 × Rn; reuse the multiplier, result to Rn).
- **Group 8 PR-C — arithmetic divs/divu** (pending):
  `divs R0,Rn`, `divu R0,Rn` (SH-2A signed/unsigned divide).

- **Group 9 — delay-slot-less branches** (PR merged):
  `rts/n`, `rtv/n Rm`, `jsr/n @Rm` (return and branch without delay slot).

### Instructions live in J2A today
`mov.l @(disp12,Rm),Rn`, `movml.l Rm,@-R15`, `mov.{b,w,l} R0,@Rn+`,
`mov.{b,w,l} @-Rm,R0`, `bclr #imm3,Rn`, `bset #imm3,Rn`, `bld #imm3,Rn`,
`bst #imm3,Rn`, `movrt Rn`, `nott`, `clips.b Rn`, `clips.w Rn`, `clipu.b Rn`,
`clipu.w Rn`, `rts/n`, `rtv/n Rm`, `jsr/n @Rm`.

---

## 2. The two reusable hardware mechanisms

### Mechanism A — 32-bit two-word (extension word)
The prefetch already surfaces the second word in `if_dr_next`. `decode_core.vhm`
has an `SH2A_ARCH`-gated `ext_word` register (`g_ext_word`) that latches
`if_dr_next` in lockstep with `op` and forwards it (variant-additive port) into
`decode_table`, where the immediate mux sources disp12/imm20 from `ext_word`.
- Generator: a two-word instruction is a spec `[[instr]]` with both `opcode` and
  `opcode2`. Use format token `nmd12` (register nibbles as `nm`, 12-bit
  immediate width). Immediates: `IMM_U_12_2` (disp12×4), and add `IMM_U_12_0/_1`
  (×1/×2) for byte/word. `IMM_S_20_0` (imm20) already exists (unused).
- Fetch/PC: BOTH slots of the instruction must carry `if_issue` so PC advances
  +4 across the pair; the extension word passes through `if_dr` on the held slot
  but is never decoded (op holds).
- **Reuse for:** all `@(disp12,…)` movs, `movi20/movi20s`, `band.b…@(disp12,Rn)`.

### Mechanism B — multi-register counted loop
`decode_core.vhm` `g_movml` (SH2A_ARCH-gated) re-presents a single store/load
slot m+1 times: `movml_hold` forces `instr_seq_zero:='0'` (hold `op`) without
advancing `op.addr`; `movml_idx` (4-bit) overrides `op.code(11:8)` (the
per-iteration register) walking m→0; the loop exits at idx=0 on the slot's own
`dispatch`. `reg_conf` (via `next_id_stall_a` gating the index decrement) paces
iterations. **`if_issue`/`incpc` are gated by `movml_hold`** so the PC advances
exactly once, at loop exit.
- **Reuse for:** `movml.l @R15+` (pop), `movmu.l` (adds PR to the range).
- Generalizing: the pop direction counts the index UP and loads (R15 post-inc);
  `movmu` extends the range to include PR. The op.code-override + hold-loop
  substrate is the same.

---

## 3. Remaining instructions, grouped by mechanism

Effort key: **S** small (single-word, existing datapath), **M** medium (new
datapath op or two-word reuse), **L** large (new mechanism or RMW sequencing).

### Group 1 — 32-bit two-word disp12 movs (Mechanism A)  — effort M
Reuse the ext_word path; add byte/word sizes, the store direction, and unsigned
zero-extend. Add `IMM_U_12_0`/`IMM_U_12_1` for ×1/×2 scaling.
- `mov.b @(disp12,Rm),Rn`, `mov.b Rm,@(disp12,Rn)`
- `mov.w @(disp12,Rm),Rn`, `mov.w Rm,@(disp12,Rn)`
- `mov.l Rm,@(disp12,Rn)`  *(load already done)*
- `movu.b @(disp12,Rm),Rn`, `movu.w @(disp12,Rm),Rn`  *(zero-extend loads)*

### Group 2 — movi20 / movi20s (Mechanism A, imm20)  — effort M
20-bit immediate: high 4 bits `op.code(11:8)`, low 16 `ext_word`. `IMM_S_20_0`
already emitted. `movi20s` shifts the imm20 left 8 (a scaled variant, add
`IMM_S_20_8`). Single-slot compute-and-write to Rn.
- `movi20 #imm20,Rn`, `movi20s #imm20,Rn`

### Group 3 — bit-manip memory, two-word (Mechanism A + RMW)  — ✅ DONE
All 10 ops shipped on branch `feat/j2a-group3-bitmem-rmw`. Two-word (disp12 in
ext_word, imm3 in first-word bits `0iii` at op.code(6:4), new `nd12i3` format +
`(6:4)` MASK3_64 mask). RMW stores (`bset/bclr/bst.b`) load byte @(disp12,Rn) →
modify → store; loads (`bld/bldnot.b`) set T from the bit; T-combine
(`band/bandnot/bor/bornot/bxor.b`) set `T = T ⟨op⟩ bit` via SH2A-gated manip
cases. Two key mechanisms: an **SH2A ext-word capture register** (decode_core,
triggered on `imm_from_ext`, decoder-independent) so the LATE ext[15:12]
op-discrimination sees word2; and the manip+sr.t T-combine. Base J1/J2/J4
decode byte-identical; base area: j2 flattened −126 LUT4, j1 +23 (alumanip_t
4→5 bit). Also added a base direct-vs-ROM decoder symmetry test (regression
Step 6b). ⚠️ ROM decoder can't runtime-discriminate two-word ext ops → these
are direct-decoder-only (j2a always binds direct).
- ✅ `band.b`, `bandnot.b`, `bor.b`, `bornot.b`, `bxor.b`, `bset.b`, `bclr.b`,
  `bst.b`, `bld.b`, `bldnot.b`  — all `#imm3,@(disp12,Rn)`

### Group 4 — multi-register pop + movmu (Mechanism B)  — effort M
- `movml.l @R15+,Rn` — pop; index up, load, R15 post-increment.
- `movmu.l Rm,@-R15`, `movmu.l @R15+,Rn` — like movml but the range includes PR.
Watch the same fetch-skip / interlock discipline as movml push (already solved).

### Group 5 — single-word mov extras  — effort S
Standard datapath, no new mechanism. Post-inc store from R0 / pre-dec load to R0.
- `mov.{b,w,l} R0,@Rn+`  (post-increment store)
- `mov.{b,w,l} @-Rm,R0`  (pre-decrement load)

### Group 6 — bit-manip register forms  — effort S
Single-word; bit op on a register selected by `#imm3`. Straightforward microcode.
- `bclr #imm3,Rn`, `bset #imm3,Rn`, `bld #imm3,Rn`, `bst #imm3,Rn`
- (`bld`/`bst` interact with the T bit.)

### Group 7 — single-word misc  — effort S
- `movrt Rn`  (¬T → Rn; the inverse of the existing `movt`)
- `nott`      (invert T)

### Group 8 — arithmetic  — effort M
Single-word but each needs a new ALU behavior.
- ✅ `clips.b/w Rn`, `clipu.b/w Rn`  (saturate Rn to signed/unsigned byte/word
  range — new saturation logic in the ALU/manip unit) — **PR-A done**
- ✅ `mulr R0,Rn`  (Rn ← R0 × Rn; reuse the multiplier, result to Rn) — **PR-B done**
- `divs R0,Rn`, `divu R0,Rn`  (SH-2A signed/unsigned divide — verify semantics
  vs the existing DIV0/DIV1 step machinery; these may be multi-cycle) — **PR-C pending**

### Group 9 — delay-slot-less branches ✅ — DONE
SH-2A branches that do NOT execute a delay slot — a distinct branch microcode
path from the existing (delay-slotted) RTS/JSR. Care around PC/pipeline timing.
- ✅ `rts/n`, `rtv/n Rm` (return + Rm→R0), `jsr/n @Rm`

---

## 4. Suggested order

1. **Group 4** (movml pop + movmu) — finishes Mechanism B while it's fresh; PR #106 is the base.
2. **Group 1** (disp12 byte/word + store + movu) — highest-value, direct Mechanism A reuse.
3. **Group 2** (movi20) — small Mechanism A extension, unblocks large-immediate codegen.
4. **Groups 5, 6, 7** (single-word movs, bit-manip register, movrt/nott) — cheap, high count, build momentum.
5. **Group 8** (arithmetic) — new ALU ops; do clips/clipu together, then mulr, then divs/divu (most care).
6. **Group 9** (delay-slot-less branches) — new branch path.
7. **Group 3** (bit-manip memory RMW) — most complex; two-word + read-modify-write.

Each group is a PR against master, gated behind `SH2A_ARCH`, with in-pipeline
`sim/tests/sh2a_*.S` tests and the byte-identity + `insns-check` gates.

---

## 5. Gotchas (hard-won — read before starting)

- **`op.addr`-hold loops must suppress `if_issue`/`incpc`.** Any loop that
  re-presents a dispatch slot (Mechanism B) will otherwise fetch past and skip
  the following instructions. This bit movml hard (a back-to-back `mov.l @r15+`
  was skipped → PC into garbage). Gate both with `not(movml_hold)`. General rule
  for any future counted/held loop over an `if_issue`-carrying slot.
- **`ext_word` cannot live in `operation_t`.** Hand-written `decode_core.vhm`
  would reference a field absent on base builds (a `if SH2A_ARCH` block still
  elaborates its body) → base compile break. Keep it a separate SH2A_ARCH-gated
  register + port; `decode_core.vhd` is v2p-generated and NOT in the cpugen
  byte-identity set, so it's free to change.
- **`SH2A_ARCH` reaches `decode_core` only by CONFIGURATION**, not generic map
  (like `MMU_ARCH`). The sim needs `cpu_sim_sh2a`/`cpu_decode_direct_mmu_sh2a`
  (in `core/cpu_config.vhd`) selected by `CONFIG_SH2A_ARCH` in `sim/cpu_tb.vhd`.
  A generic-map alone reaches the datapath but leaves `decode_core` gated off.
- **Do NOT cross decode→datapath with a new variant-additive `decode` port.**
  It forces wrapping `u_decode` in a generate, which breaks every `cpu_config.vhd`
  `for u_decode` configuration ("no component instantiation u_decode"). Keep
  new loop/counter logic inside `decode_core` (op.code override) or inside the
  datapath keyed off an existing control record.
- **`decode_core.vhm` is preprocessed by `tools/v2p`, not cpp** — use VHDL
  `if <GENERIC> generate`, never C `#if`. Mirror `g_if_pc`/`g_ext_word`/`g_movml`.
- **The direct decoder is QMC-reduced.** Overriding `op.code` bits (Mechanism B)
  is safe for register-select fields that are literal in the reduction, but
  verify a new instruction's control signals in the *generated* direct table,
  not just the simple table (the J2A sim uses `direct`).
- **Register index width:** the `op.code` register nibble is **4 bits**, not the
  5-bit `regnum_t`. Concatenating a 5-bit index into a 16-bit opcode bound-checks.
- **insns.json:** two-word instructions now match existing SH-reference rows via
  `keyOfCode`/`keyOfInstr`. Never hand-edit `docs/insns.json`; run
  `make -C decode insns` and commit. CI `insns-check` gates it.
- **Test harness:** hand-encode SH-2A ops with `.word` — this IS required, but
  the reason is the build flag, not the assembler. `sh2-elf-as` (binutils 2.43.1)
  can decode `movml.l`/`movmu.l` when given NO `-m` flag, BUT `sim/tests/Makefile`
  `CFLAGS = -m2 …`, and `-m2` (SH-2) rejects SH-2A opcodes ("opcode not valid for
  this cpu variant"). There is no working `-m2a` in this binutils (the flag
  doesn't exist), and `-m3`/`-m4` also reject `movml.l`. So `.word` stays. Model
  tests on `sim/tests/sh2a_movl12.S` /
  `sh2a_movml.S`; add `<name>.elf: <name>.o` to `sim/tests/Makefile`. Run:
  `make -C decode generate-j2a && (cd sim && make CONFIG_SH2A_ARCH=1 cpu_ctb …)`;
  ALWAYS `make -C decode generate` after to restore the base decoder.
  ghwdump for waveforms (times in fs).

---

## 6. Open follow-ups / tech debt

- **⚠️ KNOWN GAP — SH-2A + MMU restart-safety is UNVALIDATED (test infra cannot
  build a J2A+MMU decoder).** The `movml`/`movmu` pop and push "restart-safety"
  tests (`sh2a_*_restart.S`, PRs #107/#109 + the restart-safe-push branch) have
  **never genuinely run** — they cannot set up the TLB, so they either garbage-
  fetch or silently no-op; earlier "PASSED" reports were artifacts. Root cause:
  the J2A decoder is generated from `spec/sh2a` ONLY (`make -C decode generate-j2a`,
  `-overlay spec/sh2a`), which OMITS the SH-4 MMU-control instructions
  (`LDTLB` 0x0038, `LDC Rn,PTEH/PTEL/ASIDR`) that live in `spec/sh4/mmu.toml`. So
  in a `cpu_sim_sh2a` (MMU-on) build those instructions don't decode → `tlb_wr`
  never asserts (`core/tlb.vhd:170`) → empty TLB → enabling `MMUCR.AT` gives a
  garbage PC. **No CI job builds `CONFIG_SH2A_ARCH`+MMU either.** Two secondary
  facts: the MMU sim needs **all three** flags `CONFIG_PRIV_ARCH=1 CONFIG_MMU_ARCH=1
  CONFIG_SH2A_ARCH=1` (MMU_ARCH is nested under `#if CONFIG_PRIV_ARCH` in
  `cpu_tb.vhd`; the 2-flag command used everywhere silently disables MMU); and the
  proper fix — a decoder combining `spec/sh2a`+`spec/sh4` — is not currently
  generatable (single `-overlay` flag; combining trips the ROM emitter's
  `IMM_P256` 6-bit-selector width limit; the J2A sim uses the *direct* decoder, so
  a direct-only combined build may sidestep the ROM limit). Full analysis:
  `docs/superpowers/specs/2026-07-09-j2a-restart-safe-push-design.md` +
  `.superpowers/sdd/mmu-garbage-rootcause.md`.
  **SCHEDULED:** verify SH-2A restart-safety (pop + push) when SH-2A instructions
  are added to **J4** — J4 already includes `spec/sh4` (LDTLB etc.), so a J4+SH-2A
  decoder decodes both the SH-2A ops AND the MMU-setup instructions, finally
  letting the `sh2a_*_restart.S` tests actually load the TLB and prove restart
  behavior. Until then, SH-2A push/pop restart-safety rests on the structural
  argument (R15 written once, loads/stores idempotent) + code review + non-MMU
  round-trip tests only.
- **`reg_conf` weak interlock on movml** was worked around via the loop's natural
  pacing; the general "instruction after a zbus-writeback op" interlock for
  SH-2A ops should be reviewed when adding movmu/pop.
- **MULR MAC-shadow restart-handling (Group 8 PR-B).** `mulr` saves/restores
  MACH:MACL via two `SH2A_ARCH`-gated shadow registers across a 5-slot sequence.
  `mulr` performs no memory access so it cannot itself take a D-side TLB fault,
  and instruction atomicity (interrupts sampled at boundaries) covers the
  multi-slot sequence today. When SH-2A lands on J4+MMU, review whether the
  MAC-shadow state needs restart-handling like the movml/movmu push/pop path.
- Nits carried from PR #105/#106 review: the `cpu_decode_direct_mmu` binding is
  now triplicated (mmu / mmu_sh2a / dsp_alu) with no CI tie; `CONFIG_DSP_ALU`
  vs `CONFIG_SH2A_ARCH` in `cpu_tb.vhd` are mutually exclusive with no guard;
  add a `regression.sh` check for `spec/static/*.vhd` vs generated drift.
- **1.5 area/timing gauge:** run the iCE40/ASIC synthesis gauge on a full J2A
  build once several groups land, to quantify J2A's added cost vs J2.

---

## 7. Key files
- Generator: `decode/gen-go/` — `internal/opcode` (Parse/Parse32),
  `internal/insns` (KeyOf/KeyOf2, sync), `internal/microcode/immval.go`
  (immediates), `internal/spec` (Opcode2, fields), `internal/model` (build,
  variant-additive), `spec/sh2a/*.toml` (the overlay), `timing/j2a.toml`.
- Hardware: `decode/decode_core.vhm` (`g_ext_word`, `g_movml`, sequencer),
  `core/datapath.vhm`, `core/cpu_config.vhd` (sh2a configs), `core/cpu.vhd`.
- Sim: `sim/cpu_tb.vhd` (`CONFIG_SH2A_ARCH`), `sim/tests/sh2a_*.S`,
  `sim/tests/Makefile`.
- Build: `make -C decode generate-j2a`, `make -C decode diff`,
  `make -C decode insns[-check]`, `decode/gen-go/regression.sh`.


### Group 8 — arithmetic — ✅ COMPLETE (2026-07-19)
clips/clipu (PR-A) + mulr (PR-B) + **divs/divu (PR-C)** all shipped. divs/divu = an isolated SH2A_ARCH-gated sequential divider (`core/divider.vhd`, unit-tested via `divider_unit_tap`), wired like `mult(seq)` (busy→stall), ~33-cycle. Base J1/J2/J4 byte-identical (only illegal-routing terms; the g_div datapath prunes on base — verified: isolated illegal-routing j1 +87, full branch +70, divider adds nothing). Completes the J2A INTEGER instruction set (remaining SH-2A = FPU, out of scope; register banking descoped).

### TBR group — ✅ COMPLETE (2026-07-24) — J2A INTEGER SET COMPLETE
`ldc Rm,TBR`, `stc TBR,Rn`, `jsr/n @@(disp8,TBR)` shipped (branch feat/j2a-tbr).
TBR is a named register at extended-register-file **index 23** (`"10111"`) — the free
slot in the full privileged layout, so a future J4A (PRIV_ARCH ∧ SH2A_ARCH) never
collides. `rf_depth` SH2A-gated (`priv→32; sh2a→24; else→21`), so J1/J2 stay 21 and
J4 stays 32 (const-fold, base-neutral); only J2A grows to 24 (slots 21–22 dead —
the deliberate ASIC-register-file cost). `ldc/stc TBR` are pure spec rows mirroring
`ldc/stc GBR` (`zbus_sel="Y"`); `jsr/n @@(disp8,TBR)` is a 6-slot memory-indirect
delay-slot-less call composed from proven patterns (Group 9 PR-save + `@(disp,GBR)`
base+disp read + RTE mem→PC), robust under memory wait states via the existing
slot-stretch. Base J1/J2/J4 byte-identical except the illegal-routing line for the 3
opcodes. Cosim `sh2a_tbr.S` Test Passed; opus whole-branch review clean.

**This completes the J2A INTEGER instruction set.** Remaining SH-2A = register
banking (descoped: compiler never emits it) + FPU (out of scope: a separate variant).
