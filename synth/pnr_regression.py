#!/usr/bin/env python3
"""Detect post-route (-pnr) regressions in a github-action-benchmark history.
Pure compare: all pnr metrics are smaller-is-better, so a metric regresses when
cur/prev exceeds the threshold. Used by the daily synth-asic-pnr CI to file a
rolling GitHub issue."""
import json


def find_regressions(history, threshold=1.10):
    out = []
    for _suite, entries in sorted((history or {}).get("entries", {}).items()):
        if len(entries) < 2:
            continue
        cur, prev = entries[-1], entries[-2]
        prev_by = {b["name"]: b for b in prev.get("benches", [])}
        for b in cur.get("benches", []):
            p = prev_by.get(b["name"])
            if not p or not p.get("value"):
                continue
            ratio = b["value"] / p["value"]
            if ratio > threshold:
                out.append({"name": b["name"], "unit": b.get("unit", ""),
                            "prev": p["value"], "cur": b["value"],
                            "ratio": ratio,
                            "commit": cur.get("commit", {}).get("id", "")})
    return out


def to_markdown(regs):
    if not regs:
        return ""
    lines = ["The daily ASIC P&R run detected post-route regression(s) over the 110% threshold:", ""]
    lines.append("| metric | prev | current | change |")
    lines.append("|---|---|---|---|")
    for r in regs:
        lines.append("| `%s` | %g %s | %g %s | +%.1f%% |" % (
            r["name"], r["prev"], r["unit"], r["cur"], r["unit"], (r["ratio"] - 1) * 100))
    return "\n".join(lines) + "\n"


def main(argv=None):
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("history")
    p.add_argument("--out", required=True)
    p.add_argument("--threshold", type=float, default=1.10)
    a = p.parse_args(argv)
    try:
        with open(a.history) as f:
            hist = json.load(f)
    except (OSError, ValueError):
        hist = {}
    regs = find_regressions(hist, a.threshold)
    with open(a.out, "w") as f:
        f.write(to_markdown(regs))
    print("regressions=%d" % len(regs))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
