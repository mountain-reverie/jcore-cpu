# HANDOVER — Is the T-bit delay-slot hazard a J2 core bug or a gcc codegen bug?

Date: 2026-07-02
Repo: jcore-cpu (this repo; `components/cpu` submodule of jcore-soc).
For: a fresh, hands-on session that can build/run the jcore-cpu simulator AND is
comfortable reading the SuperH-2 (SH-2) programming manual online.

---

## 1. One-paragraph summary

While bringing up dual-core SMP on jcore-soc (ULX3S), a bootloader poll loop
compiled by `sh2-elf gcc -Os` **mis-executed on the J2**: a `bt.s` (delayed
conditional branch) whose **delay slot contains a T-bit–setting instruction**
(`cmp/eq` or `dt`) that feeds the **immediately following conditional branch**
(`bf`/`bf.s`) caused the loop to exit after a single iteration instead of
looping. Replacing the loop with a form where the conditional branch reads T
directly from the preceding `cmp/eq` (no T-setter in a delay slot) works
perfectly. **Your job: determine whether this is (a) a genuine J2 RTL bug in how
the T bit is produced/forwarded around a delayed branch + its delay slot, or (b)
`gcc -Os` emitting an illegal/ill-advised delay-slot sequence that real SH-2
silicon also would not execute the way the C intended.** This requires checking
the SH-2 architectural rules for delay slots and T-bit timing, then reproducing
minimally in this repo's simulator.

The jcore-soc side is already worked around (a hazard-free poll loop, committed
in the `boot` submodule). This investigation is to fix the *root* — either in the
J2 core here, or by filing/qualifying a compiler issue.

## 2. The exact instruction sequences (SH-2, verbatim from objdump)

**FAILS (original compound `while(*s != 0xC0DE0001 && spins < 2000000) spins++;`):**
```
250: 31 60   cmp/eq r6,r1     ; T = (spins == 2000000)   -> T=0
252: 67 22   mov.l @r2,r7     ; r7 = *sentinel           -> 0
254: 8d 02   bt.s  0x25c      ; branch if T (uses T from 0x250); DELAY SLOT = 0x256
256: 37 30   cmp/eq r3,r7     ; T = (*sentinel == 0xC0DE0001) -> T=0   [T-setter in delay slot]
258: 8f fa   bf.s  0x250      ; branch if !T (uses T from 0x256); DELAY SLOT = 0x25a
25a: 71 01   add   #1,r1      ; spins++
```

**ALSO FAILS (`for(spins=2000000; spins; spins--){ if(*s==X) break; }`):**
```
24e: 67 32   mov.l @r3,r7     ; r7 = *sentinel
250: 37 20   cmp/eq r2,r7     ; T = (*sentinel == 0xC0DE0001)
252: 8d 01   bt.s  0x258      ; branch if T (match -> exit); DELAY SLOT = 0x254
254: 41 10   dt    r1         ; r1--; T = (r1 == 0)        [T-setter in delay slot]
256: 8b fa   bf    0x24e      ; branch if !T (loop); reads T from 0x254 (dt)
258: 61 32   mov.l @r3,r1     ; (loop exit)
```

**WORKS (`while(*s != 0xC0DE0001u){}` — no spin counter):**
```
L: mov.l @r3,r7              ; read sentinel
   cmp/eq r2,r7             ; T = match
   bf     L                 ; bf reads T directly from cmp/eq; NO delay slot, NO T-setter between
```

**WORKS (bounded, `volatile` counter — the committed jcore-soc workaround):**
`for (volatile unsigned spins = 2000000u; spins; spins--) { if (*s == X){ran=1;break;} }`
— the `volatile` forces the counter's decrement/test to load/store, so gcc does
not fold a T-setter into the sentinel-check branch's delay slot.

**Common shape of the failures:** `bt.s TARGET` whose delay slot is a T-setting
instruction, immediately followed by a conditional branch that consumes T. The
observed hardware symptom (waveform, jcore-soc ULX3S dual-core sim): the loop's
back-branch was **not taken** when it should have been — cpu0 fetched straight
past the loop after one iteration, having read the sentinel exactly once.

## 3. The precise question to answer (from the SH-2 manual)

Research the SH-2 (SH7600 / SH-2 core) **Programming Manual**, sections on:
- **Delayed branch instructions** and the list of **"illegal delay slot
  instructions"** / restrictions. Confirm whether a T-setting instruction
  (`cmp/eq`, `dt`, `tst`, `add` with carry, `shll`, etc.) is *permitted* in the
  delay slot of `bt.s`/`bf.s`, and what the defined behavior is.
- **T-bit timing across a delayed branch**: when `bt.s`/`bf.s` is NOT taken and
  its delay-slot instruction modifies T, is that new T guaranteed visible to the
  *next* instruction (here another conditional branch)? Or is there a documented
  hazard/"undefined" window?
- Whether **two conditional branches with a T-dependency chain through a delay
  slot** (bt.s … cmp/eq(ds) … bf) is architecturally well-defined at all.

