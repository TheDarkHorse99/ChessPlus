# Balance run 5: the front-row rule (AWS sims server, 22 October 2026)

Candidate rule against first-move captures (run 3 found they cause White's
extra edge; run 4's Quiet first move made it worse): **no piece may start able
to capture anything on the opponent's two starting rows**, checked as if
those rows were full (the army plays White against 16 Men there and may have
no capture or Crack Shot at all). Tested in Plusfish only: with
`--front-row-rule=true` self-play's random armies follow it (branch
`experiment/front-row-rule`, commit 90b0dce). Not a game rule. Full tables in
`report.md` (`tools/balance/run5_analyse.py`).

| Part | What | Settings |
|---|---|---|
| 1 | Run 2's random-army self-play, every army following the rule | 20,000 games, 8,000 nodes, seed 101, selfplay defaults (as run 2) |
| 2 | Each army against itself: 20 armies following the rule, 20 from run 2 | `plusfish analyse`, 2,000,000 nodes, 8 threads (`mirror.txt`) |

- Server: `chessplus-sims` (c8g.16xlarge, 64 cores). Games 06:41-06:50 UTC;
  server on 06:39-06:51, about $0.49, stopped through AWS. The script is
  `tools/balance/run5_server.sh` on the experiment branch. Game files (not in
  the repo): `Documents\ChessPlusSims\run5\`.
- 24.1% of Plusfish's random armies followed the rule (they're laid out at
  random, not built for it).

## Result: White's edge comes down to chess level

| | No rule (run 2) | Front-row rule | Chess |
|---|---|---|---|
| White's score | 56.1% | **52.0%** (51.4-52.6) | 54-56% (strong players) |
| White won both games of a swapped pair | 12.6% | **10.1%** | 23% |
| Army against itself: median | +0.32 | **+0.26** | +0.29 (top engines +0.20 to +0.35) |
| ... within +0.35 | 9 of 18 | **17 of 20** | |
| ... over +1 pawn | 6 of 18 (incl. a forced mate) | **none** (highest +0.79) | |
| White's first move captures or uses an ability | 23.5% | 2.3% (all Full Moon, no captures) | |

Draws 22.7% -> 22.0%; games a little longer (128 -> 135 plies).
