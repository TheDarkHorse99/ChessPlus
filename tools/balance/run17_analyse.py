"""Balance run 17: the Vampire and Wizard repriced (Mac, 26 Oct 2026). Reads
the server's run17 folder (A/report.txt at today's prices, B/prices.txt,
B/report.txt and B/meta/ at the new prices; tools/balance/run17_server.sh on
the branch experiment/meta-share) and run 16's folder for the comparison, and
writes the report with the success line from the README.

    python tools/balance/run17_analyse.py --run17 <run17 folder> --run16 <run16 folder> --out balance/results/run17/report.md

Uses run14_analyse.py (report reading) and run16_analyse.py (armies, archetypes).
"""
import argparse
import glob
import os
import re
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run3_analyse as r
import run14_analyse as r14
import run16_analyse as r16

WATCH = ["Vampire", "Wizard", "Queen", "Jester", "Vassal", "Grunt", "Abatis"]


def load_population(base, by_symbol):
    """All armies of a meta-share folder (run16_server.sh layout), by population."""
    armies = []
    seeds = sorted(int(re.search(r"pool_(\d+)\.txt", p).group(1)) for p in glob.glob(os.path.join(base, "all", "pool_*.txt")))
    for s in seeds:
        for name, text in r16.read_pool(os.path.join(base, "all", "pool_%d.txt" % s), "S%d " % s):
            armies.append(r16.Army(name, text, "all-round", by_symbol))
        for name, text in r16.read_pool(os.path.join(base, "split", "pool_%d_white.txt" % s), "S%d " % s):
            armies.append(r16.Army(name, text, "White", by_symbol))
        for name, text in r16.read_pool(os.path.join(base, "split", "pool_%d_black.txt" % s), "S%d " % s):
            armies.append(r16.Army(name, text, "Black", by_symbol))
    return armies