Then decide:
- **If SH-2 says this is illegal / undefined** → it is a **gcc -Os codegen bug**
  (it should not schedule a T-setter into that delay slot). Deliverable: a
  minimal C/asm reproducer + the manual citation; file/di­agnose against the
  sh2-elf toolchain. The J2 is arguably "correct to do anything."
- **If SH-2 says this is well-defined and must loop** → it is a **J2 RTL bug** in
  T-bit production/forwarding around the delayed branch. Deliverable: the failing
  RTL path + a fix + a regression test.

## 4. How to reproduce in THIS repo (standalone, no jcore-soc needed)

The J2 sim runs SH-2 test ROMs directly. Reproduce with a minimal hand-written
assembly test — this isolates it from gcc and from the SoC.

- Test format: `testrom/tests/*.s` are SH-2 asm tests; on failure they
  `jmp @r13` (a fail handler), otherwise fall through to pass. `testrom/tests/
  testbra.s` already tests **"BRA and load contention"** and RTS/write contention
  — it is the natural sibling for a new **delay-slot T-bit** case, and a good
  style reference.
- Build/run (see repo `CLAUDE.md` + `sim/README.txt`):
  ```
  cd sim && make                 # builds cpu_ctb + ram.img etc.
  ./cpu_ctb --stop-time=180us    # runs the test ROM; add --wave=wave.ghw to trace
  ```
  `testrom/Makefile` links `tests/*.o` into the ROM.

**Minimal reproducer to add** (as `testrom/tests/testtbit.s`, wired into
`testrom/Makefile` TESTS_OBJS and the test main): assemble the exact failing
shape and assert the loop iterates the expected number of times. Sketch:
```
    ! r1 = counter (e.g. 3), r2/r7 arranged so cmp/eq is FALSE.
    ! loop must run r1 times; if the hazard bites, it exits after 1.
loop:
    cmp/eq r2, r7        ! T = (r7 == r2); arrange so this is FALSE
    bt.s   done          ! not taken (T=0)
    dt     r1            ! delay slot: r1--, T=(r1==0)   [the hazard]
    bf     loop          ! should loop while r1 != 0
done:
    ! check r1 == 0 (ran to completion). If r1 != 0 -> hazard reproduced -> fail.
```
Drive `r7`/`r2` so `cmp/eq` is deterministically false, and pre-load `r1` with a
small count. Confirm on the J2 sim whether it loops `r1` times or exits early.
Also add the **working** shape (bf directly off cmp/eq) as a control.

Cross-check the *intended* behavior against a reference SH-2 model if available
(e.g. another SH-2 simulator, or the manual's cycle description). If the J2
disagrees with a spec-faithful model on a *legal* sequence → core bug.

## 5. Where to look in the RTL if it's the core

- Decoder / control for delayed branches and the delay-slot pipeline: `decode/
  decode_core.vhm`, `decode/decode_table_*.vhd`, `decode/gen-go/spec/` (the TOML
  is the source of truth for control signals).
- T-bit generation and the SR: `core/datapath.vhm` (ALU/`cmp`/`dt` producing T),
  `core/components_pkg.vhd`, `core/datapath_pkg.vhd` (pipeline regs). Look at when
  T is written vs when a conditional-branch reads it, and whether a delay-slot
  instruction's T reaches the *next* instruction's branch decision without a
  bubble/forward gap.
- Pay attention to the case where `bt.s`/`bf.s` is **not taken**: the delay slot
  still executes; verify its T write is not being squashed or ordered after the
  following branch's condition sample.

## 6. Deliverables

1. A definitive answer: **core bug** or **gcc codegen bug**, with the SH-2 manual
   citation for the delay-slot/T-bit rule that decides it.
2. A minimal in-repo reproducer (`testrom/tests/testtbit.s` or equivalent) that
   the J2 sim runs, plus the control (working) case.
3. If core bug: the RTL fix + the regression test green (`sim/` run), and note
   the blast radius (any real code with this shape).
4. If gcc bug: the reproducer, the citation, and a recommended toolchain
   issue/writeup; confirm the J2 sim behavior matches a spec-faithful reference.

## 7. Context / pointers

- jcore-soc side (already fixed, for background): `boot/main.c` `CONFIG_CPU1_DIAG`
  poll loop; commit `978f15c` on boot branch `feat/dualcore-smp-phase2`; jcore-soc
  superproject `3698883`. The waveform investigation that isolated this found the
  root cause is the poll loop, NOT the dcache/RTL/cache coherency that an earlier
  handover wrongly hypothesized — cpu1 runs and the shared-RAM mailbox is
  coherent; a single delayed read returns the sentinel.
- This repo: `CLAUDE.md` (build/sim), `sim/README.txt`, `testrom/tests/testbra.s`
  (delay-slot contention test precedent), `decode/` and `core/` (RTL).
- The J2 implements the SH-2 ISA; use the **SH-2 / SH7600 Programming Manual** as
  the architectural authority for delay-slot and T-bit semantics.
