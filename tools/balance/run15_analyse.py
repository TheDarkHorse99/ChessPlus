"""Balance run 15: run 14's arm B plus Mac's three new pawn-type pieces
(Grunt 1.5, Abatis 1, Vassal 1), the Wall keyword and the 75-move rule, as one
arm C. Reads the server's run15/C folder (tools/balance/run15_server.sh on the
branch experiment/run15) and compares with run 14's arm B (its folder on this
PC), writing the report with the success lines from the README.

    python tools/balance/run15_analyse.py --run15 <run15 folder> --run14 <run14 folder> --out balance/results/run15/report.md

Uses run14_analyse.py's helpers (and through it runs 3-13's statistics).
"""
import argparse
import os
import re
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run3_analyse as r
import run8_9_analyse as a
import run11_analyse as s
import run14_analyse as r14

NEW = {"Grunt": 1.5, "Abatis": 1.0, "Vassal": 1.0}
PAWN_TYPE_SYMBOLS = ("P", "GR", "AB", "VS")


def army_cells(army):
    """(back row, front row) as lists of piece symbols or "" per square, from army text "back/front"."""
    if army.lower() == "standard":
        army = "RNBQKBNR/PPPPPPPP"
    rows = (army.split("/") + [""])[:2]
    out = []
    for text in rows:
        cells = []
        for token in re.findall(r"\([A-Z]+\)|[A-Z]|\d", text):
            if token.isdigit():
                cells += [""] * int(token)
            else:
                cells.append(token.strip("()"))
        out.append(cells)
    return out[0], out[1]


