#!/usr/bin/env python3
"""Edge-detect when a PR first brings J1 within the iCE40 up5k budget, and render
the milestone PR comment. Pure functions (testable) + a thin CLI the workflow
calls. Report-only: this never gates CI, it only decides whether to post a
one-time celebratory comment.

Fire iff the current build FITS (and P&R completed) AND the prior master state
did NOT fit — so it announces the crossing once, and re-announces only if J1
regresses over budget and later re-crosses.
"""
import json

UP5K_LUT4 = 5280   # ICESTORM_LC capacity (the "LUT4" budget)
UP5K_EBR = 30      # ICESTORM_RAM, 4 Kb each
UP5K_DSP = 8       # ICESTORM_DSP, 16x16 MAC
MARKER = "<!-- ice40-up5k-fit-milestone -->"


def _vals_from_metrics(metrics):
    """canonical metric list -> {SB_LUT4,EBR,SB_MAC16,Fmax} (present keys only)."""
    out = {}
    for m in metrics:
        n = m.get("name")
        if n == "cpu/SB_LUT4":
            out["SB_LUT4"] = m["value"]
        elif n == "cpu/EBR":
            out["EBR"] = m["value"]
        elif n == "cpu/SB_MAC16":
            out["SB_MAC16"] = m["value"]
        elif n == "cpu/Fmax (representative)":
            out["Fmax"] = m["value"]
    return out


def within_budget(vals):
    """True iff all three budget figures are present AND within the up5k limits."""
    if not all(k in vals for k in ("SB_LUT4", "EBR", "SB_MAC16")):
        return False
    return (vals["SB_LUT4"] < UP5K_LUT4
            and vals["EBR"] <= UP5K_EBR
            and vals["SB_MAC16"] <= UP5K_DSP)


def history_latest_j1(history):
    """github-action-benchmark history dict -> {SB_LUT4,EBR,SB_MAC16,Fmax} for the
    newest J1 iCE40 run, or {} if none. Benches are named
    'ice40-up5k · cpu/SB_LUT4 [j1]' (the '[j1]' suffix is added by
    to_gha_bench.py)."""
    runs = []
    for suite in (history.get("entries") or {}).values():
        runs.extend(suite)
    runs.sort(key=lambda r: r.get("date", 0))
    out = {}
    for run in runs:  # later runs overwrite earlier -> ends on the newest J1 point
        for b in run.get("benches", []):
            name = b.get("name", "")
            if not (name.startswith("ice40-up5k · ") and name.endswith("[j1]")):
                continue
            if "cpu/SB_LUT4" in name:
                out["SB_LUT4"] = b["value"]
            elif "cpu/EBR" in name:
                out["EBR"] = b["value"]
            elif "cpu/SB_MAC16" in name:
                out["SB_MAC16"] = b["value"]
            elif "Fmax (representative)" in name:
                out["Fmax"] = b["value"]
    return out


def decide(cur_vals, pnr_ok, prev_vals):
    """Edge trigger: fits now (and P&R completed) and did not fit before."""
    return bool(pnr_ok) and within_budget(cur_vals) and not within_budget(prev_vals)


def render(cur_vals, prev_vals, dashboard_url=""):
    def delta(k):
        if k in prev_vals:
            return " (was %s, %+d)" % (prev_vals[k], cur_vals[k] - prev_vals[k])
        return ""
    lines = [
        MARKER,
        "## \U0001F389 J1 now fits the iCE40 UltraPlus 5K (up5k)!",
        "",
        "This PR brings the **J1** core within the up5k budget — it places & "
        "routes on the `cpu_timing_top` harness via `nextpnr-ice40`.",
        "",
        "| Resource | This PR | up5k budget |",
        "|---|---|---|",
        "| Logic cells (SB_LUT4) | **%d**%s | %d |"
        % (cur_vals["SB_LUT4"], delta("SB_LUT4"), UP5K_LUT4),
        "| Block RAM (EBR) | %d%s | %d |"
        % (cur_vals["EBR"], delta("EBR"), UP5K_EBR),
        "| DSP (SB_MAC16) | %d%s | %d |"
        % (cur_vals["SB_MAC16"], delta("SB_MAC16"), UP5K_DSP),
    ]
    if "Fmax" in cur_vals:
        lines.append("| Representative Fmax | %s MHz | (reported) |" % cur_vals["Fmax"])
    lines += ["", "_Report-only milestone; no hard fit gate._"]
    if dashboard_url:
        lines.append("")
        lines.append("[Synthesis dashboard](%s)" % dashboard_url)
    return "\n".join(lines) + "\n"


def main(argv=None):
    import argparse
    p = argparse.ArgumentParser(description="iCE40 up5k fit milestone decider")
    p.add_argument("--current", required=True, help="canonical ice40-up5k metric JSON")
    p.add_argument("--history", help="bootstrapped size-suite benchmark-data.json")
    p.add_argument("--pnr-ok", action="store_true", help="nextpnr-ice40 P&R completed")
    p.add_argument("--dashboard-url", default="")
    p.add_argument("--out", default="ice40_milestone.md", help="comment body output")
    a = p.parse_args(argv)

    with open(a.current) as f:
        cur = _vals_from_metrics(json.load(f).get("metrics", []))
    prev = {}
    if a.history:
        try:
            with open(a.history) as f:
                prev = history_latest_j1(json.load(f))
        except (OSError, ValueError):
            prev = {}

    fire = decide(cur, a.pnr_ok, prev)
    if fire:
        with open(a.out, "w") as f:
            f.write(render(cur, prev, a.dashboard_url))
    print("fire=%s" % ("true" if fire else "false"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
