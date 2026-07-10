#!/usr/bin/env python3
"""Merge canonical metric JSONs into github-action-benchmark 'custom' inputs.

Splits metrics by direction into two arrays:
  smaller -> customSmallerIsBetter   speed/bigger -> customBiggerIsBetter
Each entry: {"name","unit","value","extra"}. `name` is prefixed with the
target ("asic-nangate45 · cpu/area").

Variant keying: github-action-benchmark identifies a series by its `name` only,
so to compare like-with-like (and not flag J1's larger LUT4 as a J2 regression)
each non-J2 variant gets a "[variant]" suffix on the name. **J2 keeps the bare
name** so its already-published history continues uninterrupted. The dashboard
strips the suffix to overlay J1/J2/J4 on one chart, colored by variant.
`extra` still carries the canonical variant.
Output order is sorted by name for deterministic diffs.
"""
import json


def canonical_variant(variant):
    """Map a raw variant tag to j1/j2/j4. Legacy 'direct-rom72' and anything
    unrecognised map to j2 (the baseline), so historical points stay on the
    bare J2 series."""
    v = (variant or "").lower()
    # check the cpu+cache tags before the bare j2/j4 substrings ("j4c" contains
    # "j4", "j2c" contains "j2").
    if "j2ac" in v:
        return "j2ac"
    if "j2a" in v:
        return "j2a"
    if "j2c" in v:
        return "j2c"
    if "j4c" in v:
        return "j4c"
    if "j1" in v:
        return "j1"
    if "j4" in v:
        return "j4"
    return "j2"


def convert(canon_paths):
    size, speed, pnr = [], [], []
    for path in canon_paths:
        with open(path) as f:
            doc = json.load(f)
        target, variant = doc["target"], doc.get("variant", "")
        cvar = canonical_variant(variant)
        # J2 keeps the bare name (continuous history); the others are suffixed so
        # the action keys them as distinct series and compares each against
        # itself. cpu+cache get explicit "J2+cache"/"J4+cache" display labels.
        _LABEL = {"j2": "", "j1": " [j1]", "j4": " [j4]",
                  "j2a": " [j2a]", "j2ac": " [J2A+cache]",
                  "j2c": " [J2+cache]", "j4c": " [J4+cache]"}
        suffix = _LABEL.get(cvar, " [%s]" % cvar)
        is_pnr = target.endswith("-pnr")
        for m in doc["metrics"]:
            entry = {
                "name": "%s · %s%s" % (target, m["name"], suffix),
                "unit": m["unit"],
                "value": m["value"],
                "extra": cvar,
            }
            if is_pnr:
                pnr.append(entry)                       # pnr is all smaller-is-better
            elif m["dir"] == "smaller":
                size.append(entry)
            else:
                speed.append(entry)
    size.sort(key=lambda e: e["name"])
    speed.sort(key=lambda e: e["name"])
    pnr.sort(key=lambda e: e["name"])
    return size, speed, pnr


def main(argv=None):
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("inputs", nargs="+", help="canonical metric JSON files")
    p.add_argument("--size-out", required=True)
    p.add_argument("--speed-out", required=True)
    p.add_argument("--pnr-out", required=True)
    a = p.parse_args(argv)
    size, speed, pnr = convert(a.inputs)
    for path, data in ((a.size_out, size), (a.speed_out, speed), (a.pnr_out, pnr)):
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
    print("to_gha_bench.py: %d size, %d speed, %d pnr metrics" % (len(size), len(speed), len(pnr)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
