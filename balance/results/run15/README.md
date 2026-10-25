# Balance run 15: the three new pawn-type pieces (AWS sims server, 25-26 October 2026)

Mac's three pawn-type pieces of 25 Oct 2026, measured straight after run 14.
All promote, any number per army, captures as moves, Pawn type (so they take
part in en passant and reset the 50-move clock):

| Piece | Symbol | Start price | Moves | Keyword |
|---|---|---|---|---|
| **Grunt** | GR | 1.5 | 1 forward; 2 forward on its first move (the double step may capture, Mac). Captures straight ahead, so it can be taken en passant but never takes en passant. | Shield (helmeted; bare-headed once the shield breaks) |
| **Abatis** | AB | 1 | 1 forward or 1 back; 2 forward on its first move (may capture) | **Wall** (new keyword, the Parapet's old rule: the opponent's pieces can't jump over it, their Knights count as 2 straight then 1, no screen for their Cannons; own side's jumps unaffected) |
| **Vassal** | VS | 1 | 1 forward or 1 sideways; takes en passant sideways onto the skipped square | - |

Also new in the game since run 14 and in this run: the **75-move rule** (150
plies with no change to the pieces on the board is a draw, alongside the
50-move rule; pawn moves don't reset it).

**Arm C** = run 14's arm B (budget 40, the 24 Oct prices, the ability rule
`--abilities-need-move=true`) plus the three pieces at their start prices.
Branch `experiment/run15` (run 14's engine + main's rules: Plusfish reads the
new pieces' moves from their files, the Wall keyword from the keyword bit, and
has the 75-move rule). Compared with run 14's arm B throughout.

## Success lines (written before the run)

Run 14's lines, on arm C against run 14's B:

1. Each repriced piece (Queen 10, Bishop 3.5, Rook 4.5, Werewolf 3.5, Parapet
   2.5, Jester 3.5) within **0.5** of its cost.
2. No piece more than **1.0** off its cost (the new pieces included: their
   start prices are guesses, so this is the line most likely to fail).
3. The five ability pieces within **1.0** of cost.
4. White's edge no bigger than run 14 B's in random armies (C's 95% range
   overlaps or sits below B's), and C's regrown-pool round robin passes Mac's
   standing lines: White 50-55%, no gap over 30 points, no pairing at 80%+.
5. No game starts with a special ability.
6. Diversity: C's pool uses at least as many piece types as B's (within 2)
   and at least 3 of the 5 ability types.

New for run 15:

7. **Front-row occupancy in the pool rises against run 14's B pool.** Measured
   as filled front-row squares per army (B: 7.3 of 8, A: 7.7) and, because
   that is already near the ceiling, also as pawn-type pieces in the front row
   (B: 0.3 per army). The line is on filled squares, as Mac wrote it; the
   pawn-type count is the number to read if it can't rise.

Report only: each new piece's worth; how many of each the pool armies take
and how many sit in the front row; the move-1 tally; the colour specialists
and mirror matches (run 14's parts 3 and 4).

## Before the run: does Plusfish agree with the game?

`plusfish perft-suite`, and traced games from the game's own engine leaning
towards the three new pieces, the Parapet (Wall from the keyword now) and the
ability pieces, checked with `trace-check --abilities-need-move=true`: must be
0 mismatches. Results below.

## Parts and settings

The same as run 14's arm B (`tools/balance/run15_server.sh` on the branch):

| Part | What | Settings |
|---|---|---|
| (1) | balance report (`C/report.txt`, `.html`) | `selfplay --games 20000 --nodes 8000 --seed 101` (budgets 34-40), `values` |
| (2) | the all-round pool regrown from run 14's B pool (`meta_pool.txt`, `meta.log`), then run 10's colour test on it | `meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1`; round robin of the pool + Standard, 40 games a pairing, 8,000 nodes, `--random-plies 4`, seeds 3000+ |
| (3) | run 13's colour specialists from C's regrown pool (`split/`) | `meta --split-colours --fixed-opponent`; three grids, 40 games a pairing, colours fixed, seeds 4000+/5000+/6000+ |
| (4) | each regrown-pool army against itself (`mirror.txt`) | `plusfish analyse`, 2,000,000 nodes, 8 threads, with the ability rule and without |
| (5) | move-1 tally over every game (`firstmoves.jsonl`) | `plusfish first-moves` |
| (6) | diversity, the new pieces' counts and places, front-row occupancy | `tools/balance/run15_analyse.py` (reads run 14's B folder for the comparison) |

- Server: `chessplus-sims`, c8g.16xlarge (64 Graviton4 cores), `--threads 64`.
  Game files (not in the repo): `Documents\ChessPlusSims\run15\`.
- Expected: about 2.5 hours, roughly $6.50 metered.

## Results

(pending)
