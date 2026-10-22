"""Balance run 5 (the front-row rule): compares random armies that follow it
with run 2's random armies (same seed and settings), and each army against
itself.

    python tools/balance/run5_analyse.py --run5 <run5 folder> \
        --run2-8k <run2 8k games.jsonl> --out balance/results/run5/report.md

Uses run3_analyse.py's helpers (same statistics).
"""
import argparse
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run3_analyse as r

CHESS_EDGE = 0.35


def first_move_capture(g):
    moves = g["moves"].split()
    return bool(moves) and any(mark in moves[0] for mark in ("x", "!", "~", "@"))


def describe(games):
    results = [g["result"] for g in games]
    mean, lo, hi, _ = r.mean_range(results)
    pairs, _ = r.swapped_pairs(games)
    k = sum(r.white_won_both(a, b) for a, b in pairs)
    plo, phi = r.wilson(k, len(pairs))
    return {
        "games": "%d" % len(games),
        "white": "%s (%s-%s)" % (r.pct(mean), r.pct(lo), r.pct(hi)),
        "draws": r.pct(sum(1 for x in results if x == 0.5) / len(results)),
        "both": "%s (%s-%s), %d pairs" % (r.pct(k / len(pairs)), r.pct(plo), r.pct(phi), len(pairs)),
        "first": r.pct(sum(first_move_capture(g) for g in games) / len(games)),
        "plies": "%.0f" % (sum(g["plies"] for g in games) / len(games)),
    }


def score(text):
    """Plusfish's "eval +0.42" -> 0.42; a mate for White -> +99."""
    value = text.split("eval")[1].split()[0]
    if value.startswith("#"):
        return 99.0 if not value.startswith("#-") else -99.0
    return float(value)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run5", required=True)
    ap.add_argument("--run2-8k", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    out = ["# Balance run 5: the front-row rule (report)\n",
           "Made by `tools/balance/run5_analyse.py`. \"Run 2\" = random armies without the rule; "
           "\"run 5\" = random armies that follow it, same seed and settings (20,000 self-play games, "
           "8,000 nodes per move, 4 random opening plies). Points = percentage points.\n"]
    before = describe(r.read_games(args.run2_8k))
    after = describe(r.read_games(os.path.join(args.run5, "selfplay_8k.jsonl")))
    out.append("## Random-army games\n")
    out.append("| | Run 2 (no rule) | Run 5 (front-row rule) |\n|---|---|---|")
    for key, label in (("games", "Games"), ("white", "White's score (95%)"), ("draws", "Draws"),
                       ("both", "White won both games of a swapped pair (chess benchmark 23%)"),
                       ("first", "Games where White's first move captures or uses an ability"),
                       ("plies", "Mean game length (plies)")):
        out.append("| %s | %s | %s |" % (label, before[key], after[key]))
    log = open(os.path.join(args.run5, "logs", "selfplay_8k.txt"), encoding="utf-8").read()
    passed = [line for line in log.splitlines() if line.startswith("front-row rule:")]
    if passed:
        out.append("\nHow many of Plusfish's random armies followed the rule: %s." % passed[-1].split(": ", 1)[1])

    out.append("\n## Each army against itself (Plusfish at 2,000,000 nodes, 8 threads)\n")
    out.append("White's first-move advantage in pawns. Chess: +0.29 (top engines +0.20 to +0.35). "
               "The first 20 different armies from each set of games.\n")
    rows = [line.split("|") for line in open(os.path.join(args.run5, "mirror.txt"), encoding="utf-8").read().splitlines()[1:] if line.strip()]
    out.append("| | Armies | Median | Mean | Within +0.35 | Over +1.00 | Highest |\n|---|---|---|---|---|---|---|")
    for kind, label in (("rule", "Front-row rule"), ("no rule", "No rule (run 2)")):
        values = [score(res) for k, army, res in rows if k == kind and "eval" in res]
        if not values:
            continue
        capped = [min(v, 9.0) for v in values]
        out.append("| %s | %d | %+.2f | %+.2f | %d | %d | %s |"
                   % (label, len(values), statistics.median(values), statistics.mean(capped),
                      sum(1 for v in values if v <= CHESS_EDGE), sum(1 for v in values if v > 1.0),
                      "mate" if max(values) >= 99 else "%+.2f" % max(values)))
    out.append("\n(Mean with mates counted as +9.)\n")
    out.append("| Set | Army | White's advantage | Plusfish's first move |\n|---|---|---|---|")
    for kind, army, res in rows:
        if "eval" not in res:
            continue
        move = res.split("Best move:")[1].split("(")[0].strip()
        out.append("| %s | `%s` | %s | %s |" % (kind, army, res.split("eval")[1].split()[0], move))
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print("\n".join(out))


if __name__ == "__main__":
    main()