def piece_share(armies, sym):
    have = [a.counts[sym] for a in armies if sym in a.counts]
    return (len(have) / len(armies) if armies else float("nan")), (statistics.mean(have) if have else 0.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run17", required=True)
    ap.add_argument("--run16", required=True)
    ap.add_argument("--pieces", default="data/pieces")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    defs = r14.read_defs(args.pieces)
    by_symbol = {d["symbol"]: d for d in defs.values()}
    sym_of = {d["name"]: d["symbol"] for d in defs.values()}
    A = os.path.join(args.run17, "A")
    B = os.path.join(args.run17, "B")
    prices_path = os.path.join(B, "prices.txt")
    new_prices = open(prices_path, encoding="utf-8").read().strip() if os.path.exists(prices_path) else "(not run)"
    checks = []
    out = ["# Balance run 17: the Vampire and Wizard repriced (report)\n",
           "Made by `tools/balance/run17_analyse.py`. A = today's prices; B = %s (the Vampire's price picked from A's measured worth, Mac: 7 or 7.5). "
           "Main's Plusfish (Nicholas's PR #28). 20,000 random-army games at 8,000 nodes for each report; run 16's meta-share method for the meta.\n" % new_prices]

    # --- the reports ---------------------------------------------------------------------
    repA, headA = r14.read_report(os.path.join(A, "report.txt"))
    repB, headB = r14.read_report(os.path.join(B, "report.txt"))
    out.append("## Piece values\n")
    for label, head in (("A, today's prices", headA), ("B, " + new_prices, headB)):
        if head:
            out.append("%s: %s" % (label, " / ".join(h.strip() for h in head[:2])))
    out.append("\n\"Worth\" = what one extra piece at the start is worth by game results, on the cost scale (±95%). The pieces Mac asked about first.\n")
    out.append("| Piece | Cost A | Worth A | Verdict A | Cost B | Worth B | Verdict B |\n|---|---|---|---|---|---|---|")
    rest = sorted((p for p in set(repA) | set(repB) if p not in WATCH), key=lambda p: -(repA.get(p) or repB.get(p))["cost"])
    for p in WATCH + rest:
        ra, rb = repA.get(p), repB.get(p)
        if not ra and not rb:
            continue
        label = "**%s**" % p if p in WATCH else p
        out.append("| %s | %s | %s | %s | %s | %s | %s |" % (
            label, r14.fmt(ra["cost"], 1) if ra else "-", ("%s ±%s" % (r14.fmt(ra["worth"]), r14.fmt(ra["pm"]))) if ra else "-", ra["verdict"] if ra else "-",
            r14.fmt(rb["cost"], 1) if rb else "-", ("%s ±%s" % (r14.fmt(rb["worth"]), r14.fmt(rb["pm"]))) if rb else "-", rb["verdict"] if rb else "-"))
    for label, folder in (("A", A), ("B", B)):
        path = os.path.join(folder, "selfplay.jsonl")
        if os.path.exists(path):
            st = r16_random(path)
            out.append("\n%s: White %s (%s-%s) in the random-army games, %s draws." % (label, r.pct(st[0]), r.pct(st[1]), r.pct(st[2]), r.pct(st[3])))

    # --- the meta at the new prices against run 16 -----------------------------------------
    meta17 = os.path.join(B, "meta")
    if os.path.isdir(os.path.join(meta17, "all")):
        a16 = load_population(args.run16, by_symbol)
        a17 = load_population(meta17, by_symbol)
        pops = lambda armies: {p: [a for a in armies if a.population == p] for p in ("all-round", "White", "Black")}
        p16, p17 = pops(a16), pops(a17)
        out.append("\n## The meta at the new prices, against run 16's\n")
        out.append("Share of armies with the piece (mean number when they do). Run 16 = today's prices; run 17 = %s.\n" % new_prices)
        out.append("| Piece | All-round 16 | All-round 17 | White 16 | White 17 | Black 16 | Black 17 |\n|---|---|---|---|---|---|---|")
        syms = sorted({s for a in a16 + a17 for s in a.counts}, key=lambda s: -by_symbol.get(s, {}).get("value", 0.0))
        for s in syms:
            cells = []
            for pop in ("all-round", "White", "Black"):
                for P in (p16, p17):
                    share, mean = piece_share(P[pop], s)
                    cells.append("%.0f%% (x%.1f)" % (100 * share, mean) if share > 0 else "-")
            name = by_symbol.get(s, {}).get("name", s)
            out.append("| %s | %s |" % ("**%s**" % name if name in WATCH else name, " | ".join(cells)))
        vamp = sym_of.get("Vampire", "V")
        share_all, mean_all = piece_share(p17["all-round"], vamp)
        share16, _ = piece_share(p16["all-round"], vamp)
        checks.append(("Vampire in under 60%% of the all-round armies (run 16: %s)" % r.pct(share16), share_all < 0.60,
                       "%s of %d all-rounders, %.1f each; White specialists %s, Black %s" % (
                           r.pct(share_all), len(p17["all-round"]), mean_all, r.pct(piece_share(p17["White"], vamp)[0]), r.pct(piece_share(p17["Black"], vamp)[0]))))
        # Archetypes of both runs clustered together, so the same archetype can be compared.
        for title, thr in (("Families (55% of points in common)", 0.55), ("Archetypes (70%)", 0.70)):
            both = a16 + a17
            for a in both:
                a.archetype = None
            archetypes = r16.cluster(both, thr * r16.BUDGET, by_symbol)
            def sh(arch, armies_pop):
                n = len(armies_pop)
                ids = {id(x) for x in armies_pop}
                return 100.0 * sum(1 for j in arch["members"] if id(both[j]) in ids) / n if n else 0.0
            archetypes.sort(key=lambda a: -(sum(sh(a, p16[p]) + sh(a, p17[p]) for p in ("all-round", "White", "Black"))))
            out.append("\n### %s: run 16 -> run 17\n" % title)
            out.append("| Archetype | All-round 16 -> 17 | White 16 -> 17 | Black 16 -> 17 | Example (run 17 if any) |\n|---|---|---|---|---|")
            shown = 0
            for arch in archetypes:
                if len(arch["members"]) < 2:
                    continue
                ex = next((both[j] for j in arch["members"] if both[j] in a17), both[arch["centre"]])
                out.append("| **%s** | %.0f%% -> %.0f%% | %.0f%% -> %.0f%% | %.0f%% -> %.0f%% | %s `%s` |" % (
                    arch["name"], sh(arch, p16["all-round"]), sh(arch, p17["all-round"]), sh(arch, p16["White"]), sh(arch, p17["White"]),
                    sh(arch, p16["Black"]), sh(arch, p17["Black"]), ex.name, ex.text))
                shown += 1
                if shown >= 12:
                    break
            singles = sum(1 for a in archetypes if len(a["members"]) == 1)
            out.append("\n%d archetypes over both runs' %d armies, %d of them single armies." % (len(archetypes), len(both), singles))
        avb = r16.grid_scores(os.path.join(meta17, "allround_vs_black"))
        wva = r16.grid_scores(os.path.join(meta17, "white_vs_allround"))
        if avb and wva:
            m1 = r.mean_range(avb["every"])[0]
            m2 = r.mean_range(wva["every"])[0]
            holds = 0
            for i, (name, text) in enumerate(avb["whites"]):
                w = statistics.mean(avb["by_white"][i]) if avb["by_white"][i] else 0
                j = next((j for j, (n2, _) in enumerate(wva["blacks"]) if n2 == name), None)
                b = 1 - statistics.mean(wva["by_black"][j]) if j is not None and wva["by_black"][j] else 0
                holds += w >= 0.5 and b >= 0.5
            out.append("\nAll-rounders against the specialists at the new prices: %s as White against the Black specialists, %s as Black against the White ones (run 16: 43.0%% / 38.0%%); %d of %d all-rounders hold 50%%+ both ways (run 16: 3 of 40)."
                       % (r.pct(m1), r.pct(1 - m2), holds, len(avb["whites"])))
    out.append("\n## Success line (from the README, written before the run)\n")
    for name, ok, detail in checks:
        out.append("- %s: **%s** (%s)" % (name, "yes" if ok else "no", detail))
    if not checks:
        out.append("- (the meta part hasn't run)")
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    open(args.out, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("\n".join(out[-4:]))


def r16_random(path):
    games = r.read_games(path)
    mean, lo, hi, _ = r.mean_range([g["result"] for g in games])
    return mean, lo, hi, sum(1 for g in games if g["result"] == 0.5) / len(games)


if __name__ == "__main__":
    main()
