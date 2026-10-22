# Plusfish Elo log

Every engine change is measured against the build before it with
`plusfish enginematch` (random army pairs, each played twice from the same
opening with colours swapped; Elo from pair results, ±95%). Regimes:

* **nodes**: fixed nodes per move (6,000 unless noted), the self-play and
  eval-bar regime: strength per node.
* **time**: a clock per game (e.g. 10+0.1 s), so speed counts too.

Calibration: 12,000 vs 6,000 nodes = +112.5 ±14.4 (1000 games). Doubling
the nodes is worth roughly 110 Elo here, so a 2x speed-up at fixed time
should be worth about as much.

| # | Change | Regime | Games | Elo ±95% | Kept? |
|---|--------|--------|-------|----------|-------|
| 1 | Bad captures (rough exchange estimate; Ram counts as lost): ordered after killers, skipped in quiescence | nodes 6k | 982 | +33.4 ±13.8 | kept |
| 2 | History: penalties for quiet moves that didn't cut off, bounded updates; LMR reduces less for good history | nodes 6k | 8000 | +4.5 ±4.6 | kept (marginal) |
| 3 | Transposition table in quiescence (probe, cutoffs, store, hash move first) | nodes 6k | 1290 | +21.3 ±10.8 | kept |
| 4 | Internal iterative reduction (depth-1 when no hash move, depth >= 4) | nodes 6k | 8000 | +2.1 ±4.0 | reverted (no gain shown; retry deep) |
| 5 | Lazy SMP (shared hash table, helpers own history; odd helpers one ply deeper). UCI option Threads, analyse --threads | time 5+0.05, 4 threads vs 1 | 300 | +102.5 ±24.1 | kept |
| 6 | Counter-move ordering (quiet reply that last refuted the previous move) | nodes 6k | 7394 | +5.9 ±4.5 | kept |
| 7 | Null move reduction grows with (eval - beta)/200, up to +3 | nodes 6k | 6608 | +0.7 ±3.4 | reverted (SPRT H0) |
| 8 | Mobility with ray bit masks instead of square-by-square walks (same eval) | speed (bench nps) | - | 0.94x with default target, 1.05x with x86-64-v2 | reverted for now |
| 9 | "Improving" (static eval vs two plies ago): reverse futility and late-move pruning adapt | nodes 6k | 3998 | +9.0 ±6.5 | kept |
| 10 | Futility pruning of quiet moves (static eval + 100 + 120*depth <= alpha, depth <= 3) | nodes 6k | 1266 | +22.0 ±11.5 | kept |
| 11 | Prune bad captures in the main search (gain < -120*depth, depth <= 4) | nodes 6k | 1200 | -18.0 ±11.5 | reverted |
| 12 | LMR: +1 when not improving, -1 for killers/counter-moves | nodes 6k | 4258 | -3.0 ±6.0 | reverted (SPRT H0) |
| 13 | Eval: "threatened" term, pieces attacked by a cheaper enemy piece (-30 mg / -25 eg, hand-set) | nodes 6k | 1122 | +21.7 ±12.1 | kept |
| 14 | Use a root move from an unfinished iteration if it was fully searched and beat the window | nodes 6k | 5128 | +6.0 ±4.7 | kept |
| 15 | Eval: extra term for threatened pieces of the side not to move | nodes 6k | 8000 | +1.6 ±4.4 | reverted |
| 16 | Eval: king-zone attacks squared (-1.5 mg) | nodes 6k | 8000 | +1.3 ±4.4 | reverted |
| 17 | Time management: soft target (left/35 + 3/4 inc), hard limit up to 4x; stop early when the best move is stable, later when it keeps changing | time 10+0.1 | 512 | +30.6 ±17.1 | kept |
| 18 | Static exchange evaluation (full capture sequence on the square, least valuable first; cannons' screens, Rams, shields, leapers) replaces the rough estimate; see-check command compares it with brute force (99.3% same sign, the rest pins/checks) | nodes 6k | 1298 | +20.6 ±10.8 | kept |
| 19 | Prune captures with SEE < -120*depth near the leaves (retry of #11 with the real SEE) | nodes 6k | 6900 | +6.3 ±4.7 | kept |
| 20 | Prune quiet moves whose SEE < -50*depth^2 near the leaves | nodes 6k | 5218 | +6.3 ±5.4 | kept |
| 21 | Bound quiescence check chains (evasions only in the first 6 quiescence plies) + node-limit safety net at depth 1; ported from plusfish-army-pool (it fixes a hang) | nodes 6k, random / pool | 4000 / 2000 | 0.0 ±4.7 / +2.6 ±4.2 | kept (safety fix) |

## Checkpoint: build after #20 vs the starting engine (base1)

| Regime | Games | Elo ±95% |
|--------|-------|----------|
| 6,000 nodes/move (self-play) | 2000 | +114.1 ±10.9 |
| 20,000 nodes/move (web eval bar) | 2000 | +106.4 ±10.1 |
| 150,000 nodes/move (PC eval bar) | 800 | +84.6 ±14.4 |
| clock 10+0.1 s, 1 thread | 800 | +81.8 ±14.1 |

Lazy SMP adds to the clock result on top: 4 threads vs 1 = +102.5 ±24.1 (#5).
| 22 | Hash table in buckets of two entries (replace the shallower/older one) | time 10+0.1 | 800 | +14.8 ±12.5 | kept (SPRT undecided at the game limit; range excludes 0) |
| 23 | Re-tune the per-piece weights (material, mobility per piece type, shield, ability) on 20,680 self-play games with all 30 pieces (`tune --only mat,mob,shield,ability`); the 11 new pieces had only cost-based values and every mobility weight was the same 3.1 | nodes 6k / nodes 20k | 2000 / 500 | +74.6 ±11.0 / +100.7 ±23.2 | kept |
| 24 | Eval: per-piece "worth while the armies are whole" term (fades out over the first 8 captures), tuned with the rest | start-check (below) | - | no better than #23 | reverted |
| 25 | Full re-tune (every feature) instead of #23 | start-check (below) | - | same on random armies, worse on the pool; pawn-advance weights came out jagged | not used |
| 26 | Eval: where pieces stand. Per piece type: `reach` (squares reached from its square on an empty board, minus the average), `row0`..`row7` (pieces that don't promote) and `dead` (a square it can never leave: a Berserker on the last row, prior -90% of its material); tuned with mat,mob,shield,ability on the 24,000 balance games (8,000 nodes), only for one-directional pieces (Berserker, Assassin, Cavalry, Ghost, Werewolf + wolf, Vampire) and short-range ones (Knight, Man, Elephant, Paladin, Catapult, Rogue, Squire, Jester, Necromancer, King). A dead Berserker went from 2.6 points (middlegame) to 0.8 | nodes 6k random / PR #13 pool; nodes 20k random / pool | 2000 / 2000; 1000 / 1000 | +47.2 ±10.5 / +69.9 ±11.6; +69.7 ±14.3 / +73.3 ±15.1 | kept |
| 27 | Speed: quiet-move pruning decided before the move is made (skipped unmade when surely legal and surely not check), the hash move searched before the other moves are generated, a capture's exchange worked out only when it comes up, searched quiet moves skip the legality/check tests when sure | bench nps / time movetime 100 / time 10+0.1 / nodes 6k | - / 1000 / 400 / 2000 | 1.34x / +44.4 ±13.0 / +25.2 ±19.3 / +8.2 ±8.6 | kept |
| 28 | Correction history (material, pawns, each side's pieces, last move; gravity updates, corrects the main search and quiescence's stand-pat) | nodes 6k / nodes 40k | 1000 / 600 | +37.7 ±13.1 / +46.0 ±14.7 | kept |
| 29 | Capture history + continuation history one ply back (by piece kind and square, from the mover's side) | nodes 6k (2 seeds) / nodes 40k | 4000 / 600 | +12.7 ±6.3 / +10.4 ±14.9 | kept |
| 30 | Singular extensions (depth >= 7, margin 2*depth, at (depth-1)/2) + multi-cut + negative extension | nodes 6k / nodes 40k | ~900 / 1400 | -1.2 ±11.8 / +9.4 ±10.6 | kept (deep searches; see #33) |
| 31 | Internal iterative reduction, PV + expected-cut nodes (retry of #4) | nodes 6k / nodes 40k / 40k on top of #30 | 2750 / 400 / 300 | +1.0 ±7.2 / +20.0 ±18.4 / 0.0 ±22.0 | not kept |
| 32 | Search constants as UCI options + `plusfish spsa`; SPSA-tuned values (31 constants) on the #26 search | nodes 6k / nodes 40k | 4300 / 600 | +5.8 ±6.2 / 0.0 ±15.7 | tool kept, values not |
| 33 | #27 + #28 + #29 + #30 together (each measured on top of the ones before it): #27+#28+#29 vs the #26 build; #29 on top of #27+#28; #30 on top of the rest | nodes 6k / nodes 6k / nodes 40k | 2000 / 3000 / 1500 | +35.6 ±9.5 / +7.8 ±7.6 / +13.4 ±10.0 | kept |
| 34 | SPSA re-tune of 27 constants on #33 (12,000 pairs at 6k, whole-number depth limits and singular-extension settings fixed) | nodes 6k | 6000 | +1.6 ±5.3 | not kept (the constants were already about right) |
| 35 | Opening terms (`omat`, `omob`, `oreach`, `orow1`, `oability` per piece, `otempo`; each times the share of pieces not yet moved), tuned on the first 40 plies of 9,000 `drift` games (three runs: the base engine's, the first opening weights', and one with half its armies from the meta pool) labelled by the later scores (plies +16..+40), nothing else changed; see reports/START_EVAL.md. First weights (one run) vs base: +21.9 ±11.2 at 6k. Kept build vs base: | nodes 6k / nodes 20k / nodes 20k, meta pool | 2000 / 1200 / 1000 | +34.7 ±10.4 / +43.1 ±13.4 / +6.6 ±12.2 (no Vampires and few pawns in the pool) | kept |

## Checkpoint: build after #33 vs the build after #26 (fork main)

| Regime | Games | Elo ±95% |
|--------|-------|----------|
| 6,000 nodes/move (self-play) | 2000 | +29.8 ±9.5 |
| 20,000 nodes/move (web eval bar), random armies | 1000 | +57.9 ±13.6 |
| 20,000 nodes/move, the PR #13 meta pool | 1000 | +55.4 ±14.0 |
| 150,000 nodes/move (PC eval bar) | 600 | +83.2 ±16.0 |
| clock 10+0.1 s, 1 thread | 600 | +79.5 ±16.8 |

The gain grows with the search: most of it comes from correction history and
singular extensions, which do more the deeper the search goes. 400,000-node
searches (the PC bot) run 1.1-1.4x the nodes/s they did (six random army
positions).

Variants of #26 against the build before it (6,000 nodes, 2000 games each, random armies / the PR #13 meta pool):

| Variant | Random | Pool |
|---|---|---|
| Re-tune mat,mob,shield,ability only (control, no positional terms) | -7.1 ±8.6 | +5.2 ±10.7 |
| `reach` only, other weights as they were | +23.3 ±9.5 | - |
| `reach` + rows for every piece, other weights as they were | +30.1 ±10.2 | - |
| `reach` + rows for every piece, re-tuned with the rest | +47.4 ±10.2 | - |
| ... + `dead`, every piece | +52.2 ±10.6 | +62.5 ±11.2 |
| ... + `dead`, one-directional pieces only | +32.9 ±9.9 | +74.1 ±11.1 |
| ... + `dead`, one-directional + short-range (kept) | +47.2 ±10.5 | +69.9 ±11.6 |

Kept against every piece, head to head (3000 games each): +3.9 ±7.7 random, +7.5 ±8.3 pool, with half as many weights.

## Judging the starting position (`start-check`)

186 army pairings played 40 times each (20 per colour, 6,000 nodes) for the
truth: 150 random pairs drawn from all 30 pieces, plus the old 8-army pool
with Standard. Correlation of each engine's start score (both colours
averaged) with the real result; the noise ceiling is 0.98.

| Weights | random pairs @1 node | @20,000 | right army when clear (@20k) | pool + Standard @20,000 |
|---|---|---|---|---|
| before #23 | 0.55 | 0.62 | 78% | 0.59 |
| #23 (kept) | 0.77 | 0.84 | 97% | 0.61 |
| #24 (+ opening term) | 0.76 | 0.84 | 97% | 0.52 |
| #25 (full re-tune) | 0.77 | 0.83 | 97% | 0.50 |

With only the 19 old pieces, the starting engine (base1) and the build after
#22 judged random pairs the same (0.84 vs 0.85 at 20,000 nodes): the search
work didn't change opening judgement; valuing the new pieces did.

### Drift test (#35, reports/START_EVAL.md)

2,000 held-out `drift` games (random full-budget armies, top move every turn
at 40,000 nodes; 1,000 more with meta pool armies: Brier 0.1181 -> 0.1039 at
20,000 nodes): start score vs the result (Brier, lower is better) and vs
the game's own later scores (plies 16-40, squared error in win chance).

| Start score | Brier | Error vs later | Corr. with later |
|---|---|---|---|
| before #35 @20,000 / @150,000 / @1,000,000 | 0.1395 / 0.1371 / 0.1346 | 0.0179 / 0.0161 / 0.0147 | 0.83 / 0.85 / 0.86 |
| #35 @20,000 / @150,000 / @1,000,000 | 0.1194 / 0.1180 / 0.1175 | 0.0126 / 0.0116 / 0.0109 | 0.88 / 0.89 / 0.89 |

`start-check` (150 random pairs + the meta pool and Standard, 40 games a
matchup at 6,000 nodes, seed 11), correlation with the real result / right
side when clear:

| Start score | random @20,000 | random @150,000 | pool + Standard @20,000 | @150,000 |
|---|---|---|---|---|
| before #35 | 0.63 / 76% | 0.65 / 78% | 0.73 / 94% | 0.77 / 94% |
| #35 | 0.73 / 85% | 0.75 / 89% | 0.73 / 94% | 0.77 / 94% |
| #35 trained on the two random-army runs only | 0.73 / 84% | 0.75 / 89% | 0.72 / 94% | 0.75 / 94% |

Also tried: scaling the opening terms down to match the later scores (closer
to them, further from the results: not kept), labels mixed with the result
(Brier 0.1184, error vs later 0.0136: not kept), training on plies 0-10 / 0-20
/ 0-60 instead of 0-40 (no better), re-tuning every piece's material,
mobility, shield and ability weights the same way (no better), and the
average of the last two search depths as the score (no better).

## The eval-bar meta pool (`meta`, reports/META_POOL.md)

10 armies grown by `plusfish meta` with the #23 weights. #23 against the
build before it, on that pool: **+107.5 ±19.0** (6,000 nodes, 1000 games).
start-check on the pool + Standard (55 pairings, 40 games each): correlation
0.79 at 20,000 nodes with #23, 0.41 before it.
