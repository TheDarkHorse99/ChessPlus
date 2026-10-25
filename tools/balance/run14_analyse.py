"""Balance run 14: the 24 Oct 2026 prices (arm A: budget 40, Queen 10, Bishop
3.5, Rook 4.5, Werewolf 3.5, Parapet 2.5, Jester 3.5) and the ability rule
(arm B: arm A plus Plusfish --abilities-need-move=true). Reads the server's
run14 folder (A/ and B/, see tools/balance/run14_server.sh on the branch
experiment/run14) and writes the report with the success lines from the
README.

    python tools/balance/run14_analyse.py --run14 <run14 folder> --out balance/results/run14/report.md

Uses run3_analyse.py, run8_9_analyse.py and run11_analyse.py's helpers (the
same statistics as runs 3-13).
"""
import argparse
import glob
import json
import os
import re
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run3_analyse as r
import run8_9_analyse as a
import run11_analyse as s

REPRICED = {"Queen": 10, "Bishop": 3.5, "Rook": 4.5, "Werewolf": 3.5, "Parapet": 2.5, "Jester": 3.5}
ABILITY_PIECES = ["Archer", "Necromancer", "Ghost", "Bard", "Werewolf"]


def read_defs(folder):
    """piece id (file name) -> {"name", "value", "symbol", "ability"} from the game's piece files."""
    defs = {}
    for path in glob.glob(os.path.join(folder, "*.tres")):
        text = open(path, encoding="utf-8").read()
        main = text.split("[resource]", 1)[1]

        def field(name, default=None):
            m = re.search(r"^%s = (.+)$" % name, main, re.M)
            return m.group(1).strip().strip('"') if m else default

        defs[os.path.splitext(os.path.basename(path))[0]] = {
            "name": field("display_name"), "value": float(field("value", "0")), "symbol": field("symbol"),
            "ability": int(field("ability", "0")) != 0,
        }
    return defs


def read_report(path):
    """piece name -> {"cost", "games", "worth", "pm", "elo", "board", "verdict"} from a balance report, plus its header lines."""
    rows = {}
    header = []
    if not os.path.exists(path):
        return rows, header
    for line in open(path, encoding="utf-8", errors="replace"):
        parts = line.split()
        if len(header) < 3 and line.strip():
            header.append(line.rstrip())
        if len(parts) >= 8 and re.fullmatch(r"[\d.]+", parts[1]) and re.fullmatch(r"\d+", parts[2]) and re.fullmatch(r"-?[\d.]+", parts[3]):
            rows[parts[0]] = {
                "cost": float(parts[1]), "games": int(parts[2]), "worth": float(parts[3]),
                "pm": float(re.sub(r"[^\d.]", "", parts[4]) or "nan"), "elo": parts[5], "board": parts[6],
                "verdict": " ".join(parts[8:]),
            }
    return rows, header


def fmt(x, digits=2, sign=False):
    if x is None or x != x:
        return "-"
    return ("%+." + str(digits) + "f") % x if sign else ("%." + str(digits) + "f") % x