def pool_rows(path, defs_by_symbol):
    """Per pool army: name, text, front-row pieces, front-row pawn types, each new piece's count (front, back)."""
    rows = []
    for l in open(path, encoding="utf-8"):
        if l.startswith("#") or not l.strip():
            continue
        cols = [c.strip() for c in l.split("|")]
        army, name = cols[0], cols[1]
        if name == "Standard":
            continue
        back, front = army_cells(army)
        counts = {}
        for piece in NEW:
            sym = defs_by_symbol.get(piece)
            counts[piece] = (front.count(sym), back.count(sym)) if sym else (0, 0)
        rows.append({
            "name": name, "army": army, "front": sum(1 for c in front if c), "back": sum(1 for c in back if c),
            "front_pawns": sum(1 for c in front if c in PAWN_TYPE_SYMBOLS), "new": counts,
        })
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run15", required=True)
    ap.add_argument("--run14", required=True)
    ap.add_argument("--pieces", default="data/pieces")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    pieces = r.read_pieces(args.pieces)
    defs = r14.read_defs(args.pieces)
    sym_of = {d["name"]: d["symbol"] for d in defs.values()}
    C = os.path.join(args.run15, "C")
    B = os.path.join(args.run14, "B")
    out = ["# Balance run 15: the three new pawn-type pieces (report)\n",
           "Made by `tools/balance/run15_analyse.py`. Arm C = run 14's arm B (budget 40, the 24 Oct prices, the ability "
           "rule) plus the Grunt (1.5), Abatis (1) and Vassal (1), the Wall keyword and the 75-move rule. Compared with run "
           "14's arm B throughout. Points = percentage points.\n"]
    checks = []

    # --- (1) prices and the new pieces' worth -----------------------------------------------
    repC, headC = r14.read_report(os.path.join(C, "report.txt"))
    repB, headB = r14.read_report(os.path.join(B, "report.txt"))
    out.append("## (1) Piece values: 20,000 random-army games, 8,000 nodes\n")
    for label, head in (("Run 14 B", headB), ("Run 15 C", headC)):
        if head:
            out.append("%s: %s" % (label, " / ".join(h.strip() for h in head[:2])))
    out.append("\n\"Worth\" = what one extra piece at the start is worth by game results, on the cost scale (±95%). "
               "Bold = new in run 15; * = has a special ability.\n")
    out.append("| Piece | Cost | Worth, run 14 B | Worth, run 15 C | Verdict, C | C minus B |\n|---|---|---|---|---|---|")
    order = sorted(set(repC) | set(repB), key=lambda p: -(repC.get(p) or repB.get(p))["cost"])
    for p in order:
        rb, rc = repB.get(p), repC.get(p)
        cost = (rc or rb)["cost"]
        label = ("**%s**" % p if p in NEW else p) + ("*" if p in r14.ABILITY_PIECES else "")
        diff = (rc["worth"] - rb["worth"]) if rb and rc else None
        out.append("| %s | %s | %s | %s | %s | %s |" % (
            label, r14.fmt(cost, 1), ("%s ±%s" % (r14.fmt(rb["worth"]), r14.fmt(rb["pm"]))) if rb else "-",
            ("%s ±%s" % (r14.fmt(rc["worth"]), r14.fmt(rc["pm"]))) if rc else "-", rc["verdict"] if rc else "-", r14.fmt(diff, 2, True)))
    if repC:
        off = {p: repC[p]["worth"] - repC[p]["cost"] for p in r14.REPRICED if p in repC}
        checks.append(("1. Each repriced piece within 0.5 of its cost", all(abs(d) <= 0.5 for d in off.values()) and len(off) == len(r14.REPRICED),
                       ", ".join("%s %+.2f" % (p, d) for p, d in off.items())))
        worst = sorted(((repC[p]["worth"] - repC[p]["cost"], p) for p in repC), key=lambda t: -abs(t[0]))
        checks.append(("2. No piece more than 1.0 off its cost", all(abs(d) <= 1.0 for d, _ in worst),
                       "worst: " + ", ".join("%s %+.2f" % (p, d) for d, p in worst[:4])))
        new_off = {p: (repC[p]["worth"], repC[p]["worth"] - repC[p]["cost"]) for p in NEW if p in repC}
        checks.append(("New pieces' worth (report only): starting prices Grunt 1.5, Abatis 1, Vassal 1", True,
                       "; ".join("%s worth %.2f (%+.2f)" % (p, w, d) for p, (w, d) in new_off.items()) or "none measured"))
        abil = [(p, repC[p]["worth"] - repC[p]["cost"]) for p in r14.ABILITY_PIECES if p in repC]
        checks.append(("3. Ability pieces within 1.0 of cost under the rule", all(abs(d) <= 1.0 for _, d in abil),
                       ", ".join("%s %+.2f" % (p, d) for p, d in abil)))

    # --- random armies ---------------------------------------------------------------
    rand = {}
    for label, folder in (("Run 14 B", B), ("Run 15 C", C)):
        path = os.path.join(folder, "selfplay.jsonl")
        if os.path.exists(path):
            rand[label] = a.random_armies(path)
    if rand:
        out.append("\n### White's edge in the random-army games\n")
        out.append(a.RANDOM_HEADER)
        for label, st in rand.items():
            a.write_random(out, st, label)

    # --- (2) the pool, its new pieces and front rows -------------------------------------------
    rr = {}
    pools = {}
    for label, folder in (("Run 14 B", B), ("Run 15 C", C)):
        path = os.path.join(folder, "meta_pool.txt")
        if not os.path.exists(path):
            continue
        rows = pool_rows(path, sym_of)
        pools[label] = rows
        out.append("\n## (2) %s: the all-round pool\n" % label)
        out.append("| Army | Pieces | Front-row squares filled | Pawn types in the front row | Grunts (front/back) | Abatis (front/back) | Vassals (front/back) | Cost |\n|---|---|---|---|---|---|---|---|")
        for row in rows:
            n = row["front"] + row["back"]
            out.append("| %s `%s` | %d | %d | %d | %d/%d | %d/%d | %d/%d | 40 |" % (
                row["name"], row["army"], n, row["front"], row["front_pawns"],
                row["new"]["Grunt"][0], row["new"]["Grunt"][1], row["new"]["Abatis"][0], row["new"]["Abatis"][1],
                row["new"]["Vassal"][0], row["new"]["Vassal"][1]))
        out.append("\nAverages: %.1f of 8 front-row squares filled, %.1f pawn-type pieces in the front row; armies with a Grunt %d, an Abatis %d, a Vassal %d (of %d)." % (
            statistics.mean(x["front"] for x in rows), statistics.mean(x["front_pawns"] for x in rows),
            sum(1 for x in rows if sum(x["new"]["Grunt"])), sum(1 for x in rows if sum(x["new"]["Abatis"])),
            sum(1 for x in rows if sum(x["new"]["Vassal"])), len(rows)))
        armies, ranked = a.diversity(folder, pieces)
        out.append("\n**Piece diversity:** %d piece types (not the King) in %d armies. Armies with each: %s\n"
                   % (len(ranked), armies, ", ".join("%s %d" % (pieces.get(sym, {}).get("name", sym), c) for sym, c in ranked)))
        if os.path.exists(os.path.join(folder, "pairings.txt")):
            rr[label] = a.round_robin(folder)
            a.write_rr(out, rr[label], "Round robin of %s's pool + Standard (40 games a pairing, 8,000 nodes, --random-plies 4, seeds 3000+)" % label)
            every = [g for k, i, j in [tuple(int(v) for v in l.split("|")) for l in open(os.path.join(folder, "pairings.txt")) if l.strip()]
                     for g in r.read_games(os.path.join(folder, "pairs", "p%d.jsonl" % k))]
            mean, lo, hi, _ = r.mean_range([g["result"] for g in every])
            rr[label]["lo"], rr[label]["hi"] = lo, hi
            out.append("\nWhite's score with its 95%% range: %s (%s-%s)." % (r.pct(mean), r.pct(lo), r.pct(hi)))
    if "Run 14 B" in pools and "Run 15 C" in pools:
        fb = statistics.mean(x["front"] for x in pools["Run 14 B"])
        fc = statistics.mean(x["front"] for x in pools["Run 15 C"])
        pb = statistics.mean(x["front_pawns"] for x in pools["Run 14 B"])
        pc = statistics.mean(x["front_pawns"] for x in pools["Run 15 C"])
        checks.append(("7. Front-row occupancy in the pool rises against run 14's B pool (filled squares; pawn types in the front row shown too)",
                       fc > fb + 1e-9, "filled squares %.1f -> %.1f of 8; pawn types in the front row %.1f -> %.1f" % (fb, fc, pb, pc)))
        typesB, typesC = len(a.diversity(B, pieces)[1]), len(a.diversity(C, pieces)[1])
        abil_in_C = [pieces.get(sym, {}).get("name", sym) for sym, c in a.diversity(C, pieces)[1] if pieces.get(sym, {}).get("ability")]
        checks.append(("6. Diversity: C's pool has at least as many piece types as run 14 B's (within 2) and at least 3 of the 5 ability types",
                       typesC >= typesB - 2 and len(abil_in_C) >= 3, "types B %d, C %d; ability types in C's pool: %s" % (typesB, typesC, ", ".join(abil_in_C) or "none")))
    if "Run 14 B" in rand and "Run 15 C" in rand and "Run 15 C" in rr:
        b, c = rand["Run 14 B"], rand["Run 15 C"]
        rrc = rr["Run 15 C"]
        ok = (c["white"] <= b["white"] or c["lo"] <= b["hi"]) and 0.50 <= rrc["white"] <= 0.55 and not a.big_gaps(rrc) and not a.lopsided(rrc)
        checks.append(("4. White's edge no bigger than run 14 B's in random armies, and C's round robin passes Mac's lines (50-55%, no gap over 30, no pairing at 80%+)", ok,
                       "random armies B %s (%s-%s), C %s (%s-%s); C's round robin White %s (%s-%s), biggest gap %+.1f, pairings at 80%%+: %d" % (
                           r.pct(b["white"]), r.pct(b["lo"]), r.pct(b["hi"]), r.pct(c["white"]), r.pct(c["lo"]), r.pct(c["hi"]),
                           r.pct(rrc["white"]), r.pct(rrc["lo"]), r.pct(rrc["hi"]), max(g[2] for g in rrc["gaps"] if g[1] != "standard"), len(a.lopsided(rrc)))))

    # --- (4) mirrors ------------------------------------------------------------------
    mpath = os.path.join(C, "mirror.txt")
    if os.path.exists(mpath):
        out.append("\n## (4) C's pool armies against themselves (Plusfish at 2,000,000 nodes, 8 threads)\n")
        out.append("White's first-move advantage in pawns; negative = Black ahead. Chess: +0.29 (top engines +0.20 to +0.35).\n")
        out.append("| Army | Without the ability rule | With the rule |\n|---|---|---|")
        with_rule = []
        for line in open(mpath, encoding="utf-8").read().splitlines()[1:]:
            source, name, army, without, rule = line.split("|", 4)
            x, xm = a.mirror_score(without)
            y, ym = a.mirror_score(rule)
            if y is not None:
                with_rule.append((y, name))
            f = lambda v, m: "%+.2f (%s)" % (v, m) if v is not None else m
            out.append("| %s `%s` | %s | %s |" % (name, army, f(x, xm), f(y, ym)))
        if with_rule:
            v = [x for x, _ in with_rule]
            out.append("\nWith the rule: median %+.2f; within ±0.35: %d of %d; over +1: %s; Black ahead by more than a pawn: %s (run 14 B: median +0.70, 5 of 11 over +1)"
                       % (statistics.median(v), sum(1 for x in v if -0.35 <= x <= 0.35), len(v),
                          ", ".join("%s %+.2f" % (n, x) for x, n in with_rule if x > 1) or "none",
                          ", ".join("%s %+.2f" % (n, x) for x, n in with_rule if x < -1) or "none"))

    # --- (3) colour specialists -------------------------------------------------------------
    split = os.path.join(C, "split")
    if os.path.isdir(os.path.join(split, "specialists")) and "Run 15 C" in rr:
        base = rr["Run 15 C"]
        out.append("\n## (3) Colour specialists (run 13's method on C's regrown pool)\n")
        wpath = os.path.join(split, "meta_pool_white.txt")
        bpath = os.path.join(split, "meta_pool_black.txt")
        s.pool_table(out, wpath, pieces, "White pool (judged only as White)")
        s.pool_table(out, bpath, pieces, "Black pool (judged only as Black)")
        for title, path in (("White", wpath), ("Black", bpath)):
            rows = pool_rows(path, sym_of)
            out.append("\n%s pool: %.1f of 8 front-row squares filled, %.1f pawn types in the front row; Grunts %d, Abatis %d, Vassals %d in all." % (
                title, statistics.mean(x["front"] for x in rows), statistics.mean(x["front_pawns"] for x in rows),
                sum(sum(x["new"]["Grunt"]) for x in rows), sum(sum(x["new"]["Abatis"]) for x in rows), sum(sum(x["new"]["Vassal"]) for x in rows)))
        out.append("\nPiece types, White pool: %s\n" % s.diversity_line(wpath, pieces))
        out.append("Piece types, Black pool: %s\n" % s.diversity_line(bpath, pieces))
        spec = s.grid(os.path.join(split, "specialists"))
        wvo = s.grid(os.path.join(split, "white_vs_ordinary"))
        ovb = s.grid(os.path.join(split, "ordinary_vs_black"))
        real = {k: v for k, v in spec["pairs"].items() if "Standard" not in k}
        lop = ["%s vs %s (White %s)" % (w, b, r.pct(v)) for (w, b), v in real.items() if v >= 0.8 or v <= 0.2]
        out.append("| | White's score | vs C's all-round round robin |\n|---|---|---|")
        out.append("| All-rounders as White against all-rounders as Black (C's round robin) | %s | |" % r.pct(base["white"]))
        out.append("| White specialists against all-rounders as Black | %s (%s-%s) | White gains %+.1f points |" % (r.pct(wvo["white"]), r.pct(wvo["lo"]), r.pct(wvo["hi"]), 100 * (wvo["white"] - base["white"])))
        out.append("| All-rounders as White against Black specialists | %s (%s-%s) | Black gains %+.1f points |" % (r.pct(ovb["white"]), r.pct(ovb["lo"]), r.pct(ovb["hi"]), 100 * (base["white"] - ovb["white"])))
        out.append("| White specialists against Black specialists | %s (%s-%s) | %+.1f points for White overall |" % (r.pct(spec["white"]), r.pct(spec["lo"]), r.pct(spec["hi"]), 100 * (spec["white"] - base["white"])))
        out.append("| Uneven specialist matchups (either side at 80%%+, Standard left out) | %d of %d | |" % (len(lop), len(real)))
        out.append("\nRun 14 B (same rules, without the new pieces): White specialists +16.3, Black +7.5, specialists vs specialists 70.6% (all-rounders 53.6%).")
        out.append("\nEach White army as White (all Black armies) and each Black army as Black (all White armies):\n")
        out.append("| White army | Score as White | | Black army | Score as Black |\n|---|---|---|---|---|")
        for k in range(max(len(spec["whites"]), len(spec["blacks"]))):
            wcell = ("%s | %s" % (spec["whites"][k][0], r.pct(statistics.mean(spec["by_white"][k])))) if k < len(spec["whites"]) and spec["by_white"][k] else " | "
            bcell = ("%s | %s" % (spec["blacks"][k][0], r.pct(statistics.mean(spec["by_black"][k])))) if k < len(spec["blacks"]) and spec["by_black"][k] else " | "
            out.append("| %s | | %s |" % (wcell, bcell))
        if lop:
            out.append("\nPairings at 80%%+: %s" % "; ".join(lop))

    # --- (5) move-1 tally ------------------------------------------------------------------
    tallies = {}
    for subset, word in (("random", "random armies"), ("pool", "pool games")):
        for label, folder in (("B", B), ("C", C)):
            t = r14.first_moves_tally(os.path.join(folder, "firstmoves.jsonl"), defs, subset)
            if t:
                tallies["%s, %s" % (label, word)] = t
    if tallies:
        out.append("\n## (5) White's first move, every game (B = run 14's arm B, C = run 15)\n")
        out.append("Random armies = the 20,000 balance-report games; pool games = the regrown pool's round robin and the specialist grids. "
                   "\"Hit\" = a capture, a shield break or a special ability on move 1; \"free\" = Black could not hit the mover back where it stood.\n")
        out.append("| | " + " | ".join(tallies) + " |\n|---|" + "---|" * len(tallies))
        rows = [
            ("Games", lambda t: "%d" % t["games"]),
            ("White's first move a hit", lambda t: "%s (%d)" % (r.pct(t["hits"] / t["games"]), t["hits"])),
            ("...a capture", lambda t: "%s" % r.pct(t["kinds"].get("capture", (0, 0))[0] / t["games"])),
            ("...a special ability", lambda t: "%s" % r.pct(t["ability_count"] / t["games"])),
            ("White's score after a hit / after a quiet first move", lambda t: "%s / %s" % (r.pct(t["hits_score"]), r.pct(t["quiet_score"]))),
            ("Free hits: share of hits, White's score", lambda t: "%s, %s" % (r.pct(t["free"] / t["hits"]) if t["hits"] else "-", r.pct(t["free_score"]))),
            ("Recapturable hits: share, recaptured", lambda t: "%s, %s" % (r.pct(t["recapturable"] / t["hits"]) if t["hits"] else "-", r.pct(t["recaptured"] / t["recapturable"]) if t["recapturable"] else "-")),
        ]
        for title, f in rows:
            out.append("| %s | " % title + " | ".join(f(t) for t in tallies.values()) + " |")
        for label, t in tallies.items():
            if not label.startswith("C"):
                continue
            out.append("\n### %s: by the piece that hit (move 1)\n" % label)
            out.append("| Mover | Hits | Share of hits | White's score | Free | Recaptured |\n|---|---|---|---|---|---|")
            for name, n, score, free, recap in t["by_mover"]:
                out.append("| %s | %d | %s | %s | %s | %s |" % (name, n, r.pct(n / t["hits"]), r.pct(score), r.pct(free), r.pct(recap)))
            out.append("\n**By the piece hit:**\n")
            out.append("| Target | Cost | Hit on move 1 | Share of hits | White's score |\n|---|---|---|---|---|")
            for name, n, score, val in t["by_target"]:
                out.append("| %s | %s | %d | %s | %s |" % (name, r14.fmt(val, 1), n, r.pct(n / t["hits"]), r.pct(score)))
            out.append("\n**Commonest hits (mover -> target):** " + "; ".join("%s x %s %d (White %s, free %s)" % (m, tg, n, r.pct(sc), r.pct(fr)) for m, tg, n, sc, fr in t["pairs"]))
        if "C, random armies" in tallies:
            abilities = sum(t["ability_count"] for k, t in tallies.items() if k.startswith("C,"))
            checks.append(("5. Under the rule no game starts with an ability", abilities == 0, "abilities on move 1 in C's games: %d" % abilities))

    out.append("\n## Success lines (from the README, written before the run)\n")
    checks.sort(key=lambda c: c[0])
    a.checks_md(out, checks)
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    open(args.out, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("\n".join(out[-(len(checks) + 2):]))


if __name__ == "__main__":
    main()
