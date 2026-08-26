#!/usr/bin/env python3
"""Fail on a NEW same-variant identical-encoding collision in docs/insns.json.

    scripts/insns-collision-sweep.py [docs/insns.json]

WHY THIS EXISTS, and why it is not just "fail on any collision".

`docs/insns.json` already carries a `collides` annotation, computed by
`annotateCollides` in decode/gen-go/internal/insns/sync.go and kept current by
`cpugen insns -check`. So every collision is already *visible*. What was missing
is a *verdict*: `collides` has ~94 entries and almost all of them are fine.
`fmov FRm,FRn` against `fmov DRm,DRn` is one encoding discriminated at run time
by `FPSCR.SZ`. `LDC Rm,PTEH` against DSP's `LDC Rm,MOD` is two variants that
never ship on the same core -- that is the whole reason `annotateCollides` links
merely-overlapping rows only when they share a variant.

The defect worth failing a build on is narrower and mechanical:

    two instructions with an IDENTICAL encoding that share an ENABLED variant.

On such a core the decoder cannot tell them apart. There is no run-time
discriminator and no configuration in which only one is present.

THE BASELINE. Two such pairs exist today, both in the DSP set, both real. A
sweep that failed on them would have been switched off the day it landed; a
sweep with no baseline would have had to be written as a warning, and a warning
is not a check. So they are named below and the list MAY ONLY SHRINK -- a
baseline entry that no longer collides is also a failure, so the list cannot
quietly outlive the defects it excuses. This is the same discipline as the
waiver list in docs/fact-ownership.md (jcore-workspace), and the same reason.

See jcore-workspace docs/decisions/0003-canonical-encoding-database.md.

Fails closed: a missing file, unparseable JSON, zero instructions, or zero rows
carrying an encoding are all failures. A sweep that finds nothing to sweep must
never report success.
"""

import itertools
import json
import os
import sys

# Pairs known to collide, as sorted (format, format) with tabs normalised to a
# single space. THIS LIST MAY ONLY SHRINK. Each entry needs a reason and an
# owner; "it was already like that" is why the list exists, not a reason to add
# to it.
BASELINE = {
    # 0100mmmm01110110 -- the DSP LDS pair. `lds Rm,A0` and `lds.l @Rm+,A0`
    # carry the same encoding in the source manual transcription; one of the
    # two is wrong. Owner: Wave-2 B4 (encoding sweep).
    ("lds Rm,A0", "lds.l @Rm+,A0"),
    # 0100nnnn01100010 -- the DSP STS pair, same shape, same owner.
    ("sts.l A0,@-Rn", "sts.l DSR,@-Rn"),
}


def fail(msg):
    print("::error::%s" % msg)
    print("FAIL: %s" % msg, file=sys.stderr)


def main(argv):
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = argv[1] if len(argv) > 1 else os.path.join(here, "docs", "insns.json")

    try:
        with open(path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError) as exc:
        fail("cannot read %s: %s" % (path, exc))
        return 1

    insns = doc.get("instructions")
    if not isinstance(insns, list) or not insns:
        fail("%s has no non-empty `instructions` array; nothing was swept, "
             "which is a failure and not a pass" % path)
        return 1

    # Variants are derived, not hardcoded: any key with a boolean value is a
    # product column. Hardcoding the list would mean a newly added product
    # (J2A and J4 are both recent) silently dropped out of the sweep.
    variants = sorted({k for e in insns for k, v in e.items()
                       if isinstance(v, bool)})
    if not variants:
        fail("no boolean product columns found in %s; every pair would "
             "trivially share no variant and the sweep would pass vacuously"
             % path)
        return 1

    by_code = {}
    for e in insns:
        code = (e.get("code") or "").strip()
        fmt = (e.get("format") or "").replace("\t", " ").strip()
        if not code or not fmt:
            continue
        by_code.setdefault(code, []).append((fmt, e))
    if not by_code:
        fail("no instruction in %s carries both a `code` and a `format`; "
             "there is nothing to compare" % path)
        return 1

    found = {}
    for code, entries in sorted(by_code.items()):
        for (fa, ea), (fb, eb) in itertools.combinations(entries, 2):
            shared = sorted(v for v in variants
                            if ea.get(v) is True and eb.get(v) is True)
            if shared:
                found[tuple(sorted((fa, fb)))] = (code, shared)

    rc = 0
    for pair in sorted(found):
        if pair in BASELINE:
            continue
        code, shared = found[pair]
        rc = 1
        fail("new same-variant encoding collision: `%s` and `%s` both encode "
             "as %s and are both present on %s. Re-home one of them with "
             "`cpugen freespace --avoid <the other> --form <its form>` "
             "(--avoid is comma-separated, and these formats contain commas, "
             "so pass one variant per invocation)."
             % (pair[0], pair[1], code, "/".join(shared)))

    for pair in sorted(BASELINE - set(found)):
        rc = 1
        fail("baseline entry `%s` / `%s` no longer collides. Delete it from "
             "BASELINE in %s -- the list may only shrink, and it must not "
             "outlive what it excuses."
             % (pair[0], pair[1], os.path.basename(__file__)))

    swept = sum(len(v) for v in by_code.values())
    print("swept %d instructions over %d variants (%s); %d same-variant "
          "identical-encoding collision(s), %d baselined, %d new"
          % (swept, len(variants), ",".join(variants), len(found),
             len(set(found) & BASELINE), len(set(found) - BASELINE)))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