def first_moves_tally(path, defs, subset=None):
    """The move-1 facts of one arm (plusfish first-moves): shares by kind, by mover, by target, free hits.
    subset "random" = the random-army games only (selfplay.jsonl), "pool" = the pool games (round robin and grids)."""
    if not os.path.exists(path):
        return None
    rows = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
    rows = [x for x in rows if x["kind"] != "none"]
    if subset == "random":
        rows = [x for x in rows if x["file"].endswith("selfplay.jsonl")]
    elif subset == "pool":
        rows = [x for x in rows if not x["file"].endswith("selfplay.jsonl")]
    if not rows:
        return None
    n = len(rows)
    name = lambda pid: defs.get(pid, {}).get("name", pid) if pid else "-"
    value = lambda pid: defs.get(pid, {}).get("value", 0.0) if pid else 0.0
    kinds = {}
    for x in rows:
        kinds.setdefault(x["kind"], []).append(x)
    hits = [x for x in rows if x["kind"] in ("capture", "shield", "ability")]
    by_mover = {}
    by_target = {}
    pairs = {}
    for x in hits:
        by_mover.setdefault(x["mover"], []).append(x)
        if x["target"]:
            by_target.setdefault(x["target"], []).append(x)
            pairs.setdefault((x["mover"], x["target"]), []).append(x)
    free = [x for x in hits if x["kind"] != "ability" and x["stands"] and not x["recapturable"]]
    recapturable = [x for x in hits if x["stands"] and x["recapturable"]]
    recaptured = [x for x in recapturable if x["recaptured"]]
    gain = [value(x["target"]) - (value(x["mover"]) if not x["stands"] else 0.0) for x in hits if x["kind"] != "ability"]
    return {
        "games": n, "kinds": {k: (len(v), statistics.mean(y["result"] for y in v)) for k, v in kinds.items()},
        "hits": len(hits), "hits_score": statistics.mean(x["result"] for x in hits) if hits else float("nan"),
        "quiet_score": statistics.mean(x["result"] for x in kinds.get("quiet", [])) if kinds.get("quiet") else float("nan"),
        "checks": sum(1 for x in hits if x["check"]),
        "free": len(free), "free_score": statistics.mean(x["result"] for x in free) if free else float("nan"),
        "recapturable": len(recapturable), "recaptured": len(recaptured),
        "recap_score": statistics.mean(x["result"] for x in recapturable) if recapturable else float("nan"),
        "mean_gain": statistics.mean(gain) if gain else float("nan"),
        "by_mover": sorted(((name(k), len(v), statistics.mean(y["result"] for y in v),
                             sum(1 for y in v if y["stands"] and not y["recapturable"]) / len(v),
                             sum(1 for y in v if y["recaptured"]) / len(v)) for k, v in by_mover.items()), key=lambda t: -t[1]),
        "by_target": sorted(((name(k), len(v), statistics.mean(y["result"] for y in v), value(k)) for k, v in by_target.items()), key=lambda t: -t[1]),
        "pairs": sorted(((name(m), name(t), len(v), statistics.mean(y["result"] for y in v),
                          sum(1 for y in v if y["stands"] and not y["recapturable"]) / len(v)) for (m, t), v in pairs.items()), key=lambda t: -t[2])[:15],
        "ability": {name(k): n for k, n in ((k, sum(1 for y in v if y["kind"] == "ability")) for k, v in by_mover.items()) if n},
        "ability_count": len(kinds.get("ability", [])),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run14", required=True)
    ap.add_argument("--pieces", default="data/pieces")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    pieces = r.read_pieces(args.pieces)
    defs = read_defs(args.pieces)
    A = os.path.join(args.run14, "A")
    B = os.path.join(args.run14, "B")
    out = ["# Balance run 14: the 24 October prices and the ability rule (report)\n",
           "Made by `tools/balance/run14_analyse.py`. Arm A: budget 40 and the new prices (Queen 10, Bishop 3.5, Rook 4.5, "
           "Werewolf 3.5, Parapet 2.5, Jester 3.5). Arm B: arm A plus the ability rule (Plusfish `--abilities-need-move=true`: "
           "a special ability needs a move first; a capture or a shield break counts as a move; a Ghost captured before it "
           "moved can't Haunt). Normal rules otherwise. Points = percentage points.\n"]
    checks = []

    # --- (1) prices -------------------------------------------------------------
    repA, headA = read_report(os.path.join(A, "report.txt"))
    repB, headB = read_report(os.path.join(B, "report.txt"))
    out.append("## (1) Piece values: 20,000 random-army games per arm, 8,000 nodes\n")
    for label, head in (("A", headA), ("B", headB)):
        if head:
            out.append("Arm %s: %s" % (label, " / ".join(h.strip() for h in head[:2])))
    out.append("\n\"Worth\" = what one extra piece at the start is worth by game results, on the cost scale (±95%). "
               "Bold = repriced on 24 Oct; * = has a special ability.\n")
    out.append("| Piece | Cost | Worth, A | Verdict, A | Worth, B | Verdict, B | B minus A |\n|---|---|---|---|---|---|---|")
    order = sorted(set(repA) | set(repB), key=lambda p: -(repA.get(p) or repB.get(p))["cost"])
    for p in order:
        ra, rb = repA.get(p), repB.get(p)
        cost = (ra or rb)["cost"]
        label = ("**%s**" % p if p in REPRICED else p) + ("*" if p in ABILITY_PIECES else "")
        diff = (rb["worth"] - ra["worth"]) if ra and rb else None
        out.append("| %s | %s | %s | %s | %s | %s | %s |" % (
            label, fmt(cost, 1), ("%s ±%s" % (fmt(ra["worth"]), fmt(ra["pm"]))) if ra else "-", ra["verdict"] if ra else "-",
            ("%s ±%s" % (fmt(rb["worth"]), fmt(rb["pm"]))) if rb else "-", rb["verdict"] if rb else "-", fmt(diff, 2, True)))
    if repA:
        off = {p: repA[p]["worth"] - repA[p]["cost"] for p in REPRICED if p in repA}
        bad = ["%s %+.2f" % (p, d) for p, d in off.items() if abs(d) > 0.5]
        checks.append(("1. Each repriced piece within 0.5 of its new cost (arm A)", not bad and len(off) == len(REPRICED),
                       ", ".join("%s %+.2f" % (p, d) for p, d in off.items())))
        worst = sorted(((repA[p]["worth"] - repA[p]["cost"], p) for p in repA), key=lambda t: -abs(t[0]))
        checks.append(("2. No piece more than 1.0 off its cost (arm A)", all(abs(d) <= 1.0 for d, _ in worst),
                       "worst: " + ", ".join("%s %+.2f" % (p, d) for d, p in worst[:4])))
    if repA and repB:
        detail = []
        ok = True
        for p in ABILITY_PIECES:
            if p in repA and p in repB:
                d_cost = repB[p]["worth"] - repB[p]["cost"]
                drop = repB[p]["worth"] - repA[p]["worth"]
                detail.append("%s %s (A %s, B %s)" % (p, fmt(drop, 2, True), fmt(repA[p]["worth"]), fmt(repB[p]["worth"])))
                if abs(d_cost) > 1.0 or drop < -0.5:
                    ok = False
        checks.append(("3. Ability pieces within 1.0 of cost under the rule and none down more than 0.5 from A to B", ok, "; ".join(detail)))

    # --- random armies -----------------------------------------------------------
    rand = {}
    for label, folder in (("A", A), ("B", B)):
        path = os.path.join(folder, "selfplay.jsonl")
        if os.path.exists(path):
            rand[label] = a.random_armies(path)
    if rand:
        out.append("\n### White's edge in the random-army games\n")
        out.append(a.RANDOM_HEADER)
        for label, st in rand.items():
            a.write_random(out, st, "Arm " + label)
    # --- (2) pools and round robins --------------------------------------------------
    rr = {}
    pools = {}
    for label, folder in (("A", A), ("B", B)):
        if not os.path.exists(os.path.join(folder, "meta_pool.txt")):
            continue
        out.append("\n## (2) Arm %s: the all-round pool regrown from run 7's pool\n" % label)
        rows = a.pool_pawns(folder)
        out.append("| Army | Pieces | Pawns | ...in the front row | Cost |\n|---|---|---|---|---|")
        for name, army, pawns, front, n, cost in rows:
            out.append("| %s `%s` | %d | %d | %d | %s |" % (name, army, n, pawns, front, cost))
        armies, ranked = a.diversity(folder, pieces)
        pools[label] = (armies, ranked)
        out.append("\n**Piece diversity:** %d piece types (not the King) in %d armies. Armies with each: %s\n"
                   % (len(ranked), armies, ", ".join("%s %d" % (pieces.get(sym, {}).get("name", sym), c) for sym, c in ranked)))
        if os.path.exists(os.path.join(folder, "pairings.txt")):
            rr[label] = a.round_robin(folder)
            a.write_rr(out, rr[label], "Round robin of arm %s's pool + Standard (40 games a pairing, 8,000 nodes, --random-plies 4, seeds 3000+)" % label)
            every = [g for k, i, j in [tuple(int(v) for v in l.split("|")) for l in open(os.path.join(folder, "pairings.txt")) if l.strip()]
                     for g in r.read_games(os.path.join(folder, "pairs", "p%d.jsonl" % k))]
            mean, lo, hi, _ = r.mean_range([g["result"] for g in every])
            rr[label]["lo"], rr[label]["hi"] = lo, hi
            out.append("\nWhite's score with its 95%% range: %s (%s-%s)." % (r.pct(mean), r.pct(lo), r.pct(hi)))
    if "A" in rand and "B" in rand:
        ok = rand["B"]["white"] <= rand["A"]["white"] or rand["B"]["lo"] <= rand["A"]["hi"]
        detail = "random armies A %s (%s-%s), B %s (%s-%s)" % (r.pct(rand["A"]["white"]), r.pct(rand["A"]["lo"]), r.pct(rand["A"]["hi"]),
                                                              r.pct(rand["B"]["white"]), r.pct(rand["B"]["lo"]), r.pct(rand["B"]["hi"]))
        if "B" in rr:
            b = rr["B"]
            lines = a.verdict(None, b)
            rr_ok = 0.50 <= b["white"] <= 0.55 and not a.big_gaps(b) and not a.lopsided(b)
            detail += "; B's round robin White %s (%s-%s), biggest gap %+.1f, pairings at 80%%+: %d" % (
                r.pct(b["white"]), r.pct(b.get("lo", float("nan"))), r.pct(b.get("hi", float("nan"))),
                max(g[2] for g in b["gaps"] if g[1] != "standard"), len(a.lopsided(b)))
            ok = ok and rr_ok
        checks.append(("4. The rule doesn't widen White's edge: B's random-army score no higher than A's, and B's round robin passes Mac's lines (50-55%, no gap over 30, no pairing at 80%+)", ok, detail))
    if "A" in pools and "B" in pools:
        typesA, typesB = len(pools["A"][1]), len(pools["B"][1])
        abil_in_B = [pieces.get(sym, {}).get("name", sym) for sym, c in pools["B"][1] if pieces.get(sym, {}).get("ability")]
        ok = typesB >= typesA - 2 and len(abil_in_B) >= 3
        checks.append(("6. Diversity: B's pool has at least as many piece types as A's (within 2) and at least 3 of the 5 ability types", ok,
                       "types A %d, B %d; ability types in B's pool: %s" % (typesA, typesB, ", ".join(abil_in_B) or "none")))

    # --- (4) mirrors (B) ----------------------------------------------------------------
    mpath = os.path.join(B, "mirror.txt")
    if os.path.exists(mpath):
        out.append("\n## (4) Arm B's pool armies against themselves (Plusfish at 2,000,000 nodes, 8 threads)\n")
        out.append("White's first-move advantage in pawns; negative = Black ahead. Chess: +0.29 (top engines +0.20 to +0.35).\n")
        out.append("| Army | Without the rule | With the rule |\n|---|---|---|")
        with_rule, without_rule = [], []
        for line in open(mpath, encoding="utf-8").read().splitlines()[1:]:
            source, name, army, without, rule = line.split("|", 4)
            x, xm = a.mirror_score(without)
            y, ym = a.mirror_score(rule)
            if y is not None:
                with_rule.append((y, name))
            if x is not None:
                without_rule.append((x, name))
            f = lambda v, m: "%+.2f (%s)" % (v, m) if v is not None else m
            out.append("| %s `%s` | %s | %s |" % (name, army, f(x, xm), f(y, ym)))
        for title, vals in (("Without the rule", without_rule), ("With the rule", with_rule)):
            if vals:
                v = [x for x, _ in vals]
                out.append("\n%s: median %+.2f; within ±0.35: %d of %d; over +1: %s; Black ahead by more than a pawn: %s"
                           % (title, statistics.median(v), sum(1 for x in v if -0.35 <= x <= 0.35), len(v),
                              ", ".join("%s %+.2f" % (n, x) for x, n in vals if x > 1) or "none",
                              ", ".join("%s %+.2f" % (n, x) for x, n in vals if x < -1) or "none"))

    # --- (3) colour specialists (B) --------------------------------------------------
    split = os.path.join(B, "split")
    if os.path.isdir(os.path.join(split, "specialists")) and "B" in rr:
        base = rr["B"]
        out.append("\n## (3) Arm B: colour specialists (run 13's method on B's regrown pool)\n")
        out.append("A White army is judged only as White against B's all-round pool + Standard playing Black, frozen; a Black "
                   "army only as Black against them playing White (`meta --split-colours --fixed-opponent`). All games below "
                   "have fixed colours, 40 games a pairing, 8,000 nodes, `--random-plies 4`.\n")
        wpath = os.path.join(split, "meta_pool_white.txt")
        bpath = os.path.join(split, "meta_pool_black.txt")
        s.pool_table(out, wpath, pieces, "White pool (judged only as White)")
        s.pool_table(out, bpath, pieces, "Black pool (judged only as Black)")
        out.append("\nPiece types, White pool: %s\n" % s.diversity_line(wpath, pieces))
        out.append("Piece types, Black pool: %s\n" % s.diversity_line(bpath, pieces))
        spec = s.grid(os.path.join(split, "specialists"))
        wvo = s.grid(os.path.join(split, "white_vs_ordinary"))
        ovb = s.grid(os.path.join(split, "ordinary_vs_black"))
        real = {k: v for k, v in spec["pairs"].items() if "Standard" not in k}
        lop = ["%s vs %s (White %s)" % (w, b, r.pct(v)) for (w, b), v in real.items() if v >= 0.8 or v <= 0.2]
        out.append("| | White's score | vs B's all-round round robin |\n|---|---|---|")
        out.append("| All-rounders as White against all-rounders as Black (B's round robin) | %s | |" % r.pct(base["white"]))
        out.append("| White specialists against all-rounders as Black | %s (%s-%s) | White gains %+.1f points |" % (r.pct(wvo["white"]), r.pct(wvo["lo"]), r.pct(wvo["hi"]), 100 * (wvo["white"] - base["white"])))
        out.append("| All-rounders as White against Black specialists | %s (%s-%s) | Black gains %+.1f points |" % (r.pct(ovb["white"]), r.pct(ovb["lo"]), r.pct(ovb["hi"]), 100 * (base["white"] - ovb["white"])))
        out.append("| White specialists against Black specialists | %s (%s-%s) | %+.1f points for White overall |" % (r.pct(spec["white"]), r.pct(spec["lo"]), r.pct(spec["hi"]), 100 * (spec["white"] - base["white"])))
        out.append("| Uneven specialist matchups (either side at 80%%+, Standard left out) | %d of %d | |" % (len(lop), len(real)))
        out.append("\nRun 13 (normal rules, old prices, no ability rule): White specialists +11.0, Black specialists +13.5, specialists vs specialists 56.7% (all-rounders 59.4%).")
        out.append("\nEach White army as White (all Black armies) and each Black army as Black (all White armies):\n")
        out.append("| White army | Score as White | | Black army | Score as Black |\n|---|---|---|---|---|")
        for k in range(max(len(spec["whites"]), len(spec["blacks"]))):
            wcell = ("%s | %s" % (spec["whites"][k][0], r.pct(statistics.mean(spec["by_white"][k])))) if k < len(spec["whites"]) and spec["by_white"][k] else " | "
            bcell = ("%s | %s" % (spec["blacks"][k][0], r.pct(statistics.mean(spec["by_black"][k])))) if k < len(spec["blacks"]) and spec["by_black"][k] else " | "
            out.append("| %s | | %s |" % (wcell, bcell))
        if lop:
            out.append("\nPairings at 80%%+: %s" % "; ".join(lop))

    # --- (5) move-1 tally -------------------------------------------------------------
    tallies = {}
    for subset, word in (("random", "random armies"), ("pool", "pool games")):
        for label, folder in (("A", A), ("B", B)):
            t = first_moves_tally(os.path.join(folder, "firstmoves.jsonl"), defs, subset)
            if t:
                tallies["%s, %s" % (label, word)] = t
    if tallies:
        out.append("\n## (5) White's first move, every game of each arm\n")
        out.append("Random armies = the 20,000 balance-report games of the arm; pool games = its regrown pool's round robin "
                   "and, for B, the specialist grids (strong armies, so far more first-move contact). "
                   "\"Hit\" = a capture, a shield break or a special ability on move 1. \"Free\" = a capture or shield break "
                   "where Black could not capture (or break the shield of) the mover where it stood afterwards; "
                   "\"recaptured\" = Black's reply did hit it. White's score = points per game in those games.\n")
        out.append("| | " + " | ".join(tallies) + " |\n|---|" + "---|" * len(tallies))
        rows = [
            ("Games", lambda t: "%d" % t["games"]),
            ("White's first move a hit", lambda t: "%s (%d)" % (r.pct(t["hits"] / t["games"]), t["hits"])),
            ("...a capture", lambda t: "%s" % r.pct(t["kinds"].get("capture", (0, 0))[0] / t["games"])),
            ("...a shield break", lambda t: "%s" % r.pct(t["kinds"].get("shield", (0, 0))[0] / t["games"])),
            ("...a special ability", lambda t: "%s (%d: %s)" % (r.pct(t["ability_count"] / t["games"]), t["ability_count"], ", ".join("%s %d" % kv for kv in t["ability"].items()) or "-")),
            ("...giving check", lambda t: "%s of hits" % r.pct(t["checks"] / t["hits"]) if t["hits"] else "-"),
            ("White's score after a first-move hit", lambda t: r.pct(t["hits_score"])),
            ("White's score after a quiet first move", lambda t: r.pct(t["quiet_score"])),
            ("Free hits (not recapturable)", lambda t: "%s of hits, White scores %s" % (r.pct(t["free"] / t["hits"]) if t["hits"] else "-", r.pct(t["free_score"]))),
            ("Recapturable hits", lambda t: "%s of hits, recaptured %s of those, White scores %s" % (r.pct(t["recapturable"] / t["hits"]) if t["hits"] else "-", r.pct(t["recaptured"] / t["recapturable"]) if t["recapturable"] else "-", r.pct(t["recap_score"]))),
            ("Mean material taken on move 1 (points, minus a Ram that died)", lambda t: fmt(t["mean_gain"])),
        ]
        for title, f in rows:
            out.append("| %s | " % title + " | ".join(f(t) for t in tallies.values()) + " |")
        for label, t in tallies.items():
            out.append("\n### %s: by the piece that hit (move 1)\n" % label)
            out.append("| Mover | Hits | Share of hits | White's score | Free | Recaptured |\n|---|---|---|---|---|---|")
            for name, n, score, free, recap in t["by_mover"]:
                out.append("| %s | %d | %s | %s | %s | %s |" % (name, n, r.pct(n / t["hits"]), r.pct(score), r.pct(free), r.pct(recap)))
            out.append("\n**By the piece hit:**\n")
            out.append("| Target | Cost | Hit on move 1 | Share of hits | White's score |\n|---|---|---|---|---|")
            for name, n, score, val in t["by_target"]:
                out.append("| %s | %s | %d | %s | %s |" % (name, fmt(val, 1), n, r.pct(n / t["hits"]), r.pct(score)))
            out.append("\n**Commonest hits (mover -> target):** " + "; ".join("%s x %s %d (White %s, free %s)" % (m, tg, n, r.pct(sc), r.pct(fr)) for m, tg, n, sc, fr in t["pairs"]))
        if "A, random armies" in tallies and "B, random armies" in tallies:
            ta, tb = tallies["A, random armies"], tallies["B, random armies"]
            capA = ta["kinds"].get("capture", (0, 0))[0] / ta["games"]
            capB = tb["kinds"].get("capture", (0, 0))[0] / tb["games"]
            b_all = [t for k, t in tallies.items() if k.startswith("B,")]
            abilities = sum(t["ability_count"] for t in b_all)
            checks.append(("5. Under the rule no game starts with an ability, and White's first-move capture share (random armies) is no higher than A's",
                           abilities == 0 and capB <= capA + 0.005,
                           "abilities on move 1 in B's %d games: %d; first-move captures in random armies A %s, B %s" % (
                               sum(t["games"] for t in b_all), abilities, r.pct(capA), r.pct(capB))))

    # --- success test ---------------------------------------------------------------
    out.append("\n## Success lines (from the README, written before the run)\n")
    checks.sort(key=lambda c: c[0])
    a.checks_md(out, checks)
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    open(args.out, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("\n".join(out[-(len(checks) + 2):]))


if __name__ == "__main__":
    main()
