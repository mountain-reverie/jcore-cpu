#!/usr/bin/env python3
"""Fixture tests for insns-collision-sweep.py.

    scripts/test-insns-collision-sweep.py

WHY THIS EXISTS. The sweep shipped with its non-vacuity demonstrated once, by
hand, in a commit message. That is not a property anyone can re-check, and this
repository's standard for a guard is a fixture plus a mutation -- the sweep's own
sibling in jcore-workspace has 107 of them. A one-time manual exercise decays
into a claim about the past.

Each case builds a synthetic insns.json in a temp directory and asserts the
sweep's EXIT STATUS and, where a failure is expected, which message produced it.
Exit status alone cannot tell "the check I meant fired" from "something else
did" -- the same distinction the workspace suite learned to assert.
"""

import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SWEEP = os.path.join(HERE, "insns-collision-sweep.py")
REAL = os.path.join(os.path.dirname(HERE), "docs", "insns.json")

# The two pairs the shipped BASELINE excuses. Cases that want a clean tree must
# include them or the "baseline entry no longer collides" arm fires -- which is
# itself one of the things under test.
BASELINE_ROWS = [
    {"format": "lds\tRm,A0", "code": "0100mmmm01110110", "DSP": True},
    {"format": "lds.l\t@Rm+,A0", "code": "0100mmmm01110110", "DSP": True},
    {"format": "sts.l\tDSR,@-Rn", "code": "0100nnnn01100010", "DSP": True},
    {"format": "sts.l\tA0,@-Rn", "code": "0100nnnn01100010", "DSP": True},
]


def run(doc):
    tmp = tempfile.mkdtemp(prefix="sweep-")
    path = os.path.join(tmp, "insns.json")
    with open(path, "w") as fh:
        if isinstance(doc, str):
            fh.write(doc)
        else:
            json.dump(doc, fh)
    p = subprocess.run([sys.executable, SWEEP, path],
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


CASES = []


def case(name, expect_fail, expect_text=None):
    def wrap(fn):
        CASES.append((name, expect_fail, fn, expect_text))
        return fn
    return wrap


def doc(rows):
    return {"instructions": BASELINE_ROWS + rows}


@case("the real docs/insns.json passes", False)
def _():
    with open(REAL) as fh:
        return json.load(fh)


@case("baseline-only input passes", False)
def _():
    return doc([])


@case("a new same-variant identical encoding fails", True,
      "new same-variant encoding collision")
def _():
    return doc([
        {"format": "mov\tRm,Rn", "code": "0110nnnnmmmm0011", "J4": True},
        {"format": "zzz\tRm,Rn", "code": "0110nnnnmmmm0011", "J4": True},
    ])


@case("an identical encoding on DISJOINT variants passes", False)
def _():
    # The rule that keeps the sweep usable. LDC Rm,PTEH and DSP's LDC Rm,MOD
    # share an encoding and never ship on one core; failing on that would fail
    # on ~94 legitimate entries and the sweep would be deleted.
    return doc([
        {"format": "ldc\tRm,PTEH", "code": "0100mmmm01011110", "J4": True},
        {"format": "ldc\tRm,MOD", "code": "0100mmmm01011110", "DSP": True},
    ])


@case("a baseline entry that no longer collides fails", True,
      "no longer collides")
def _():
    # The list may only shrink, and it must not outlive what it excuses.
    return {"instructions": BASELINE_ROWS[:2]}


@case("an empty instruction array fails closed", True,
      "nothing was swept")
def _():
    return {"instructions": []}


@case("a missing instructions key fails closed", True,
      "nothing was swept")
def _():
    return {}


@case("unparseable JSON fails closed", True, "cannot read")
def _():
    return "{not json"


@case("rows with no boolean variant column fail closed", True,
      "no boolean product columns")
def _():
    # Every pair would trivially share no variant, so the sweep would report
    # zero collisions over any input at all.
    return {"instructions": [{"format": "a", "code": "0000000000000000"},
                             {"format": "b", "code": "0000000000000000"}]}


@case("rows carrying no code at all fail closed", True,
      "nothing to compare")
def _():
    return {"instructions": [{"format": "a", "J4": True},
                             {"format": "b", "J4": True}]}


def main():
    passed = failed = 0
    for name, expect_fail, fn, expect_text in CASES:
        rc, out = run(fn())
        status_ok = (rc != 0) == expect_fail
        text_ok = expect_text is None or expect_text in out
        crashed = "Traceback" in out
        ok = status_ok and text_ok and not crashed
        why = ""
        if crashed:
            why = "  [CRASH]"
        elif not status_ok:
            why = "  [exit %d; expected %s]" % (
                rc, "non-zero" if expect_fail else "0")
        elif not text_ok:
            why = "  [exit status agreed; wanted message %r]" % expect_text
        print("%-4s %s%s" % ("pass" if ok else "FAIL", name, why))
        if ok:
            passed += 1
        else:
            failed += 1
            for line in out.splitlines():
                print("       | %s" % line)
    print("\n%d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
